const hre = require('hardhat');

async function main() {
  const Lock = await hre.ethers.getContractFactory('CKVerifier');
  const lock = await Lock.deploy(3026, 62, 5, 1);

  await lock.deployed();

  console.log(
    'Deployed!',
  );
  console.log(lock.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
