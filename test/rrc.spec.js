const {expect} = require('chai');
const hre = require('hardhat');
// NOTE: The Genius Smart Financial Contract repository is required to properly
// run the tests for the Royalty Receiver Contract.  Replace GENIUS_REPO_PATH
// with the actual path to the repository.
const {addDays} = require('GENIUS_REPO_PATH/scripts/helpers/misc-utils');

const APPROVAL_LIMIT = '240000000000000000000';

const parse = (amount, dec) => {
  return ethers.utils.parseUnits(amount.toString(), dec);
};

const beginCollateral = async (stabilityPoolContract, collateralToBegin) => {
  for (const {address, rate} of collateralToBegin) {
    if (address && rate) {
      await stabilityPoolContract.beginCollateral(address, rate);
      console.log("beginCollateral", address, rate);
    }
  }
}
const VARIETIES = [
  // common (0)
  15,
  // uncommon (1)
  9,
  // common foil (2)
  15,
  // uncommon foil (3)
  9,
  // rare (4)
  6,
  // rare foil (5)
  6,
  // mythic (6)
  2,
  // mythic foil (7)
  2
];
const tokenId = (r, v) => {
  return (r << 8 | v) + 1;
}

const dataEnv = {
  genftAddress: "0x8656996710CF52fBaCB8CacE1b670fea52Da695E",
}

let Genius, StabilityPool, Edition, EditionV2, Royalty;
let LGenius, AuctionHouse, Calendar, Penalty, Miners, Genft;
let deployer, alice, bob, Dai, Weth;
let NewGenius, NewStabilityPool, NewAuctionHouse, NewCalendar, NewPenalty, NewMiners, NewGenft;

