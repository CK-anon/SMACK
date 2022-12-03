# Android CK Key Attestation Verifier

Try running some of the following tasks:

```shell
REPORT_GAS=true npx hardhat test
```

Much of the X.509 certificate parsing code was adapted from [JonahGroendal's](https://github.com/JonahGroendal) [x509-forest-of-trust](https://github.com/JonahGroendal/x509-forest-of-trust) project. The secp256r1 curve ECDSA-with-SHA256 signatures are verified using the P256SHA256Algorithm contract found in the [ens-contracts](https://github.com/ensdomains/ens-contracts) repository deployed at 0xe571A50F76ff7404F3Ce380D06CBd2c9c6Ca3670 on the Ethereum mainnet.
