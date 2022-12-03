const {
  loadFixture,
} = require('@nomicfoundation/hardhat-network-helpers');
const { ethers } = require('hardhat');

const chai = require('chai');
const chaiAsPromised = require('chai-as-promised');

chai.use(chaiAsPromised);
const { expect } = chai;

describe('CKRegistry', () => {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployCKVerifierFixture() {
    // Contracts are deployed using the first signer/account by default
    const [owner, verifiedAccount, unverifiedAccount] = await ethers.getSigners();

    const Registry = await ethers.getContractFactory('CKRegistry');
    const registry = await Registry.deploy();

    const Verifier = await ethers.getContractFactory('TestCKVerifier');
    const verifier = await Verifier.deploy();

    await verifier.setCKVerified(verifiedAccount.address, true);
    // Assign bit (1 << 0x2) = 0x4
    await registry.assignVerifierAddress(verifier.address, 2);
    await registry.trustVerificationBit(2, true);

    return {
      registry, verifier, owner, verifiedAccount, unverifiedAccount,
    };
  }

  describe('Access', () => {
    it('Should not allow verifications from non-verifier addresses', async () => {
      const { registry, unverifiedAccount } = await loadFixture(deployCKVerifierFixture);
      const Verifier = await ethers.getContractFactory('TestCKVerifier');
      const verifier = await Verifier.deploy();

      await expect(registry.registerCK(unverifiedAccount.address, verifier.address))
        .to.be.revertedWith('CKRegistry: Verifier address is not authorized');
    });

    it('Should revert if a verification attempt is made without a proof', async () => {
      const { registry, verifier, unverifiedAccount } = await loadFixture(deployCKVerifierFixture);
      await expect(registry.registerCK(unverifiedAccount.address, verifier.address))
        .to.be.revertedWith('CKRegistry: Verifier needs proof');
    });

    it('Should allow for verifier assignment', async () => {
      const { registry, verifiedAccount } = await loadFixture(deployCKVerifierFixture);
      const Verifier2 = await ethers.getContractFactory('TestCKVerifier');
      const verifier2 = await Verifier2.deploy();
      await verifier2.setCKVerified(verifiedAccount.address, true);
      await expect(registry.registerCK(verifiedAccount.address, verifier2.address))
        .to.be.revertedWith('CKRegistry: Verifier address is not authorized');
      await expect(registry.assignVerifierAddress(verifier2.address, 0))
        .to.emit(registry, 'VerifierAssigned')
        .withArgs(verifier2.address, 0);

      await expect(registry.registerCK(verifiedAccount.address, verifier2.address))
        .to.emit(registry, 'VerificationBitSet')
        .withArgs(verifiedAccount.address, verifier2.address, 0);

      // The new verification bit must be set to trusted
      await expect(registry.isCK(verifiedAccount.address)).to.eventually.be.false;
      await registry.trustVerificationBit(0, true);
      await expect(registry.isCK(verifiedAccount.address)).to.eventually.be.true;
    });

    it('Should allow for verifier removal', async () => {
      const {
        registry, verifier, verifiedAccount, unverifiedAccount,
      } = await loadFixture(deployCKVerifierFixture);
      await expect(registry.registerCK(verifiedAccount.address, verifier.address))
        .to.emit(registry, 'VerificationBitSet');
      await expect(registry.isCK(verifiedAccount.address)).to.eventually.be.true;
      await expect(registry.removeVerifierAddress(verifier.address))
        .to.emit(registry, 'VerifierRemoved')
        .withArgs(verifier.address);
      await expect(registry.isCK(verifiedAccount.address)).to.eventually.be.true;
      await expect(registry.registerCK(unverifiedAccount.address, verifier.address))
        .to.be.revertedWith('CKRegistry: Verifier address is not authorized');
    });
  });

  describe('Verification bit setting', () => {
    it('Should set a verification bit upon successful CK registration', async () => {
      const { registry, verifier, verifiedAccount } = await loadFixture(deployCKVerifierFixture);
      // Emits log
      const vBit = (await registry.verifierAddresses(verifier.address)).sub(1);
      await expect(vBit.gte(0)).to.be.true;
      await expect(registry.registerCK(verifiedAccount.address, verifier.address))
        .to.emit(registry, 'VerificationBitSet')
        .withArgs(verifiedAccount.address, verifier.address, vBit);
      // Verification bit set
      await expect(registry.verifications(verifiedAccount.address)).to.eventually.equal(
        ethers.BigNumber.from(1).shl(vBit.toNumber()),
      );
      // isCK returns true
      await expect(registry.isCK(verifiedAccount.address)).to.eventually.equal(true);
      await expect(registry.isCKAny(verifiedAccount.address)).to.eventually.equal(true);
    });
    it('Should revoke trust from proofs after updating the trust bitset', async () => {
      const {
        registry, verifier, verifiedAccount,
      } = await loadFixture(deployCKVerifierFixture);
      const vBit = (await registry.verifierAddresses(verifier.address)).sub(1);
      await registry.registerCK(verifiedAccount.address, verifier.address);
      // Verification bit set
      await expect(registry.verifications(verifiedAccount.address)).to.eventually.equal(
        ethers.BigNumber.from(1).shl(vBit.toNumber()),
      );
      // isCK returns true
      await expect(registry.isCK(verifiedAccount.address)).to.eventually.equal(true);
      await expect(registry.isCKAny(verifiedAccount.address)).to.eventually.equal(true);
      // Now untrusted
      await registry.trustVerificationBit(vBit, false);
      await expect(registry.isCK(verifiedAccount.address)).to.eventually.equal(false);
      await expect(registry.isCKAny(verifiedAccount.address)).to.eventually.equal(true);
    });
  });
});