const init = async () => {
  await hre.ethers.provider.send("hardhat_reset");
  [deployer, alice, bob] = await hre.ethers.getSigners();
  const key = deployer.address;
  Genius = await (await hre.ethers.getContractFactory('Genius')).deploy(key, key);
  await Genius.deployed();

  LGenius = await (await hre.ethers.getContractFactory('LegacyGenius')).deploy();
  await LGenius.deployed();

  StabilityPool = await (await hre.ethers.getContractFactory('StabilityPool')).deploy(Genius.address, key, key);
  AuctionHouse = await (await hre.ethers.getContractFactory('GeniusAuctionHouse')).deploy(Genius.address);
  Calendar = await (await hre.ethers.getContractFactory('Calendar')).deploy(Genius.address, AuctionHouse.address);
  Penalty = await (await hre.ethers.getContractFactory('PenaltyCounter')).deploy(Genius.address, Calendar.address, AuctionHouse.address);
  Miners = await (await hre.ethers.getContractFactory('Miners')).deploy(Genius.address, Penalty.address,
    Calendar.address, StabilityPool.address, AuctionHouse.address, LGenius.address);
  Genft = await (await hre.ethers.getContractFactory('Genft')).deploy(Genius.address,
    AuctionHouse.address,
    Calendar.address,
    Miners.address,
    StabilityPool.address,
    Penalty.address
  );
  await Genius.setStabilityPoolAddress(StabilityPool.address);
  await Genius.setAuctionContract(AuctionHouse.address);
  await Genius.setCalendarContract(Calendar.address);
  await Genius.setPenaltyContract(Penalty.address);
  await Genius.setMinersContract(Miners.address);
  await Genius.setGnftContract(Genft.address);

  // new contracts
  NewGenius = await (await hre.ethers.getContractFactory('Genius')).deploy(key, key);
  await NewGenius.deployed();
  NewStabilityPool = await (await hre.ethers.getContractFactory('StabilityPool')).deploy(NewGenius.address, key, key);
  NewAuctionHouse = await (await hre.ethers.getContractFactory('GeniusAuctionHouse')).deploy(NewGenius.address);
  NewCalendar = await (await hre.ethers.getContractFactory('Calendar')).deploy(NewGenius.address, NewAuctionHouse.address);
  NewPenalty = await (await hre.ethers.getContractFactory('PenaltyCounter')).deploy(NewGenius.address, NewCalendar.address, NewAuctionHouse.address);
  NewMiners = await (await hre.ethers.getContractFactory('Miners')).deploy(NewGenius.address, NewPenalty.address,
    NewCalendar.address, NewStabilityPool.address, NewAuctionHouse.address, LGenius.address);
  NewGenft = await (await hre.ethers.getContractFactory('Genft')).deploy(
    NewGenius.address,
    NewAuctionHouse.address,
    NewCalendar.address,
    NewMiners.address,
    NewStabilityPool.address,
    NewPenalty.address
  );

  await Genius.connect(alice).approve(Miners.address, hre.ethers.utils.parseUnits(APPROVAL_LIMIT.toString(), 18));
  await Genius.connect(bob).approve(Miners.address, hre.ethers.utils.parseUnits(APPROVAL_LIMIT.toString(), 18));

  // Deploy RoyaltyReceiver
  Royalty = await (await hre.ethers.getContractFactory('RoyaltyReceiver')).deploy(
    Genius.address,
    StabilityPool.address,
    Miners.address,
    Penalty.address,
    Genft.address
  );
  // Deploy Edition
  const baseURI = "ipfs://JGkARStQ5yBXgyfG2ZH3Jby8w6BgQmTRCQF5TrfB2hPjrD/";
  Edition = await (await hre.ethers.getContractFactory('Edition001')).deploy(
    Genius.address,
    Genft.address,
    StabilityPool.address,
    baseURI
  );

  // Deploy Edition V2
  EditionV2 = await (await hre.ethers.getContractFactory('Edition001V2')).deploy(
    Genius.address,
    Genft.address,
    StabilityPool.address,
    Calendar.address,
    Royalty.address,
    Edition.address,
    baseURI
  );

  await Genft.newEdition(EditionV2.address);

  BOOSTER_TOKEN_ID = await Edition.BOOSTER_TOKEN_ID();
  ULTIMATE_TOKEN_ID = await Edition.ULTIMATE_TOKEN_ID();

  Dai = await hre.ethers.getContractFactory("Dai");
  const chainId = (await hre.ethers.provider.getNetwork()).chainId;
  Dai = await Dai.deploy(chainId);

  Weth = await hre.ethers.getContractFactory("WrappedEther");
  Weth = await Weth.deploy();

  await beginCollateral(StabilityPool, [
    {
      address: Dai.address,
      rate: 1400000000000000
    },
    {
      address: Genius.address,
      rate: 1_000_000_000
    },
    {
      address: ethers.constants.AddressZero,
      rate: 1000000000
    },
  ]);

  await Dai.connect(deployer).approve(StabilityPool.address, hre.ethers.utils.parseUnits(APPROVAL_LIMIT, 18));
  await hre.ethers.provider.send("evm_increaseTime", [86400 * 60]);
  await hre.ethers.provider.send("evm_mine");

  await EditionV2.defineUserMints(
    ethers.constants.AddressZero,
    hre.ethers.utils.parseEther('0.1'),
    hre.ethers.utils.parseEther('0.2')
  );

  // transfer Genius token to the user
  await Genius.transferToTest(alice.address, parse(2_000_000, 9));
  // Define mintSetting to Genius as the payment token
  await EditionV2.defineUserMints(
    Genius.address,
    parse(1_000_000, 9),
    parse(2_000_000, 9)
  );

  // transfer Dai token to the user
  await Dai.mint(alice.address, parse(200, 18));
  // Define mintSetting to Genius as the payment token
  await EditionV2.defineUserMints(
    Dai.address,
    parse(100, 18),
    parse(200, 18)
  );
}

