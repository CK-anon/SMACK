const hre = require('hardhat');
const BigNumber = require('bignumber.js');

async function main() {
  contract_address = '0xAC86fD0d5293F8E5c412b569FCB10F8d5DB39f4b';

  contract_address = '0xE6E340D132b5f46d1e472DebcD681B2aBc16e57E';

  let [commitmentsX, commitmentsY, pkx, pky] = [
    [
      '27803234298335061949407146865860172254272005584944994146192385143010177926634',
      '113701359232053805814549367891166505084300108254318669534512754831782870372276',
      '109947393900667469070504573733163993149981661978046575815433269997465865504296',
      '46725386823395117753404608170486636657658974250488782911733333051115794489112',
      '22126283538286053724315734059353101962853415658284702812688172083558950531017',
    ],
    [
      '93561541378570300685208937663033946922634849385667789571681952756318138821603',
      '87182697592757874684493864651524599689985690116242343583755587458188010569756',
      '7873903381314374413355490323423414565822239211632048768825915476751302557219',
      '62473546498102808293311541988810204699882491837395828741313925531312493671010',
      '16172415511111266377270880497052037629578408987222950851498366676228834818158',
    ],
    '36384868579675573372656496263509990092570645809285184128284050686852694902901',
    '51792098218084568999788043605590004678280489525667168488502954943102253947037',
  ];

  for (let i = 0; i < commitmentsX.length; i++) {
    commitmentsX[i] = ethers.BigNumber.from(commitmentsX[i]);
    commitmentsY[i] = ethers.BigNumber.from(commitmentsY[i]);
  }
  pkx = ethers.BigNumber.from(pkx);
  pky = ethers.BigNumber.from(pky);

  const MyContract = await ethers.getContractFactory('CKVerifier');
  const contract = await MyContract.attach(contract_address);

  // Now you can call functions of the contract
  register_tx = await contract.registerJob(commitmentsX, commitmentsY, pkx, pky, { gasLimit: 1000000 });
  const receipt = await register_tx.wait();
  // Receipt should now contain the logs
  console.log(receipt.logs);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
