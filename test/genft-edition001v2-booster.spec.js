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

describe('Edition001 V2 Booster Test Cases', async () => {

  let Genius, StabilityPool, Edition, EditionV2, Royalty, Genft, Calendar, Miners, Penalty, AuctionHouse, LGenius;
  let deployer, alice, bob, Dai, Weth;

  let BOOSTER_TOKEN_ID, ULTIMATE_TOKEN_ID;
  const baseURI = "ipfs://JGkARStQ5yBXgyfG2ZH3Jby8w6BgQmTRCQF5TrfB2hPjrD/";
  before(async () => {
    await ethers.provider.send("hardhat_reset");
    [deployer, alice, bob] = await ethers.getSigners();
    const key = deployer.address;
    Genius = await (await ethers.getContractFactory('Genius')).deploy(key, key);
    await Genius.deployed();

    LGenius = await (await ethers.getContractFactory('LegacyGenius')).deploy();
    await LGenius.deployed();

    StabilityPool = await (await ethers.getContractFactory('StabilityPool')).deploy(Genius.address, key, key);
    AuctionHouse = await (await ethers.getContractFactory('GeniusAuctionHouse')).deploy(Genius.address);
    Calendar = await (await ethers.getContractFactory('Calendar')).deploy(Genius.address, AuctionHouse.address);
    Penalty = await (await ethers.getContractFactory('PenaltyCounter')).deploy(Genius.address, Calendar.address, AuctionHouse.address);
    Miners = await (await ethers.getContractFactory('Miners')).deploy(Genius.address, Penalty.address,
      Calendar.address, StabilityPool.address, AuctionHouse.address, LGenius.address);
    Genft = await (await ethers.getContractFactory('Genft')).deploy(Genius.address,
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

    // Deploy RoyaltyReceiver
    Royalty = await (await ethers.getContractFactory('RoyaltyReceiver')).deploy(
        Genius.address,
        StabilityPool.address,
        Miners.address,
        Penalty.address,
        Genft.address
    );
    // Deploy Edition
    Edition = await (await ethers.getContractFactory('Edition001')).deploy(
        Genius.address,
        Genft.address,
        StabilityPool.address,
        baseURI
    );

    // Deploy Edition V2
    EditionV2 = await (await ethers.getContractFactory('Edition001V2')).deploy(
      Genius.address,
      Genft.address,
      StabilityPool.address,
      Calendar.address,
      Royalty.address,
      Edition.address,
      baseURI
    );

    BOOSTER_TOKEN_ID = await Edition.BOOSTER_TOKEN_ID();
    ULTIMATE_TOKEN_ID = await Edition.ULTIMATE_TOKEN_ID();

    Dai = await ethers.getContractFactory("Dai");
    const chainId = (await ethers.provider.getNetwork()).chainId;
    Dai = await Dai.deploy(chainId);

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

    await Dai.connect(deployer).approve(StabilityPool.address, ethers.utils.parseUnits(APPROVAL_LIMIT, 18));

    // GENFT distribution
    await Edition.defineUserMints(
        ethers.constants.AddressZero,
        ethers.utils.parseEther('0.1'),
        ethers.utils.parseEther('0.2')
    );
    // transfer Genius token to the user
    await Genius.transferToTest(alice.address, parse(4_000_000, 9));
    // Define mintSetting to Genius as the payment token
    await Edition.defineUserMints(
        Genius.address,
        parse(1_000_000, 9),
        parse(2_000_000, 9)
    );
    // The end user allows Edition contract to access to his Genius token asset
    await Genius.connect(alice).approve(Edition.address, ethers.utils.parseUnits(APPROVAL_LIMIT.toString(), 18));
    let tx = Edition.connect(alice).userMintBooster(Genius.address, 2);
    await tx;

    describe('Booster Tests', async () => {

      before(async () => {
        await Genft.newEdition(EditionV2.address);
        await ethers.provider.send("evm_increaseTime", [86400 * 60]);
        await ethers.provider.send("evm_mine");
      })

      it('defineUserMints has not been set', async () => {
        const tx = EditionV2.connect(alice).userMintBooster(ethers.constants.AddressZero, 1);
        await expect(tx).to.be.revertedWithCustomError(EditionV2, 'ErrorMintSettingDoesNotExist');
        await EditionV2.defineUserMints(
          ethers.constants.AddressZero,
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.2')
        );
        await EditionV2.removeUserMint(ethers.constants.AddressZero);
        await EditionV2.defineUserMints(
          ethers.constants.AddressZero,
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.2')
        );
      });

      it('alice can mint Booster NFT with Native', async () => {
        let tx = EditionV2.connect(alice).userMintBooster(ethers.constants.AddressZero, 1);
        await expect(tx).to.be.revertedWithCustomError(EditionV2, `ErrorInsufficientDeposit`);
        console.log("Royalty Address:", await EditionV2.royaltyAddress());
        await EditionV2.connect(alice).userMintBooster(ethers.constants.AddressZero, 1,
          { value: ethers.utils.parseEther("0.2") });
        // Verify token balance
        const userTokens = await EditionV2.tokensByAccount(alice.address);
        expect(BOOSTER_TOKEN_ID).to.be.equal(userTokens[0]);

        const tokenUsers = await EditionV2.accountsByToken(userTokens[0]);
        expect(alice.address).to.be.equal(tokenUsers[0]);

        const aliceBal = await EditionV2.balanceOf(alice.address, BOOSTER_TOKEN_ID);
        expect(aliceBal).to.be.equal(1);

        // Checking Royalty Native balance
        const contractNativeBalance = await ethers.provider.getBalance(Royalty.address);
        expect(contractNativeBalance).to.be.equal(ethers.utils.parseEther("0.2"));
      });

      it('Alice can mint Booster NFT with Genius Token', async () => {
        // transfer Genius token to the user
        await Genius.transferToTest(alice.address, parse(2_000_000, 9));
        // Define mintSetting to Genius as the payment token
        await EditionV2.defineUserMints(
          Genius.address,
          parse(1_000_000, 9),
          parse(2_000_000, 9)
        );
        // The end user allows Edition contract to access to his Genius token asset
        await Genius.connect(alice).approve(EditionV2.address, ethers.utils.parseUnits(APPROVAL_LIMIT.toString(), 18));

        let tx = EditionV2.connect(alice).userMintBooster(Genius.address, 1);
        await tx;

        const userTokens = await EditionV2.tokensByAccount(alice.address);
        expect(BOOSTER_TOKEN_ID).to.be.equal(userTokens[0]);

        const tokenUsers = await EditionV2.accountsByToken(userTokens[0]);
        expect(alice.address).to.be.equal(tokenUsers[0]);

        const aliceBal = await EditionV2.balanceOf(alice.address, BOOSTER_TOKEN_ID);
        expect(aliceBal).to.be.equal(2);
      });

      it('Alice can mint Booster NFT with ERC20 Token (DAI)', async () => {
        // transfer Genius token to the user
        await Dai.mint(alice.address, parse(200, 18));
        // Define mintSetting to Genius as the payment token
        await EditionV2.defineUserMints(
          Dai.address,
          parse(100, 18),
          parse(200, 18)
        );
        // The end user allows Edition contract to access to his Genius token asset
        await Dai.connect(alice).approve(EditionV2.address, ethers.utils.parseUnits(APPROVAL_LIMIT.toString(), 18));

        let tx = EditionV2.connect(alice).userMintBooster(Dai.address, 1);
        await tx;

        const userTokens = await EditionV2.tokensByAccount(alice.address);
        expect(BOOSTER_TOKEN_ID).to.be.equal(userTokens[0]);

        const tokenUsers = await EditionV2.accountsByToken(userTokens[0]);
        expect(alice.address).to.be.equal(tokenUsers[0]);

        const aliceBal = await EditionV2.balanceOf(alice.address, BOOSTER_TOKEN_ID);
        expect(aliceBal).to.be.equal(3);
      });

      it('Alice can convert V1 to V2', async () => {

        expect(await Edition.balanceOf(alice.address, BOOSTER_TOKEN_ID)).to.be.equal(2);

        await Edition.connect(alice).setApprovalForAll(EditionV2.address, true);
        await EditionV2.connect(alice).convert();

        expect(await Edition.balanceOf(alice.address, BOOSTER_TOKEN_ID)).to.be.equal(0);
        // 6 = existing v2 tokens: 3(using native, geni, dai) + converted v2 tokens: 2 + bonus for conversion: 1
        expect(await EditionV2.balanceOf(alice.address, BOOSTER_TOKEN_ID)).to.be.equal(6);
      });

      it('Royalty Balances Check', async () => {
        // Native Token
        //// 1 token using Native Token
        expect(await Royalty.balanceOf(ethers.constants.AddressZero)).to.be.equals(ethers.utils.parseEther("0.2"));
        //// 3 tokens sent to Genius OA beneficiary, 2 tokens from Edition001, 1 tokens from Edition001V2 for 2000,000 GENI
        expect(await Genius.balanceOf(await Genius.oaBeneficiary())).to.be.equals(2 * parse(2_000_000, 9));
        //// 1 token using ERC20 Dai,
        expect(await Dai.balanceOf(Royalty.address)).to.be.equals(parse(200, 18));
        expect(await Royalty.balanceOf(Dai.address)).to.be.equals(ethers.utils.parseEther("200"));
      });

      it('Verify metadata URIs', async () => {
        // console.log(await Edition.uri(527));
        // console.log(await EditionV2.uri(527));
        for (let r = 0; r < 8; r++) {
          for (let v = 0; v < VARIETIES[r]; v++) {
            const tid  = tokenId(r, v);
            console.log(tid);
            const v1Uri = await Edition.uri(tid);
            const v2Uri = await EditionV2.uri(tid);
            if (v1Uri.includes("json")) {
              // expected two URIs are identical, if v1 uri is valid
              expect(v1Uri).to.be.equal(v2Uri);
            } else {
              // expected v2 has a valid uri, if v1 uri is invalid
              expect(v2Uri.includes("json")).to.be.equal(true);
            }
          }
        }
      });

    });

  });

  describe('canPurchase Modifier', () => {
    it('should throw ErrorPobOnly if less than 60 days from edition launch and paymentToken is anything other than Geni', async () => {

      /*
         if (block.timestamp < LAUNCH_TIMESTAMP + 60 days && paymentToken != geniAddress) {
          revert ErrorPobOnly();
      }
      */
      await Genft.newEdition(EditionV2.address);

      const currBlock = await ethers.provider.getBlock();
      const currTimestamp = currBlock.timestamp;
      const editionLaunchTimestamp = await EditionV2.LAUNCH_TIMESTAMP();
      console.log(editionLaunchTimestamp.toNumber());
      expect(currTimestamp).to.be.lessThan(editionLaunchTimestamp.toNumber() + (60 * 86400));
      await expect(EditionV2.connect(alice).userMintBooster(Dai.address, 1)).to.be.revertedWithCustomError(EditionV2,'ErrorPobOnly');
    });

    it('should throw ErrorEditionExpired if editionV2 is not latest and Genius Day is greater than 365', async () => {

      /*
        if (genftContract.currentEdition().editionAddress != address(this) && calendarContract.getCurrentGeniusDay() > 365) {
          revert ErrorEditionExpired();
        }
      */
      const prevDay = await Calendar.getCurrentGeniusDay();
      await Genft.newEdition(Edition.address);
      const currentEdition = await Genft.currentEdition();

      // genftContract.currentEdition().editionAddress != address(this)
      expect(currentEdition.editionAddress).to.be.equal(Edition.address);

      await ethers.provider.send("evm_increaseTime", [86400 * 366]);
      await ethers.provider.send("evm_mine");
      const currDay = await Calendar.getCurrentGeniusDay();

      // calendarContract.getCurrentGeniusDay() > 365
      expect(currDay.toNumber()).to.be.equal(prevDay.toNumber() + 366);

      await expect(EditionV2.connect(alice).userMintBooster(Genius.address, 1)).to.be.revertedWithCustomError(EditionV2,'ErrorEditionExpired');
    });

  });
});
