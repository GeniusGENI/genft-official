const {expect} = require('chai');
const hre = require('hardhat');

const APPROVAL_LIMIT = '240000000000000000000';
const deadline = hre.ethers.constants.MaxInt256;

const parse = (amount, dec) => {
  return ethers.utils.parseUnits(amount.toString(), dec);
};

async function getERC20PermitSignature(signer, token, spender, value, deadline) {
  const [nonce, name, version, chainId] = await Promise.all([
    token.nonces(signer.address),
    token.name(),
    "1",
    signer.getChainId(),
  ])

  return ethers.utils.splitSignature(
    await signer._signTypedData(
      {
        name,
        version,
        chainId,
        verifyingContract: token.address,
      },
      {
        Permit: [
          {
            name: "owner",
            type: "address",
          },
          {
            name: "spender",
            type: "address",
          },
          {
            name: "value",
            type: "uint256",
          },
          {
            name: "nonce",
            type: "uint256",
          },
          {
            name: "deadline",
            type: "uint256",
          },
        ],
      },
      {
        owner: signer.address,
        spender,
        value,
        nonce,
        deadline,
      }
    )
  )
}

//
// function permit(address holder, address spender, uint256 nonce, uint256 expiry,
//  bool allowed, uint8 v, bytes32 r, bytes32 s) external

async function getDaiPermitSignature(signer, token, spender, expiry) {
  const [nonce, name, version, chainId] = await Promise.all([
    token.nonces(signer.address),
    token.name(),
    "1",
    signer.getChainId(),
  ])

  return ethers.utils.splitSignature(
    await signer._signTypedData(
      {
        name,
        version,
        chainId,
        verifyingContract: token.address,
      },
      {
        Permit: [
          {
            name: "holder",
            type: "address",
          },
          {
            name: "spender",
            type: "address",
          },
          {
            name: "nonce",
            type: "uint256",
          },
          {
            name: "expiry",
            type: "uint256",
          },
          {
            name: "allowed",
            type: "bool",
          },
        ],
      },
      {
        holder: signer.address,
        spender,
        nonce,
        expiry,
        allowed: true,
      }
    )
  )
}

const beginCollateral = async (stabilityPoolContract, collateralToBegin) => {
  for (const {address, rate} of collateralToBegin) {
    if (address && rate) {
      await stabilityPoolContract.beginCollateral(address, rate);
      console.log("beginCollateral", address, rate);
    }
  }
}