describe('Royalty Contract Test Cases', async () => {
  describe('Royalty Receiver Contract', async () => {

    before(init);

    it('Royalty Balances Check', async () => {

      const tx = await EditionV2.connect(alice).userMintBooster(ethers.constants.AddressZero, 1,
        {value: ethers.utils.parseEther("0.2")});
      await tx;

      // The end user allows Edition contract to access to his Genius token asset
      await Genius.connect(alice).approve(EditionV2.address, hre.ethers.utils.parseUnits(APPROVAL_LIMIT.toString(), 18));
      await EditionV2.connect(alice).userMintBooster(Genius.address, 1);

      // The end user allows Edition contract to access to his Genius token asset
      await Dai.connect(alice).approve(EditionV2.address, hre.ethers.utils.parseUnits(APPROVAL_LIMIT.toString(), 18));
      await EditionV2.connect(alice).userMintBooster(Dai.address, 1);
      // Native Token
      // 1 token using Native Token
      expect(await Royalty.balanceOf(ethers.constants.AddressZero)).to.be.equals(ethers.utils.parseEther("0.2"));
      // console.log(await Genius.balanceOf(await Genius.oaBeneficiary()));
      // //// 3 tokens sent to Genius OA beneficiary, 2 tokens from Edition001, 1 tokens from Edition001V2 for 2000,000 GENI
      // expect(await Genius.balanceOf(await Genius.oaBeneficiary())).to.be.equals(parse(2_000_000, 9));
      //// 1 token using ERC20 Dai,
      expect(await Dai.balanceOf(Royalty.address)).to.be.equals(parse(200, 18));
      expect(await Royalty.balanceOf(Dai.address)).to.be.equals(ethers.utils.parseEther("200"));
    });

    it('deployToken Test with native', async () => {
      const token = ethers.constants.AddressZero;
      const GENIUS_PRECISION = 1_000_000_000;
      const amount = ethers.utils.parseEther("0.2");
      const rSupply = await Genius.reserveSupply();
      const localMaxSystemDebt = await StabilityPool.maxSystemDebt(rSupply);
      const rate = await StabilityPool.issueRate(token);
      const geniusDebtAmount = (amount * GENIUS_PRECISION) / rate;
      const totalIssuedGenitos = await StabilityPool.totalIssuedGenitos();
      const newIssuedGenitos = geniusDebtAmount >
      await StabilityPool.maxTxDebt(rSupply)
        ? await StabilityPool.maxTxDebt(rSupply)
        : geniusDebtAmount;
      console.log("totalIssuedGenitos: ", totalIssuedGenitos);
      console.log("localMaxSystemDebt: ", localMaxSystemDebt);
      console.log("newIssuedGenitos: ", newIssuedGenitos);
      await expect(Royalty.connect(alice).deployToken(token, true)).to.be.not.reverted;

    });

    it('deployToken with Genius', async () => {
      await expect(Royalty.connect(alice).deployToken(Genius.address, true)).to.be.not.reverted;
    });

    it('deployToken with Dai', async () => {
      await expect(Royalty.connect(alice).deployToken(Dai.address, true)).to.be.not.reverted;
    });

    it('endMiner Test', async () => {
      await addDays(91);
      await expect(Royalty.endMiner([Genius.address])).to.be.not.reverted;
    });

  });

  describe('Upgrade', async () => {

    beforeEach(init);

    it('can upgrade', async () => {
      await Royalty.upgrade(NewGenius.address, NewGenft.address, NewStabilityPool.address, NewMiners.address, NewPenalty.address);
      expect(await Royalty.appliedUpgrade()).to.equal(true);
    });

    it('cannot upgrade a second time', async () => {
      await Royalty.upgrade(NewGenius.address, NewGenft.address, NewStabilityPool.address, NewMiners.address, NewPenalty.address);
      await expect(Royalty.upgrade(NewGenius.address, NewGenft.address, NewStabilityPool.address, NewMiners.address, NewPenalty.address)).to.be.revertedWithCustomError(Royalty, 'ErrorAlreadyUpgraded');
    });

    it('non-grantor is locked out of upgrading', async () => {
      await expect(Royalty.connect(bob).upgrade(NewGenius.address, NewGenft.address, NewStabilityPool.address, NewMiners.address, NewPenalty.address)).to.be.revertedWithCustomError(Royalty, 'ErrorNotAllowed');
    });

    it('cannot upgrade to non-genius contracts', async () => {
      await expect(Royalty.upgrade(Dai.address, NewGenft.address, NewStabilityPool.address, NewMiners.address, NewPenalty.address)).to.be.revertedWithCustomError(Royalty, 'ErrorInvalidGenius');
    });

  });

  describe( 'End Miner', async () => {

    beforeEach(init);

    it('Cannot end early', async () => {
      await Genius.connect(alice).approve(EditionV2.address, hre.ethers.utils.parseUnits(APPROVAL_LIMIT.toString(), 18));
      await EditionV2.connect(alice).userMintBooster(ethers.constants.AddressZero, 1, { value: ethers.utils.parseEther("0.2") });
      const tx = await Royalty.connect(alice).deployToken(ethers.constants.AddressZero, true);
      await tx;
      await expect(Royalty.endMiner([ethers.constants.AddressZero])).to.be.reverted;
      await expect((await Royalty.totalMiners()).toString()).to.be.equals('1');
      await addDays(100);
      await expect(Royalty.endMiner([ethers.constants.AddressZero])).to.be.not.reverted;
    });

    it('Cannot end a miner when there are no more miners', async () => {
      await Genius.connect(alice).approve(EditionV2.address, hre.ethers.utils.parseUnits(APPROVAL_LIMIT.toString(), 18));
      await EditionV2.connect(alice).userMintBooster(ethers.constants.AddressZero, 1, { value: ethers.utils.parseEther("0.2") });
      const tx = await Royalty.connect(alice).deployToken(ethers.constants.AddressZero, true);
      await tx;
      await addDays(100);
      await expect(Royalty.endMiner([ethers.constants.AddressZero])).to.be.not.reverted;
      await expect(Royalty.endMiner([ethers.constants.AddressZero])).to.be.reverted;
    });

    it('When ending an RRC miner – the stability pool’s settlement rate “pumps” (this requires having more than 1 collateral miner in the system)', async () => {

      let tx = await alice.sendTransaction({ to: Royalty.address, value: ethers.utils.parseEther("100") });
      await tx;

      const rateBefore = await StabilityPool.settlementRate(ethers.constants.AddressZero);

      tx = await Royalty.connect(alice).deployToken(ethers.constants.AddressZero, true);
      await tx;

      tx = await alice.sendTransaction({ to: Royalty.address, value: ethers.utils.parseEther("100") });
      await tx;

      tx = await Royalty.connect(alice).deployToken(ethers.constants.AddressZero, true);
      await tx;

      await addDays(100);
      await expect(Royalty.endMiner([ethers.constants.AddressZero])).to.be.not.reverted;

      const rateAfter = await StabilityPool.settlementRate(ethers.constants.AddressZero);
      expect(rateBefore).to.be.lessThan(rateAfter);

    });

    it('When ending an RRC miner without any “reward tokens” specified, verify that the EOA does not receive any tokens (which would’ve been the reward)', async () => {
      let tx = await alice.sendTransaction({ to: Royalty.address, value: ethers.utils.parseEther("200") });
      await tx;
      tx = await Royalty.connect(alice).deployToken(ethers.constants.AddressZero, true);
      await tx;
      await Genius.connect(alice).approve(EditionV2.address, hre.ethers.utils.parseUnits(APPROVAL_LIMIT.toString(), 18));
      tx = await EditionV2.connect(alice).userMintBooster(ethers.constants.AddressZero, 1, { value: ethers.utils.parseEther("0.2") });
      await tx;
      await addDays(100);
      const royaltyBalanceStart = await Royalty.balanceOf(ethers.constants.AddressZero);
      await expect(Royalty.endMiner([])).to.be.not.reverted;
      const royaltyBalanceEnd = await Royalty.balanceOf(ethers.constants.AddressZero);
      expect(royaltyBalanceStart).to.be.equals(royaltyBalanceEnd);
    });

    it('Ending a miner with the native token specified as the reward: EOA receives ETH as a reward!', async () => {
      let tx = await alice.sendTransaction({ to: Royalty.address, value: ethers.utils.parseEther("100") });
      await tx;
      tx = await Royalty.connect(alice).deployToken(ethers.constants.AddressZero, true);
      await tx;
      await Genius.connect(alice).approve(EditionV2.address, hre.ethers.utils.parseUnits(APPROVAL_LIMIT.toString(), 18));
      tx = await EditionV2.connect(alice).userMintBooster(ethers.constants.AddressZero, 1, { value: ethers.utils.parseEther("0.2") });
      await tx;
      const balance = await deployer.getBalance();
      console.log(balance);
      await addDays(100);
      await expect(Royalty.endMiner([ethers.constants.AddressZero])).to.be.not.reverted;
      const balance2 = await deployer.getBalance();
      expect(balance2).to.be.above(balance);
    });

    it('With RRC having a balance for all acceptable tokens: Ending a miner with all collateral tokens specified for the reward tokens: EOA receives a portion of all collateral tokens held within the RRC contract as a reward', async () => {
      let tx = await alice.sendTransaction({ to: Royalty.address, value: ethers.utils.parseEther("100") });
      await tx;
      tx = await Royalty.connect(alice).deployToken(ethers.constants.AddressZero, true);
      await tx;
      await Genius.connect(alice).approve(EditionV2.address, hre.ethers.utils.parseUnits(APPROVAL_LIMIT.toString(), 18));
      tx = await EditionV2.connect(alice).userMintBooster(ethers.constants.AddressZero, 1, { value: ethers.utils.parseEther("0.2") });
      await tx;
      const balance = await deployer.getBalance();
      console.log(balance);
      await addDays(100);
      await expect(Royalty.endMiner([ethers.constants.AddressZero])).to.be.not.reverted;
      const balance2 = await deployer.getBalance();
      console.log(balance2);
      expect(balance2).to.be.above(balance);
    });

    it('With RRC having a balance for SOME (but not all) of the acceptable tokens: Ending a miner with all collateral tokens specified for the reward tokens: EOA receives a portion of all collateral tokens held within the RRC contract as a reward.', async () => {
      let tx = await alice.sendTransaction({ to: Royalty.address, value: ethers.utils.parseEther("100") });
      await tx;
      tx = Dai.connect(alice).transfer(Royalty.address, parse(60, 18));
      await tx;

      const royaltyBalanceNativeStart = await Royalty.balanceOf(ethers.constants.AddressZero);

      const royaltyBalanceDaiStart = await Royalty.balanceOf(Dai.address);

      tx = await Royalty.connect(alice).deployToken(ethers.constants.AddressZero, true);
      await tx;

      tx = await alice.sendTransaction({ to: Royalty.address, value: ethers.utils.parseEther("100") });
      await tx;

      await addDays(100);
      // const royaltyBalanceNativeStart = await Royalty.balanceOf(ethers.constants.AddressZero);

      await expect(Royalty.endMiner([ethers.constants.AddressZero, Dai.address])).to.be.not.reverted;

      const royaltyBalanceNativeEnd = await Royalty.balanceOf(ethers.constants.AddressZero);
      const royaltyBalanceDaiEnd = await Royalty.balanceOf(Dai.address);

      expect(royaltyBalanceNativeStart).to.be.greaterThan(royaltyBalanceNativeEnd);
      expect(royaltyBalanceDaiStart).to.be.greaterThan(royaltyBalanceDaiEnd);

    });

    it('With RRC having a GENI balance, ending a miner with the GENI token specified WILL NOT reward GENI.', async () => {
      let tx = await alice.sendTransaction({ to: Royalty.address, value: ethers.utils.parseEther("100") });
      await tx;

      tx = Genius.connect(alice).transfer(Royalty.address, parse(60, 9));
      await tx;

      tx = await Royalty.connect(alice).deployToken(ethers.constants.AddressZero, true);
      await tx;

      const royaltyBalanceGeniStart = await Royalty.balanceOf(Genius.address);

      await addDays(100);

      await Royalty.endMiner([Genius.address]);
      const royaltyBalanceGeniEnd = await Royalty.balanceOf(Genius.address);
      expect(royaltyBalanceGeniEnd).to.be.greaterThan(royaltyBalanceGeniStart);

    });

    it('Can "unlock" ETH refund', async () => {
      let tx = await alice.sendTransaction({ to: Royalty.address, value: ethers.utils.parseEther("100") });
      await tx;

      tx = Genius.connect(alice).transfer(Royalty.address, parse(60, 9));
      await tx;

      tx = await Royalty.connect(alice).deployToken(ethers.constants.AddressZero, true);
      await tx;

      await addDays(100);

      await Royalty.endMiner([Genius.address]);

      await expect(Royalty.unlockCvRefund()).to.be.not.reverted;
    });


  });

})

