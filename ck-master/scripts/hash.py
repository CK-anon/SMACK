genTx0 = "01000000010000000000000000000000000000000000000000000000000000000000000000ffffffff2f02d301044381376305";
extraNonce1 = "deadc0de";
extraNonce2 = "b0";
genTx1 = "a9f0013bfed85f9f824cf64d79b71e0db1aa9471fd790f1b6cbad3222db9bf5200000000020000000000000000266a24aa21a9ede2f61c3f71d1defd3fa999dfa36953755c690689799962b48bebd836974e8cf900f2052a01000000160014475a44069a4288f3df3048fb12926f27c63f157900000000";
nonce = "02570730";
nbits = "1d00ffff"
nTime = "633780f7"
previousBlockHash = "000000000002ea8eb35b9df5a5f7d3f7182d5226e4e9ab5399fe7582f0f9a9de"
nversion = "20000000"

genTx0 = bytearray.fromhex(genTx0)
extraNonce1 = bytearray.fromhex(extraNonce1)
extraNonce2 = bytearray.fromhex(extraNonce2)
genTx1 = bytearray.fromhex(genTx1)
nonce = bytearray.fromhex(nonce)
nbits = bytearray.fromhex(nbits)
nTime = bytearray.fromhex(nTime)
previousBlockHash = bytearray.fromhex(previousBlockHash)
nversion = bytearray.fromhex(nversion)

# genTx0.reverse()
# extraNonce1.reverse()
# extraNonce2.reverse()
# genTx1.reverse()
nonce.reverse()
nbits.reverse()
nTime.reverse()
previousBlockHash.reverse()
nversion.reverse()

import hashlib
coinbaseBuffer = genTx0 +  extraNonce1 +  extraNonce2 + genTx1
merkle_hash = hashlib.sha256(hashlib.sha256(coinbaseBuffer).digest()).hexdigest()
print(merkle_hash)


from binascii import unhexlify, hexlify
header_hex = (nversion.hex() +
 previousBlockHash.hex() +
 merkle_hash +
 nTime.hex() +
 nbits.hex() +
 nonce.hex())
header_bin = unhexlify(header_hex)
hash = hashlib.sha256(hashlib.sha256(header_bin).digest()).digest()
print(hexlify(hash[::-1]).decode("utf-8"))