describe('Edition001 V2 Test Cases', async () => {

  let Genius, StabilityPool, Edition, EditionV2, Royalty;
  let deployer, alice, bob, Dai;

  let ULTIMATE_TOKEN_ID, BOOSTER_TOKEN_ID;
  beforeEach(async () => {
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

    ULTIMATE_TOKEN_ID = await EditionV2.ULTIMATE_TOKEN_ID();
    BOOSTER_TOKEN_ID = await EditionV2.BOOSTER_TOKEN_ID();

    Dai = await hre.ethers.getContractFactory("Dai");
    const chainId = (await hre.ethers.provider.getNetwork()).chainId;
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
        address: hre.ethers.constants.AddressZero,
        rate: 1000000000
      },
    ]);

    await Dai.connect(deployer).approve(StabilityPool.address, hre.ethers.utils.parseUnits(APPROVAL_LIMIT, 18));

    await Genft.newEdition(Edition.address);

  });

  describe('Ultimate Permit Tests', async () => {

    it('alice can mint Ultimate NFT with Native', async () => {
      await hre.ethers.provider.send("evm_increaseTime", [86400 * 60]);
      await hre.ethers.provider.send("evm_mine");
      await EditionV2.defineUserMints(
        hre.ethers.constants.AddressZero,
        hre.ethers.utils.parseEther('0.1'),
        hre.ethers.utils.parseEther('0.2')
      );
      const mintSettings = await EditionV2.mintSettings(hre.ethers.constants.AddressZero);
      const amount = 1;
      const totalFee = mintSettings.feeForUltimate.mul(amount);
      const {v, r, s} = await getERC20PermitSignature(alice, Dai, EditionV2.address, totalFee, deadline);
      await EditionV2.connect(alice).userMintUltimatePermit(hre.ethers.constants.AddressZero, amount, v, r, s,
          { value: hre.ethers.utils.parseEther("0.1") });
      // Verify token balance
      const userTokens = await EditionV2.tokensByAccount(alice.address);
      expect(ULTIMATE_TOKEN_ID).to.be.equal(userTokens[0]);

      const tokenUsers = await EditionV2.accountsByToken(userTokens[0]);
      expect(alice.address).to.be.equal(tokenUsers[0]);

      const aliceBal = await EditionV2.balanceOf(alice.address, ULTIMATE_TOKEN_ID);
      expect(aliceBal).to.be.equal(1);

      // Checking Royalty Native balance
      const contractNativeBalance = await hre.ethers.provider.getBalance(Royalty.address);
      expect(contractNativeBalance).to.be.equal(hre.ethers.utils.parseEther("0.1"));
    });

    it('Alice can mint Ultimate NFT with Genius Token', async () => {
        // transfer Genius token to the user
        await Genius.transferToTest(alice.address, parse(1_000_000, 9));
        // Define mintSetting to Genius as the payment token
        await EditionV2.defineUserMints(
            Genius.address,
            parse(1_000_000, 9),
            parse(2_000_000, 9)
        );

        const mintSetting = await EditionV2.mintSettings(Genius.address);
        const quantity = 1;
        const totalFee = mintSetting.feeForUltimate.mul(quantity);
        console.log("Genius total fee", totalFee);
        const {v, r, s} = await getERC20PermitSignature(alice, Genius, EditionV2.address, totalFee, deadline);
        let tx = EditionV2.connect(alice).userMintUltimatePermit(Genius.address, quantity, v, r, s);
        await tx;
        const userTokens = await EditionV2.tokensByAccount(alice.address);
        expect(ULTIMATE_TOKEN_ID).to.be.equal(userTokens[0]);
        const tokenUsers = await EditionV2.accountsByToken(userTokens[0]);
        expect(alice.address).to.be.equal(tokenUsers[0]);
        const aliceBal = await EditionV2.balanceOf(alice.address, ULTIMATE_TOKEN_ID);
        expect(aliceBal).to.be.equal(1);
    });

    it('Alice can mint Ultimate NFT with DAI', async () => {
      await hre.ethers.provider.send("evm_increaseTime", [86400 * 60]);
      await hre.ethers.provider.send("evm_mine");
      // Found a bug: ERC20 token name should be same as ERC20Permit's one in constructor.
      // transfer Genius token to the user
      await Dai.mint(alice.address, parse(1000, 18));
      // Define mintSetting to Genius as the payment token
      await EditionV2.defineUserMints(
          Dai.address,
          parse(100, 18),
          parse(200, 18)
      );

      const mintSetting = await EditionV2.mintSettings(Dai.address);
      const quantity = 1;
      const totalFee = mintSetting.feeForUltimate.mul(quantity);
      console.log("DAI total fee", totalFee);
      const nonce = await Dai.nonces(alice.address);
      const {v, r, s} = await getDaiPermitSignature(alice, Dai, EditionV2.address, deadline);
      const tx = EditionV2.connect(alice).userMintUltimateDaiPermit(Dai.address, quantity, nonce, true, v, r, s);
      await tx;

      const userTokens = await EditionV2.tokensByAccount(alice.address);
      expect(ULTIMATE_TOKEN_ID).to.be.equal(userTokens[0]);

      const tokenUsers = await EditionV2.accountsByToken(userTokens[0]);
      expect(alice.address).to.be.equal(tokenUsers[0]);

      const aliceBal = await EditionV2.balanceOf(alice.address, ULTIMATE_TOKEN_ID);
      expect(aliceBal).to.be.equal(1);
     });

  });
  ///////////////////////////////////////
  describe('Booster Permit Tests', async () => {

    it('alice can mint Booster NFT with Native', async () => {
      await hre.ethers.provider.send("evm_increaseTime", [86400 * 60]);
      await hre.ethers.provider.send("evm_mine");
      await EditionV2.defineUserMints(
        hre.ethers.constants.AddressZero,
        hre.ethers.utils.parseEther('0.1'),
        hre.ethers.utils.parseEther('0.2')
      );
      const mintSettings = await EditionV2.mintSettings(hre.ethers.constants.AddressZero);
      const amount = 1;
      const totalFee = mintSettings.feeForBooster.mul(amount);
      console.log(totalFee.toString())
      const {v, r, s} = await getERC20PermitSignature(alice, Dai, EditionV2.address, totalFee, deadline);
      await EditionV2.connect(alice).userMintBoosterPermit(hre.ethers.constants.AddressZero, amount, v, r, s,
        { value: hre.ethers.utils.parseEther("0.2") });
      // Verify token balance
      const userTokens = await EditionV2.tokensByAccount(alice.address);
      expect(BOOSTER_TOKEN_ID).to.be.equal(userTokens[0]);

      const tokenUsers = await EditionV2.accountsByToken(userTokens[0]);
      expect(alice.address).to.be.equal(tokenUsers[0]);

      const aliceBal = await EditionV2.balanceOf(alice.address, BOOSTER_TOKEN_ID);
      expect(aliceBal).to.be.equal(1);

      // Checking Royalty Native balance
      const contractNativeBalance = await hre.ethers.provider.getBalance(Royalty.address);
      expect(contractNativeBalance).to.be.equal(hre.ethers.utils.parseEther("0.2"));
    });

    it('Alice can mint Booster NFT with Genius Token', async () => {
      // transfer Genius token to the user
      await Genius.transferToTest(alice.address, parse(5_000_000, 9));
      // Define mintSetting to Genius as the payment token
      await EditionV2.defineUserMints(
        Genius.address,
        parse(1_000_000, 9),
        parse(2_000_000, 9)
      );

      const mintSetting = await EditionV2.mintSettings(Genius.address);
      const quantity = 1;
      const totalFee = mintSetting.feeForBooster.mul(quantity);
      console.log("Genius total fee", totalFee);
      const {v, r, s} = await getERC20PermitSignature(alice, Genius, EditionV2.address, totalFee, deadline);
      let tx = EditionV2.connect(alice).userMintBoosterPermit(Genius.address, quantity, v, r, s);
      await tx;
      const userTokens = await EditionV2.tokensByAccount(alice.address);
      expect(BOOSTER_TOKEN_ID).to.be.equal(userTokens[0]);
      const tokenUsers = await EditionV2.accountsByToken(userTokens[0]);
      expect(alice.address).to.be.equal(tokenUsers[0]);
      const aliceBal = await EditionV2.balanceOf(alice.address, BOOSTER_TOKEN_ID);
      expect(aliceBal).to.be.equal(1);
    });

    it('Alice can mint Booster NFT with DAI', async () => {
      await hre.ethers.provider.send("evm_increaseTime", [86400 * 60]);
      await hre.ethers.provider.send("evm_mine");
      // Found a bug: ERC20 token name should be same as ERC20Permit's one in constructor.
      // transfer Genius token to the user
      await Dai.mint(alice.address, parse(1000, 18));
      // Define mintSetting to Genius as the payment token
      await EditionV2.defineUserMints(
        Dai.address,
        parse(100, 18),
        parse(200, 18)
      );

      const mintSetting = await EditionV2.mintSettings(Dai.address);
      const quantity = 1;
      const totalFee = mintSetting.feeForBooster.mul(quantity);
      console.log("DAI total fee", totalFee);
      const nonce = await Dai.nonces(alice.address);
      const {v, r, s} = await getDaiPermitSignature(alice, Dai, EditionV2.address, deadline);
      const tx = EditionV2.connect(alice).userMintBoosterDaiPermit(Dai.address, quantity, nonce, true, v, r, s);
      await tx;

      const userTokens = await EditionV2.tokensByAccount(alice.address);
      expect(BOOSTER_TOKEN_ID).to.be.equal(userTokens[0]);

      const tokenUsers = await EditionV2.accountsByToken(userTokens[0]);
      expect(alice.address).to.be.equal(tokenUsers[0]);

      const aliceBal = await EditionV2.balanceOf(alice.address, BOOSTER_TOKEN_ID);
      expect(aliceBal).to.be.equal(1);
    });

  });
})
