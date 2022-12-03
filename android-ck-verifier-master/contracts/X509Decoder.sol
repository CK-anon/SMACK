// SPDX-License-Identifier: MIT
// Adapted from
// https://github.com/JonahGroendal/x509-forest-of-trust/blob/master/contracts/X509ForestOfTrust.sol
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@ensdomains/ens-contracts/contracts/dnssec-oracle/BytesUtils.sol";
import "@ensdomains/ens-contracts/contracts/dnssec-oracle/algorithms/Algorithm.sol";
import "./Asn1Decode.sol";
import "./ENSNamehash.sol";
import "./DateTime.sol";

// Debugging
import "hardhat/console.sol";

/**
 * @dev A contract that attests to proofs of complete knowledge
 */
interface ICKVerifier {
    /**
     * @dev Returns true if the address has shown a proof of complete knowledge
     * to this verifier.
     */
    function isCKVerified(address addr) external returns (bool);
}

/*
 * @dev Stores validated X.509 certificate chains in parent pointer trees.
 * @dev The root of each tree is a CA root certificate
 */
contract X509Parser is Ownable, ICKVerifier {
  using Asn1Decode for bytes;
  using ENSNamehash for bytes;

  bytes10 constant private OID_SUBJECT_ALT_NAME   = 0x551d1100000000000000;
  bytes10 constant private OID_BASIC_CONSTRAINTS  = 0x551d1300000000000000;
  bytes10 constant private OID_NAME_CONSTRAINTS   = 0x551d1e00000000000000;
  bytes10 constant private OID_KEY_USAGE          = 0x551d0f00000000000000;
  bytes10 constant private OID_EXTENDED_KEY_USAGE = 0x551d2500000000000000;
  
  // Android key attestation OIDs
  bytes10 constant private OID_ANDROID_KEY_STORE  = 0x2b06010401d679020111;

  constructor(address ecdsaWithSHA256, address _dateTime) {
    // sha256WithRSAEncryption defined in RFC-8017
    // bytes32 algOid = 0x2a864886f70d01010b0000000000000000000000000000000000000000000000;
    // ecdsa-with-SHA256 defined in RFC-5754
    bytes32 algOid = 0x2a8648ce3d040302000000000000000000000000000000000000000000000000;
    algs[algOid] = Algorithm(ecdsaWithSHA256);
    dateTime = DateTime(_dateTime);
  }

  struct KeyUsage {
    bool critical;
    bool present;
    uint16 bits;              // Value of KeyUsage bits. (E.g. 5 is 000000101)
  }
  struct ExtKeyUsage {
    bool critical;
    bool present;
    bytes32[] oids;
  }
  struct Certificate {
    address owner;
    bytes32 parentId;
    uint40 timestamp;
    uint160 serialNumber;
    uint40 validNotBefore;
    uint40 validNotAfter;
    bool cA;                  // Whether the certified public key may be used to verify certificate signatures.
    uint8 pathLenConstraint;  // Maximum number of non-self-issued intermediate certs that may follow this
                              // cert in a valid certification path.
    KeyUsage keyUsage;
    ExtKeyUsage extKeyUsage;
  }
  
  /**
   * @dev Add a X.509 certificate to an existing tree/chain
   * @param cert A DER-encoded X.509 certificate
   * @param certParams The parent certificate's DER-encoded public key
   */
  
  struct ParentParams {
    bytes pubKey;
    bool verified;
  }
  
  struct CertParams {
    ParentParams parent;
    address proverAddress;
  }

  mapping (bytes32 => Certificate) private certs;     // certId => cert  (certId is keccak256(pubKey))
  mapping (bytes32 => Algorithm)   private algs;      // algorithm oid bytes => signature verification contract
  mapping (bytes32 => bytes32[])   public  toCertIds; // ensNamehash(subjectAltName) => certId
  mapping (bytes32 => bytes32)     public  toCertId;  // sha256 fingerprint => certId
  DateTime dateTime;                                  // For dateTime conversion
  
  // Trusted by the contract owner
  mapping (bytes32 => bool)        public  trustedKeys;
  // Untrusted by the contract owner; revocation list
  mapping (bytes32 => bool)        public  revokedKeys;
  mapping (address => bool)        public  isCKVerified;

  event CertAdded(bytes32);
  event CertClaimed(bytes32, address);
  event AlgSet(bytes32, address);
  
  /**
   * @dev Mark a key as trusted. Certificates signed by this key are considered
   * trusted unless they have been revoked.
   * @param pubKey List of public keys to trust
   * @param trust If true, trust these keys. If false, do not trust
   *    these keys by themselves.
   */
  function setTrustedKeys(bytes[] calldata pubKey, bool trust) public onlyOwner {
    for (uint i = 0; i < pubKey.length; i++) {
      trustedKeys[keccak256(pubKey[i])] = trust;
    }
  }
  
  /**
   * @dev Mark a key as revoked. Certificates signed by this key are considered
   * invalid.
   * @param pubKey List of public keys to revoke
   * @param revoke If true, revoke these keys. If false, allow them to be used
   *    in a chain of trust.
   */
  function setRevokedKeys(bytes[] calldata pubKey, bool revoke) public onlyOwner {
    for (uint i = 0; i < pubKey.length; i++) {
      revokedKeys[keccak256(pubKey[i])] = revoke;
    }
  }
  
  function checkParentTrusted(ParentParams memory parent) public view {
    if (!parent.verified) {
      parent.verified = trustedKeys[keccak256(parent.pubKey)];
      require(parent.verified, "Certificate chain not trusted");
    }
    require(!revokedKeys[keccak256(parent.pubKey)], "Parent public key revoked");
  }
  
  /**
   * @dev Verify a certificate chain ending in a lightweight CK proof
   * @param certChain Certificate chain to verify, starting with the attestation cert
   * @param parentPubKey The public key of the trusted parent certificate
   * @param proverAddress Address the proof is for
   */
  function verifyCertChain(bytes[] calldata certChain, bytes calldata parentPubKey, address proverAddress) public {
    ParentParams memory parent;
    parent.pubKey = parentPubKey;
    parent.verified = false;
    for (int i = int256(certChain.length) - 1; i >= 1; i--) {
      parent.pubKey = addCertToChain(certChain[uint256(i)], parent);
      parent.verified = true;
    }
    CertParams memory certParams;
    certParams.parent = parent;
    certParams.proverAddress = proverAddress;
    addKeyCert(certChain[0], certParams);
    isCKVerified[proverAddress] = true;
  }
  
  /**
   * @dev Verify a certificate is signed with a verified parent public key
   * @param cert Certificate to verify
   * @param parent The public key of the parent certificate and if the parent key
   * has been linked to a root of trust
   * @return Public key of this certificate
   */
  function addCertToChain(bytes memory cert, ParentParams memory parent) public view returns (bytes memory) {
    checkParentTrusted(parent);
    Certificate memory certificate;
    // Certificate root
    uint node1 = cert.root();
    // tbsCertificate (TBSCertificate)
    node1 = cert.firstChildOf(node1);
    // |-- Version
    uint node2 = cert.firstChildOf(node1);
    require(cert.uintAt(cert.firstChildOf(node2)) + 1 == 3, "Certificate must be X.509 Version 3");
    node2 = cert.nextSiblingOf(node2);
    // signature node (AlgorithmIdentifier)
    node2 = cert.nextSiblingOf(node2);
    node2 = cert.firstChildOf(node2);
    // signatureValue node (BIT STRING)
    uint node3 = cert.nextSiblingOf(node1);
    node3 = cert.nextSiblingOf(node3);
    
    Algorithm algAddress = algs[cert.bytes32At(node2)];
    require(address(algAddress) != address(0x0), "Algorithm unknown");
    
    // Parse signature
    node2 = cert.rootOfBitStringAt(node3);
    node2 = cert.firstChildOf(node2);
    require(algAddress.verify(bytes.concat(bytes4(0x00000000), parent.pubKey),
        cert.allBytesAt(node1),
        bytes.concat(cert.uintBytesAt(node2), cert.uintBytesAt(cert.nextSiblingOf(node2)))),
        "Intermediate signature doesn't match");
    
    node1 = cert.firstChildOf(node1);
    node1 = cert.nextSiblingOf(node1);
    node1 = cert.nextSiblingOf(node1);
    node1 = cert.nextSiblingOf(node1);
    node1 = cert.nextSiblingOf(node1);
    
    // Now at validity (Validity)
    node2 = cert.firstChildOf(node1);
    // Check notBefore
    certificate.validNotBefore = uint40(toTimestamp(cert.bytesAt(node2)));
    require(certificate.validNotBefore <= block.timestamp, "Now is before validNotBefore");
    node2 = cert.nextSiblingOf(node2);
    // Check notAfter
    certificate.validNotAfter = uint40(toTimestamp(cert.bytesAt(node2)));
    require(block.timestamp <= certificate.validNotAfter, "Now is after validNotAfter");

    // subject (Name)
    node1 = cert.nextSiblingOf(node1);
    // subjectPublicKeyInfo (SubjectPublicKeyInfo)
    node1 = cert.nextSiblingOf(node1);
    
    node2 = cert.firstChildOf(node1);
    node2 = cert.nextSiblingOf(node2);
    
    // Get this certificate's public key
    bytes memory certPublicKey = cert.bitstringAt(node2);
    require(certPublicKey.length == 65, "Public key length incorrect");
    // Cut off the 0x04 (indicating it is an uncompressed EC public key)
    return BytesUtils.substring(certPublicKey, 1, 64);
  }

  /**
   * @dev Add a X.509 certificate to an existing tree/chain
   * @param cert A DER-encoded X.509 certificate
   * @param certParams A description of the certificate and intended address to verify
   */
  function addKeyCert(bytes memory cert, CertParams memory certParams)
  public view
  {
    checkParentTrusted(certParams.parent);
    Certificate memory certificate;
    uint node1;
    uint node2;
    uint node3;
    uint node4;

    certificate.parentId = keccak256(certParams.parent.pubKey);
    certificate.timestamp = uint40(block.timestamp);
    
    // Follow along with parsing the X.509 cert at
    // https://www.rfc-editor.org/rfc/rfc5280#section-4.1

    // Certificate root
    node1 = cert.root();
    // tbsCertificate (TBSCertificate)
    node1 = cert.firstChildOf(node1);
    // |-- Version
    node2 = cert.firstChildOf(node1);
    console.log("Version %d", NodePtr.ixl(node2));
    console.log("Bytes at version");
    console.logBytes(cert.bytesAt(node2));
    console.logBytes(cert.allBytesAt(node2));
    
    console.log("X.509 Version is %d", cert.uintAt(cert.firstChildOf(node2)) + 1);
    require(cert.uintAt(cert.firstChildOf(node2)) + 1 == 3, "Certificate must be X.509 Version 3");
    node2 = cert.nextSiblingOf(node2);
    
    // Extract serial number
    certificate.serialNumber = uint160(cert.uintAt(node2));
    console.log("Serial number (often 1 for Android TEEs):");
    console.logBytes20(bytes20(certificate.serialNumber));
    
    // signature node (AlgorithmIdentifier)
    node2 = cert.nextSiblingOf(node2);
    node2 = cert.firstChildOf(node2);
    // signatureValue node (BIT STRING)
    node3 = cert.nextSiblingOf(node1);
    node3 = cert.nextSiblingOf(node3);
    
    Algorithm algAddress = algs[cert.bytes32At(node2)];
    console.log("Alg address: %s", address(algAddress));
    console.logBytes32(cert.bytes32At(node2));
    require(address(algAddress) != address(0x0), "Algorithm unknown");
    
    // Read signature details
    console.log("Length of cert: %d", cert.allBytesAt(node1).length);
    
    // Parse the signature bit string
    // NOTE: ECDSA requires a specific parsing structure. In the future,
    // the signature parameters could be parsed in an algorithm-agnostic way.
    node2 = cert.rootOfBitStringAt(node3);
    node2 = cert.firstChildOf(node2);
    console.log("rs_0");
    console.logBytes(cert.uintBytesAt(node2));
    console.log("rs_1");
    console.logBytes(cert.uintBytesAt(cert.nextSiblingOf(node2)));
    
    console.log("Cert bytes");
    console.logBytes(cert.allBytesAt(node1));
    console.log("sig bytes");
    console.logBytes(bytes.concat(cert.uintBytesAt(node2), cert.uintBytesAt(cert.nextSiblingOf(node2))));
    console.log("pub key bytes");
    console.logBytes(certParams.parent.pubKey);
    
    // verify(pubkey, data, signature)
    {
    require(algAddress.verify(bytes.concat(bytes4(0x00000000), certParams.parent.pubKey), cert.allBytesAt(node1),
        bytes.concat(cert.uintBytesAt(node2), cert.uintBytesAt(cert.nextSiblingOf(node2)))),
    "Signature doesn't match");
    }
    
    console.log("Verification passed!");

    node1 = cert.firstChildOf(node1);
    node1 = cert.nextSiblingOf(node1);
    node1 = cert.nextSiblingOf(node1);
    node1 = cert.nextSiblingOf(node1);
    node1 = cert.nextSiblingOf(node1);
    
    // Now at validity (Validity)
    node2 = cert.firstChildOf(node1);
    // Check notBefore
    certificate.validNotBefore = uint40(toTimestamp(cert.bytesAt(node2)));
    require(certificate.validNotBefore <= block.timestamp, "Now is before validNotBefore");
    node2 = cert.nextSiblingOf(node2);
    // Check notAfter
    certificate.validNotAfter = uint40(toTimestamp(cert.bytesAt(node2)));
    require(block.timestamp <= certificate.validNotAfter, "Now is after validNotAfter");

    // subject (Name)
    node1 = cert.nextSiblingOf(node1);
    // subjectPublicKeyInfo (SubjectPublicKeyInfo)
    node1 = cert.nextSiblingOf(node1);
    
    /*
    bytes32 certId;
    // Get public key and calculate certId from it
    certId = cert.keccakOfAllBytesAt(node1);
    // Cert must not already exist
    // Prevents duplicate references and owner from being overridden
    require(certs[certId].validNotAfter == 0);
    // Fire event
    emit CertAdded(certId);

    // Add reference from sha256 fingerprint
    toCertId[sha256(cert)] = certId;
    */

    node1 = cert.nextSiblingOf(node1);

    // Skip over v2 fields
    if (cert[NodePtr.ixs(node1)] == 0xa1)
      node1 = cert.nextSiblingOf(node1);
    if (cert[NodePtr.ixs(node1)] == 0xa2)
      node1 = cert.nextSiblingOf(node1);

    // Parse extensions
    if (cert[NodePtr.ixs(node1)] == 0xa3) {
      console.log("Reading extension");
      node1 = cert.firstChildOf(node1);
      node2 = cert.firstChildOf(node1);
      bytes10 oid;
      //bool isCritical;
      while (Asn1Decode.isChildOf(node2, node1)) {
        node3 = cert.firstChildOf(node2);
        oid = bytes10(cert.bytes32At(node3)); // Extension oid
        console.log("OID:");
        console.logBytes10(oid);
        node3 = cert.nextSiblingOf(node3);
        // Check if extension is critical
        /*isCritical = false;
        if (cert[NodePtr.ixs(node3)] == 0x01) { // If type is bool
          if (cert[NodePtr.ixf(node3)] != 0x00) // If not false
            isCritical = true;
          node3 = cert.nextSiblingOf(node3);
        }*/
        /*
        if (oid == OID_SUBJECT_ALT_NAME) {
          // Add references from names
          node3 = cert.rootOfOctetStringAt(node3);
          node4 = cert.firstChildOf(node3);
          while (Asn1Decode.isChildOf(node4, node3)) {
            if(cert[NodePtr.ixs(node4)] == 0x82)
              toCertIds[cert.bytesAt(node4).namehash()].push(certId);
            else
              toCertIds[cert.keccakOfBytesAt(node4)].push(certId);
            node4 = cert.nextSiblingOf(node4);
          }
        }
        else if (oid == OID_BASIC_CONSTRAINTS) {
          if (isCritical) {
            // Check if cert can sign other certs
            node3 = cert.rootOfOctetStringAt(node3);
            node4 = cert.firstChildOf(node3);
            // If sequence (node3) is not empty
            if (Asn1Decode.isChildOf(node4, node3)) {
              // If value == true
              if (cert[NodePtr.ixf(node4)] != 0x00) {
                certificate.cA = true;
                node4 = cert.nextSiblingOf(node4);
                if (Asn1Decode.isChildOf(node4, node3)) {
                  certificate.pathLenConstraint = uint8(cert.uintAt(node4));
                }
                else {
                  certificate.pathLenConstraint = uint8(0xff);
                }
              }
            }
          }
        }
        else if (oid == OID_KEY_USAGE) {
          certificate.keyUsage.present = true;
          certificate.keyUsage.critical = isCritical;
          node3 = cert.rootOfOctetStringAt(node3);
          bytes3 v = bytes3(cert.bytes32At(node3)); // The encoded bitstring value
          certificate.keyUsage.bits = ((uint16(uint8(v[1])) << 8) + uint16(uint8(v[2]))) >> 7;
          console.log("Key usage"); 
        }
        else if (oid == OID_EXTENDED_KEY_USAGE) {
          certificate.extKeyUsage.present = true;
          certificate.extKeyUsage.critical = isCritical;
          node3 = cert.rootOfOctetStringAt(node3);
          node4 = cert.firstChildOf(node3);
          uint len;
          while (Asn1Decode.isChildOf(node4, node3)) {
            len++;
            node4 = cert.nextSiblingOf(node4);
          }
          bytes32[] memory oids = new bytes32[](len);
          node4 = cert.firstChildOf(node3);
          for (uint i; i<len; i++) {
            oids[i] = cert.bytes32At(node4);
            node4 = cert.nextSiblingOf(node4);
          }
          certificate.extKeyUsage.oids = oids;
        }
        */
        if (oid == OID_ANDROID_KEY_STORE) {
          node3 = cert.rootOfOctetStringAt(node3);
          
          // Follow along at
          // https://developer.android.com/training/articles/security-key-attestation#certificate_schema
          
          // attestationVersion
          node4 = cert.firstChildOf(node3);
          console.log("Attestation version: %d", cert.uintAt(node4));
          require(cert.uintAt(node4) == 200, "Attestation version must be 200 for this contract");
          
          // attestationSecurityLevel
          node4 = cert.nextSiblingOf(node4);
          console.log("KeyStore version: %d", cert.enumAt(node4));
          require(cert.enumAt(node4) >= 1, "Software KeyStore not allowed; a hardware TEE is required.");
          
          // keyMintVersion
          node4 = cert.nextSiblingOf(node4);
          console.log("KeyMint version: %d", cert.uintAt(node4));
          require(cert.uintAt(node4) == 200, "KeyMint version must be 200 for this contract");
          
          // keyMintSecurityLevel
          node4 = cert.nextSiblingOf(node4);
          console.log("KeyMint security level: %d", cert.enumAt(node4));
          require(cert.enumAt(node4) >= 1, "Key must be stored in a hardware TEE");
          
          // attestationChallenge (OCTET_STRING)
          node4 = cert.nextSiblingOf(node4);
          bytes memory sigBytes = cert.bytesAt(node4);
          console.log("Byte length: %d", sigBytes.length);
          address signer = ecrecover(
            keccak256("\x19Ethereum Signed Message:\n23Android CK Verification"),
            // v
            BytesUtils.readUint8(sigBytes, 64),
            // r
            BytesUtils.readBytes32(sigBytes, 0),
            // s
            BytesUtils.readBytes32(sigBytes, 32));
          require(certParams.proverAddress == signer, "Invalid signature for intended address");
          
          // uniqueId OCTET_STRING - empty for non-system apps
          node4 = cert.nextSiblingOf(node4);
          
          // softwareEnforced (AuthorizationList)
          node3 = cert.nextSiblingOf(node4);
          
          // Read AuthorizationList sequence of OIDs
          node4 = cert.firstChildOf(node3);
          uint id = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
          do {
            console.log("ixs: %d", NodePtr.ixs(node4));
            (id, node4) = cert.readTag(node4);
            if (id == 701) {
              // Not created in the future
              node4 = cert.firstChildOf(node4);
              require(cert.uintAt(node4) / 1000 <= block.timestamp, "Certificate creation datetime in the future!");
            } else if (id == 709) {
              // attestationApplicationId
              console.log("ID IN HERE");
              node4 = cert.firstChildOf(node4);
              require(keccak256(cert.bytesAt(node4))
                == 0x0dba4f607b0913140a4b44135a0ae98acc128770d2cf9fa877c26637c277ef07,
                "Created from an invalid application");
            }
            
            console.log("id: %d", id);
            console.log("it: %d %d", NodePtr.ixl(node4), NodePtr.ixl(node3));
            if (NodePtr.ixl(node4) >= NodePtr.ixl(node3)) {
              break;
            }
            // NOTE: The following line corrupts the .ixf and .ixl parts of the pointer
            // because there is not always a valid length (e.g. for long tags)
            // readTag only uses .ixs, so this is okay.
            node4 = cert.nextSiblingOf(node4);
          } while (true);
          
          // teeEnforced (AuthorizationList)
          console.log("Completed");
        }
        /*
        Don't save any extra data on-chain
        else if (isCritical && certificate.extId == bytes32(0)) {
          // Note: unrecognized critical extensions are allowed.
          // Further validation of certificate is needed if extId != bytes32(0).
          // Save hash of extensions
          certificate.extId = cert.keccakOfAllBytesAt(node1);
        }
        */
        node2 = cert.nextSiblingOf(node2);
      }
    }
    return;

    // TODO: Handle 4.2.1.9. of RFC 5280 (cert constraints)
  }

  function rootOf(bytes32 certId) external view returns (bytes32) {
    bytes32 id = certId;
    while (id != certs[id].parentId) {
      id = certs[id].parentId;
    }
    return id;
  }

  function owner(bytes32 certId) external view returns (address) {
    return certs[certId].owner;
  }

  function parentId(bytes32 certId) external view returns (bytes32) {
    return certs[certId].parentId;
  }

  function timestamp(bytes32 certId) external view returns (uint40) {
    return certs[certId].timestamp;
  }

  function serialNumber(bytes32 certId) external view returns (uint160) {
    return certs[certId].serialNumber;
  }

  function validNotBefore(bytes32 certId) external view returns (uint40) {
    return certs[certId].validNotBefore;
  }

  function validNotAfter(bytes32 certId) external view returns (uint40) {
    return certs[certId].validNotAfter;
  }

  function basicConstraints(bytes32 certId) external view returns (bool, uint8) {
    return (certs[certId].cA, certs[certId].pathLenConstraint);
  }

  function keyUsage(bytes32 certId) external view returns (bool, bool[9] memory) {
    KeyUsage memory _keyUsage = certs[certId].keyUsage;
    uint16 mask = 256;
    bool[9] memory flags;
    if (_keyUsage.present) {
      for (uint i; i<9; i++) {
        flags[i] = (_keyUsage.bits & mask == mask);
        mask = mask >> 1;
      }
    }
    return (_keyUsage.present, flags);
  }

  function keyUsageCritical(bytes32 certId) external view returns (bool) {
    return certs[certId].keyUsage.critical;
  }

  function extKeyUsage(bytes32 certId) external view returns (bool, bytes32[] memory) {
    ExtKeyUsage memory _extKeyUsage = certs[certId].extKeyUsage;
    return (_extKeyUsage.present, _extKeyUsage.oids);
  }

  function extKeyUsageCritical(bytes32 certId) external view returns (bool) {
    return certs[certId].extKeyUsage.critical;
  }

  function toCertIdsLength(bytes32 _hash) external view returns (uint) {
    return toCertIds[_hash].length;
  }

  function toTimestamp(bytes memory x509Time) private view returns (uint) {
    uint16 yrs;  uint8 mnths;
    uint8  dys;  uint8 hrs;
    uint8  mins; uint8 secs;
    uint8  offset;

    if (x509Time.length == 13) {
      if (uint8(x509Time[0])-48 < 5) yrs += 2000;
      else yrs += 1900;
    }
    else {
      yrs += (uint8(x509Time[0])-48) * 1000 + (uint8(x509Time[1])-48) * 100;
      offset = 2;
    }
    yrs +=  (uint8(x509Time[offset+0])-48)*10 + uint8(x509Time[offset+1])-48;
    mnths = (uint8(x509Time[offset+2])-48)*10 + uint8(x509Time[offset+3])-48;
    dys +=  (uint8(x509Time[offset+4])-48)*10 + uint8(x509Time[offset+5])-48;
    hrs +=  (uint8(x509Time[offset+6])-48)*10 + uint8(x509Time[offset+7])-48;
    mins += (uint8(x509Time[offset+8])-48)*10 + uint8(x509Time[offset+9])-48;
    secs += (uint8(x509Time[offset+10])-48)*10 + uint8(x509Time[offset+11])-48;

    return dateTime.toTimestamp(yrs, mnths, dys, hrs, mins, secs);
  }

  function setAlg(bytes32 oid, address alg) external onlyOwner {
    algs[oid] = Algorithm(alg);
    emit AlgSet(oid, alg);
  }
}

