# CK
On-chain verification of an ASIC CK proof

You can run the sample proof and test using the following script:

```shell
npx hardhat compile
npx hardhat run scripts/verify.js --network hardhat
```

## Development
To lint the smart contracts, run
```
node ./node_modules/solhint/solhint.js './contracts/**/*.sol'
```

To lint JavaScript scripts and tests, run
```
npm run lint
# Fix some linting errors automatically
npm run lint -- --fix
```

To run smart contract test cases, run
```
npx hardhat test
```

### Bitcoin block verification
To test out the Bitcoin block verification tools, run
```shell
npx hardhat run scripts/blocksynth.js --network hardhat
```

### Ethereum Mainnet remarks
* Blocks are mined every 12 seconds on the mainnet, so expect transaction receipts to be delayed up to 12 seconds or more when sending transactions.
* The pool software outputs commitments and public keys, waits for a randomness file to exist (created by the initchallenge script). Then the pool software broadcasts the work to the ASIC once it is ready to work.
