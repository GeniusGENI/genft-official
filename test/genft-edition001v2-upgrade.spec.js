const {expect} = require('chai');
const hre = require('hardhat');

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

describe.only('Edition001 V2 Upgrade', async () => {

  beforeEach(init);

  it('can upgrade', async () => {
    await EditionV2.upgrade(NewGenius.address, NewGenft.address, NewStabilityPool.address, Calendar.address);
    expect(await EditionV2.appliedUpgrade()).to.equal(true);
  });

  it('cannot upgrade to existing contracts', async () => {
    await expect(EditionV2.upgrade(Genius.address, NewGenft.address, NewStabilityPool.address, Calendar.address)).to.be.revertedWithCustomError(EditionV2, 'ErrorInvalidGenius');
  });

  it('cannot upgrade a second time', async () => {
    await EditionV2.upgrade(NewGenius.address, NewGenft.address, NewStabilityPool.address, Calendar.address);
    await expect(EditionV2.upgrade(NewGenius.address, NewGenft.address, NewStabilityPool.address, Calendar.address)).to.be.revertedWithCustomError(EditionV2, 'ErrorAlreadyUpgraded');
  });

  it('non-grantor is locked out of upgrading', async () => {
    await expect(EditionV2.connect(bob).upgrade(NewGenius.address, NewGenft.address, NewStabilityPool.address, Calendar.address)).to.be.revertedWithCustomError(EditionV2, 'ErrorNotAllowed');
  });

  it('cannot upgrade to non-genius contracts', async () => {
    await expect(EditionV2.upgrade(Dai.address, NewGenft.address, NewStabilityPool.address, Calendar.address)).to.be.revertedWithCustomError(EditionV2, 'ErrorInvalidGenius');
  });

});
