// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require('hardhat');
const ethers = require('ethers');

const { BigNumber } = ethers;

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy
  const bsFactory = await hre.ethers.getContractFactory('BlockSynthesis');
  const bs = await bsFactory.deploy();

  await bs.deployed();
  const genTx0 = '0x01000000010000000000000000000000000000000000000000000000000000000000000000ffffffff1d5a044c15326308';
  const genTx1 = '0x0d2f6e6f64655374726174756d2f00000000020000000000000000266a24aa21a9ede2f61c3f71d1defd3fa999dfa36953755c690689799962b48bebd836974e8cf900f2052a01000000160014844b7da326c9142a937cea4537a9553a459fbee300000000';
  const extraNonce1 = '0x58000000';
  const extraNonce2 = '0x00000000';

  const previousBlockHash = '0x00000000babb8fd5fd35178708337c580bdd9153226d6610ce90d06e4ca688cb';

  const nonce = '0xd7f0fdea';
  const bits = '0x1d00ffff';
  const nTime = '0x6332154c';
  const version = '0x20000000';

  const res = await bs.createCoinbaseTx(genTx0, extraNonce1, extraNonce2, genTx1);
  console.log(`Coinbase tx: ${res}`);
  const merkleRoot = await bs.coinbaseHash(res);
  console.log('Merkle root:', merkleRoot);
  const blockHeader = await bs.createBlockHeader(
    nonce,
    bits,
    nTime,
    merkleRoot,
    previousBlockHash,
    version,
  );
  console.log('Block header:', blockHeader);
  const blockHash = await bs.blockHash(blockHeader);
  console.log('Block hash:', blockHash);

  const diff1 = BigNumber.from('0x00000000ffff0000000000000000000000000000000000000000000000000000');
  console.log('Block difficulty:', diff1.mul(1e8).div(BigNumber.from(blockHash)).toNumber() / 1e8);
  const diffContract = await bs.blockDifficulty(blockHash);
  console.log(' (as computed by the contract):', diffContract.toNumber());
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
