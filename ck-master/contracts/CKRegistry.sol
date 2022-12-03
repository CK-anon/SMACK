// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./SingleSlotBitArray.sol";

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

/**
 * @dev A registry containing addresses that have provided proofs of complete
 * knowledge.
 */
contract CKRegistry is Ownable {
    /**
     * @dev Maps addresses to a value containing the verifications. Up to 256
     * verification bits can be used per address to denote different verification
     * types.
     */
    mapping (address => SingleSlotBitArray.BitArray256) public verifications;
    
    /**
     * @dev A bit array denoting which verification bits are accepted as evidence
     * of a CK proof. This value can be updated to revoke proofs if a particular
     * CK verification method is deemed to be insecure in the future.
     *
     * If this value is set to 0 by the contract owner, then the `isCK` function would
     * not accept any verification type at all.
     *
     * Note that it is possible for verifier addresses to continue to set the
     * bits that are not trusted by this variable. This might be useful if
     * external contracts have different trust settings.
     */
    SingleSlotBitArray.BitArray256 public trustedVerificationBits;
    
    /**
     * @dev A mapping of addresses to verification bits (plus one). The default storage
     * slot value, 0, remains unprivileged.
     */
    mapping (address => uint256) public verifierAddresses;
    
    /**
     * @dev Emitted when an address becomes a verifier for a specific verification bit
     */
    event VerifierAssigned(address indexed verifier, uint8 indexed bit);
    
    /**
     * @dev Emitted when an address is removed from the verifiers set
     */
    event VerifierRemoved(address indexed verifier);
    
    /**
     * @dev Emitted when an address successfully sets a verification bit
     */
    event VerificationBitSet(
        address indexed userAddress,
        ICKVerifier indexed verifierAddress,
        uint8 indexed vBit
    );
    
    /**
     * @dev Returns whether a particular address has provided a proof of complete
     * knowledge per the current state of trust given by `trustedVerificationBits`.
     */
    function isCK(address addr) public view returns (bool) {
        return verifications[addr].storedValue & trustedVerificationBits.storedValue != 0;
    }
    
    /**
     * @dev Returns whether a particular address has provided a proof of complete
     * knowledge using any verifier at any time in the past.
     */
    function isCKAny(address addr) public view returns (bool) {
        return verifications[addr].storedValue != 0;
    }
    
    /**
     * @dev Sets a verification bit as trusted or not.
     */
    function trustVerificationBit(uint8 bit, bool trusted) public onlyOwner {
        SingleSlotBitArray.set(trustedVerificationBits, bit, trusted);
    }
    
    /**
     * @dev Assigns the power of setting a verification bit to an address. Note that
     * more than one address can be assigned to a single verification bit. Addresses
     * might share the same verification bit if they are very similar, e.g. for minor
     * contract upgrades.
     */
    function assignVerifierAddress(address verifierAddress, uint8 bit) public onlyOwner {
        verifierAddresses[verifierAddress] = uint256(bit) + 1;
        emit VerifierAssigned(verifierAddress, bit);
    }
    
    /**
     * @dev Revokes verification bit setting privileges from an address.
     *
     * Note: This function might be used without also removing the bit from
     * `trustedVerificationBits` when a certain verifier was known to produce
     * true results for previous verifications but is not guaranteed to do
     * so in the future.
     */
    function removeVerifierAddress(address verifierAddress) public onlyOwner {
        verifierAddresses[verifierAddress] = 0;
        emit VerifierRemoved(verifierAddress);
    }
    
    /**
     * @dev Assigns the verification bit of an address that has provided a
     * proof of complete knowledge to a verifier.
     */
    function registerCK(address userAddress, ICKVerifier verifierAddress) public {
        uint256 vBitPlusOne = verifierAddresses[address(verifierAddress)];
        require(vBitPlusOne > 0, "CKRegistry: Verifier address is not authorized");
        bool didVerify = verifierAddress.isCKVerified(userAddress);
        require(didVerify, "CKRegistry: Verifier needs proof");
        uint8 vBit = uint8(vBitPlusOne - 1);
        SingleSlotBitArray.set(verifications[userAddress], vBit, true);
        emit VerificationBitSet(userAddress, verifierAddress, vBit);
    }
}
