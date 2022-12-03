const hre = require('hardhat');
const BigNumber = require('bignumber.js');
const fs = require('fs');

async function main() {
  contract_address = '0xAC86fD0d5293F8E5c412b569FCB10F8d5DB39f4b';
  job_id = 1;

  contract_address = '0xE6E340D132b5f46d1e472DebcD681B2aBc16e57E';
  job_id = 1;

  fs.readFile('result.json', 'utf8', (err, jsonString) => {
    if (err) {
      console.log('File read failed:', err);
      return;
    }
    blocks = JSON.parse(jsonString);
    console.log(blocks);
  });

  const MyContract = await ethers.getContractFactory('CKVerifier');
  const contract = await MyContract.attach(contract_address);

  // Now you can call functions of the contract
  verify_tx = await contract.verify(job_id, blocks, { gasLimit: 10000000 });
  const receipt = await verify_tx.wait();
  // Receipt should now contain the logs
  console.log(verify_tx);
  console.log(receipt);
  console.log(receipt.logs);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
