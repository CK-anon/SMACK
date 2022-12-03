const hre = require('hardhat');
const BigNumber = require('bignumber.js');
const { version } = require('chai');
const fs = require('fs');

async function main() {
  // Randomness : 0xc73031daa95c8a4119d200c0796c7958d6ead87cff96d9bdd30c56cfb2314efe need to use this for the specific response

  const Verifier = await hre.ethers.getContractFactory('CKVerifier');
  const verifier = await Verifier.deploy(3026, 62, 5, 1);

  await verifier.deployed();

  contract_address = verifier.address;
  console.log('Verifer deployed to:', contract_address);

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

  register_tx = await verifier.registerJob(commitmentsX, commitmentsY, pkx, pky, { gasLimit: 1000000 });
  const receipt1 = await register_tx.wait();
  console.log(receipt1.logs);

  job_id = 1;
  // const randomness = '0xc73031daa95c8a4119d200c0796c7958d6ead87cff96d9bdd30c56cfb2314efe'

  const challenge_tx = await verifier.initChallenge(job_id);

  const receipt2 = await challenge_tx.wait();
  console.log(receipt2.logs);

  const jsonString = fs.readFileSync('result.json', 'utf-8', 'r');

  const blocks = JSON.parse(jsonString);
  console.log(blocks);

  // Now you can call functions of the contract
  verify_tx = await verifier.verify(job_id, blocks, { gasLimit: 10000000 });
  const receipt3 = await verify_tx.wait();
  // Receipt should now contain the logs
  console.log(verify_tx);
  console.log(receipt3);
  console.log(receipt3.logs);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
