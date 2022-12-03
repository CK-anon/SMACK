// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require('hardhat');

async function main() {
  const nftFactory = await hre.ethers.getContractFactory('AtomicNFT');
  // TODO: Create CKRegistry
  const nft = await nftFactory.deploy('0x0000000000000000000000000000000000000000');

  await nft.deployed();
  const receipt = await nft.deployTransaction.wait();
  console.log('Deployment cost:', receipt.gasUsed.toNumber());
  console.log(`AtomicNFT deployed at ${nft.address}`);
  console.log('NFT name:', await nft.name(), '\tSymbol:', await nft.symbol());
  // TODO: Mint tokens
  // const tokenId = 0;
  // console.log("Token URI of token", tokenId + ":", await nft.tokenURI(tokenId));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
