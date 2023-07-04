/**
 * @title deployment script to deploy and set up edition update version contract
 * @description  No need to edit/modify this script, unless extra transactions need to be automated.
 * @author dai
 * @notice how to use
 * full command: npx hardhat run scripts/deploy-edition001.js --network fuji
 * short command: yarn deploy-edition-<network name>
 * e.g: yarn deploy-fuji
 *
 */
const hre = require("hardhat");
const { ethers } = require("ethers");

const { deployContract, getContract } = require('./helpers/contracts-helpers');
const { eContractid } = require('./helpers/type');

// Define Edition info
const edition = {
    name: "Edition001V2",
    baseURI: "ipfs://QmREBr7uRAL1bCRnSVRv4mGfMHV2b4YaEX7gAuLYdvzxwF/",
    goerli: {
        genftAddress: "0x5721f0b80e5d1dc889BF906565715428a960fE25",
        genftV1Address: "0x2A5e2198C58b02344A514f4488E3A58A58C9D38b",
        geniusAddress: "0x112ec839ab7e237639Efe75DdB123c069c41f973",
        geniusUltimateCost: "88800000000000",
        geniusBoosterCost: "22220000000000",
        nativeTokenUltimateCost: "1000000000000000",
        nativeTokenBoosterCost: "100000000000000",
        // MakerDao's DAI
        stableCoinAddress: "0xeF5C6b0e42ca730264779F65A8CE0Ca192ff2723",
        stableCoinUltimateCost: "17760000",
        stableCoinBoosterCost: "4444000",
        stabilityAddress: "0x0189AfD6b184858A8B8ED6c9fCD87019097d316b",
        royaltyAddress: "0xC2cF3B1423d685777e8f6ac8F7C8bB6768765C91",
    },
    fuji: {
        genftAddress: "0x4444444444329C1eC1E8e5aC8903d183F91f3A3f",
        genftV1Address: "0x001D763c42751edc67686eEE9efA844924434444",
        geniusAddress: "0x444444444444C1a66F394025Ac839A535246FCc8",
        geniusUltimateCost: "88800000000000",
        geniusBoosterCost: "22220000000000",
        nativeTokenUltimateCost: "1346474601971190000",
        nativeTokenBoosterCost: "336921910538287000",
        // MakerDao's DAI
        stableCoinAddress: "0x8f3cf7ad23cd3cadbd9735aff958023239c6a063",
        stableCoinUltimateCost: "17760000",
        stableCoinBoosterCost: "4444000",
        stabilityAddress: "0xDCA692d433Fe291ef72c84652Af2fe04DA4B4444",
        royaltyAddress: "",
    },
    avax: {
        genftAddress: "0x4444444444329C1eC1E8e5aC8903d183F91f3A3f",
        genftV1Address: "0x001D763c42751edc67686eEE9efA844924434444",
        geniusAddress: "0x444444444444C1a66F394025Ac839A535246FCc8",
        geniusUltimateCost: "88800000000000",
        geniusBoosterCost: "22220000000000",
        nativeTokenUltimateCost: "1346474601971190000",
        nativeTokenBoosterCost: "336921910538287000",
        stableCoinAddress: "0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664",
        stableCoinUltimateCost: "17760000",
        stableCoinBoosterCost: "4444000",
        stabilityAddress: "0xDCA692d433Fe291ef72c84652Af2fe04DA4B4444",
        royaltyAddress: "",
    },
}

// Helper to log userMint
const logger = (colName, colAddress, ultimateCost, boosterCost) => {
    console.log(`=> Define ${colName} for user minting`);
    console.log(`   Collateral token address: ${colAddress}`);
    console.log(`   Ultimate Cost:            ${ultimateCost}`);
    console.log(`   Booster Cost:             ${boosterCost}`);
}

async function main() {

    const { edition001V2PublicKey } = process.env;
    const [edition001V2PrivateKey] = await hre.ethers.getSigners();

    // Check if the running network is neither fuji nor avax

    // Check if the deployment variables are configured on Avalanche mainnet or testnet
    const config = edition[hre.network.name];
    if (config == undefined || config == null) {
        console.error(`${hre.network.name} is not configured yet`);
        process.exit(0);
    }

    // Check if the edition already was deployed at the previous version's address.
    const code = await hre.ethers.provider.getCode(edition001V2PublicKey);
    if(code != '0x') {
        console.error(`Edition contract already was deployed at ${edition001V2PublicKey}`);
        process.exit(0);
    }

    // Deploy edition contract
    const Edition = await getContract(edition.name);
    const Genius = await getContract(eContractid.Genius, config.geniusAddress);
    const oaGrantor = await hre.ethers.getSigner(await Genius.oaGrantor());
    console.log(`oaGrantor account address: ${oaGrantor.address}`);

    // Call for the Native Token, Stable Coin, and Genius token.
    // Waiting until the txn has 1 confirmation
    logger("Native Token", ethers.constants.AddressZero, config.nativeTokenUltimateCost, config.nativeTokenBoosterCost);
    await (
        await Edition.connect(oaGrantor).defineUserMints(
            ethers.constants.AddressZero,
            config.nativeTokenUltimateCost,
            config.nativeTokenBoosterCost
        )
    ).wait(1);

    // Waiting until the txn has 1 confirmation
    logger("Stable Coin", config.stableCoinAddress, config.stableCoinUltimateCost, config.stableCoinBoosterCost);
    await (
        await Edition.connect(oaGrantor).defineUserMints(
            config.stableCoinAddress,
            config.stableCoinUltimateCost,
            config.stableCoinBoosterCost
        )
    ).wait(1);

    // Waiting until the txn has 1 confirmation
    logger("Genius Token", config.geniusAddress, config.geniusUltimateCost, config.geniusBoosterCost);
    await (
        await Edition.connect(oaGrantor).defineUserMints(
            config.geniusAddress,
            config.geniusUltimateCost,
            config.geniusBoosterCost
        )
    ).wait(1);

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
