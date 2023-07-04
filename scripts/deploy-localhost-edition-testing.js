// NOTE: The Genius Smart Financial Contract repository is required to properly
// run the tests for the Royalty Receiver Contract.  Replace GENIUS_REPO_PATH
// with the actual path to the repository.
//
// If you do not have the repository, modify the JSON file to include the
// contract addresses on testnet.  The testnet contract addresses on testnet are
// the same as the addresses for mainnet.  For additional help, visit the public
// telegram chat room for Genius Development: https://t.me/genicryptodev
const hre = require("hardhat");
const fs = require('fs');
const {deployContract, getContract} = require('./helpers/contracts-helpers');
const {ethers} = require('ethers');
const {eContractid} = require('./helpers/type');
const {addDays} = require('./helpers/misc-utils');

async function main() {
  const [account0, account1] = await hre.ethers.getSigners();
  // Genius testnet setup:
  const addresses = fs.readFileSync("./data/genius-contract-addresses.json", "utf-8");
  // Genius local development setup:
//  const addresses = fs.readFileSync("GENIUS_REPO_PATH/data/addresses.json", "utf-8");
  const {Genius, StabilityPool, Miners, Penalty, Genft, Calendar, Edition001Old, Dai} = JSON.parse(addresses);



  const GeniusContract = await getContract("Genius", Genius);
  const GenftContract = await getContract('Genft', Genft);
  const oaGrantor = await hre.ethers.getSigner(await GeniusContract.oaGrantor());

  const RoyaltyReceiver = await deployContract(
    "RoyaltyReceiver",
    [
      Genius,
      StabilityPool,
      Miners,
      Penalty,
      Genft
    ],
    oaGrantor
  );
  await RoyaltyReceiver.deployed();

  const EditionV2 = await deployContract(
    "Edition001V2",
    [
      Genius,
      Genft,
      StabilityPool,
      Calendar,
      RoyaltyReceiver.address,
      Edition001Old,
      "ipfs://QmREBr7uRAL1bCRnSVRv4mGfMHV2b4YaEX7gAuLYdvzxwF/"
    ],
    oaGrantor
  );
  await EditionV2.deployed();

  await (
    await EditionV2.connect(oaGrantor).defineUserMints(
      ethers.constants.AddressZero,
      "1346474601971190000",
      "336921910538287000"
    )
  ).wait(1);

  await (
    await EditionV2.connect(oaGrantor).defineUserMints(
      Dai,
      "17760000000000000000",
      "4444000000000000000"
    )
  ).wait(1);

  await (
    await EditionV2.connect(oaGrantor).defineUserMints(
      Genius,
      "88800000000000",
      "22220000000000"
    )
  ).wait(1);


  let tx;
  const edition001Contract = await getContract('Edition001', Edition001Old);
  //   26. Set New Edition to v2
  GenftContract.connect(oaGrantor).newEdition(EditionV2.address);
  //   27. Approve access to all v1 GENFTs
  tx = await edition001Contract.connect(account0).setApprovalForAll(EditionV2.address, true);
  await tx.wait();
  //   28. Convert v1 GENFTs
  tx = await EditionV2.connect(account0).convert();
  await tx.wait();
  //   29. Permit unlimited GENI spend for v2 GENFTs contract
  tx = await GeniusContract.connect(oaGrantor).approve(EditionV2.address, ethers.constants.MaxUint256);
  await tx.wait();
  //   30. Buy 23 Ultimate Packs 🙂
  tx = await EditionV2.connect(account0).userMintUltimate(Genius, 23);
  await tx.wait();
  // 31. Buy 3 Booster Packs 🙂
  tx = await EditionV2.connect(account0).userMintBooster(Genius, 3);
  await tx.wait();
  //   32. RRC#deployToken (GENI)
  tx = await RoyaltyReceiver.connect(oaGrantor).deployToken(Genius, true);
  await tx.wait();

// may need this for reference
//  const GeniusContract = await getContract("Genius", Genius);
//  tx = await StabilityPool.connect(oaGrantor).endCollateral(Dai);
//  await tx.wait();
//  tx = await StabilityPool.connect(oaGrantor).endCollateral(Dai);

  await addDays(61);
  const calendarContract = await getContract('Calendar', Calendar);
  await calendarContract.connect(account0).makeGeniusDaySummary(61, false);

  console.log('-------------------------------');
  console.log(JSON.parse(addresses));
  console.log('-------------------------------');
  console.log('RoyaltyReceiver: ', RoyaltyReceiver.address);
  console.log('EditionV2: ', EditionV2.address);

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });


