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
    ethereum: {
        genftAddress: "0x4444444444329C1eC1E8e5aC8903d183F91f3A3f",
        genftV1Address: "0x001D763c42751edc67686eEE9efA844924434444",
        geniusAddress: "0x444444444444C1a66F394025Ac839A535246FCc8",
        minersAddress: "0x4444444ffA9bD8AF854Ea4E353756b06472F4444",
        geniusUltimateCost: "REPLACE_ME",
        geniusBoosterCost: "REPLACE_ME",
        nativeTokenUltimateCost: "REPLACE_ME",
        nativeTokenBoosterCost: "REPLACE_ME",
        stableCoinAddress: "REPLACE_ME",
        stableCoinUltimateCost: "REPLACE_ME",
        stableCoinBoosterCost: "REPLACE_ME",
        stabilityAddress: "0xDCA692d433Fe291ef72c84652Af2fe04DA4B4444",
        royaltyAddress: "REPLACE_ME",
    },
    polygon: {
        genftAddress: "0x4444444444329C1eC1E8e5aC8903d183F91f3A3f",
        genftV1Address: "0x001D763c42751edc67686eEE9efA844924434444",
        geniusAddress: "0x444444444444C1a66F394025Ac839A535246FCc8",
        minersAddress: "0x4444444ffA9bD8AF854Ea4E353756b06472F4444",
        geniusUltimateCost: "REPLACE_ME",
        geniusBoosterCost: "REPLACE_ME",
        nativeTokenUltimateCost: "REPLACE_ME",
        nativeTokenBoosterCost: "REPLACE_ME",
        stableCoinAddress: "REPLACE_ME",
        stableCoinUltimateCost: "REPLACE_ME",
        stableCoinBoosterCost: "REPLACE_ME",
        stabilityAddress: "0xDCA692d433Fe291ef72c84652Af2fe04DA4B4444",
        royaltyAddress: "REPLACE_ME",
    },
    bsc: {
        genftAddress: "0x4444444444329C1eC1E8e5aC8903d183F91f3A3f",
        genftV1Address: "0x001D763c42751edc67686eEE9efA844924434444",
        geniusAddress: "0x444444444444C1a66F394025Ac839A535246FCc8",
        minersAddress: "0x4444444ffA9bD8AF854Ea4E353756b06472F4444",
        geniusUltimateCost: "REPLACE_ME",
        geniusBoosterCost: "REPLACE_ME",
        nativeTokenUltimateCost: "REPLACE_ME",
        nativeTokenBoosterCost: "REPLACE_ME",
        stableCoinAddress: "REPLACE_ME",
        stableCoinUltimateCost: "REPLACE_ME",
        stableCoinBoosterCost: "REPLACE_ME",
        stabilityAddress: "0xDCA692d433Fe291ef72c84652Af2fe04DA4B4444",
        royaltyAddress: "REPLACE_ME",
    },
    avax: {
        genftAddress: "0x4444444444329C1eC1E8e5aC8903d183F91f3A3f",
        genftV1Address: "0x001D763c42751edc67686eEE9efA844924434444",
        geniusAddress: "0x444444444444C1a66F394025Ac839A535246FCc8",
        minersAddress: "0x4444444ffA9bD8AF854Ea4E353756b06472F4444",
        geniusUltimateCost: "REPLACE_ME",
        geniusBoosterCost: "REPLACE_ME",
        nativeTokenUltimateCost: "REPLACE_ME",
        nativeTokenBoosterCost: "REPLACE_ME",
        stableCoinAddress: "REPLACE_ME",
        stableCoinUltimateCost: "REPLACE_ME",
        stableCoinBoosterCost: "REPLACE_ME",
        stabilityAddress: "0xDCA692d433Fe291ef72c84652Af2fe04DA4B4444",
        royaltyAddress: "REPLACE_ME",
    },
    pls: {
        genftAddress: "0x4444444444329C1eC1E8e5aC8903d183F91f3A3f",
        genftV1Address: "0x001D763c42751edc67686eEE9efA844924434444",
        geniusAddress: "0x444444444444C1a66F394025Ac839A535246FCc8",
        minersAddress: "0x4444444ffA9bD8AF854Ea4E353756b06472F4444",
        geniusUltimateCost: "REPLACE_ME",
        geniusBoosterCost: "REPLACE_ME",
        nativeTokenUltimateCost: "REPLACE_ME",
        nativeTokenBoosterCost: "REPLACE_ME",
        stableCoinAddress: "REPLACE_ME",
        stableCoinUltimateCost: "REPLACE_ME",
        stableCoinBoosterCost: "REPLACE_ME",
        stabilityAddress: "0xDCA692d433Fe291ef72c84652Af2fe04DA4B4444",
        royaltyAddress: "REPLACE_ME",
    },
    goerli: {
        genftAddress: "0xE5bF09BC61E440C4A15686bE37899F79b98912dD",
        genftV1Address: "0x565b3C2cbd37D6a82C53a5FcB9BE02377390d877",
        minersAddress: "0x020983C9eFd12863B74618E25d978A25D1121afe",
        calendarAddress: "0xBD98D40DEF0D6BC462E62af8e775A74A984A2cD6",
        geniusAddress: "0x1448cf0e964460CA18a2E2d8D56eb1eD5Aae085f",
        geniusUltimateCost: "88800000000000",
        geniusBoosterCost: "22220000000000",
        nativeTokenUltimateCost: "1346474601971190000",
        nativeTokenBoosterCost: "336921910538287000",
        // MakerDao's DAI
        stableCoinAddress: "0xeF5C6b0e42ca730264779F65A8CE0Ca192ff2723",
        stableCoinUltimateCost: "17760000",
        stableCoinBoosterCost: "4444000",
        stabilityAddress: "0x9b122945152Db5EdF42A09b3eabf93C9b9b17490",
        royaltyAddress: "0x87f98305fE507Ed74624a75A53320500C01ca268",
    },
    fuji: {
        genftAddress: "0x4444444444329C1eC1E8e5aC8903d183F91f3A3f",
        genftV1Address: "0x001D763c42751edc67686eEE9efA844924434444",
        geniusAddress: "0x444444444444C1a66F394025Ac839A535246FCc8",
        minersAddress: "0x4444444ffA9bD8AF854Ea4E353756b06472F4444",
        calendarAddress: "0x44444489FA9588870d4e06003B516d54A2af4444",
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
    localhost: {
        // replace these with your locally deployed ones
        genftAddress: "0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6",
        genftV1Address: "0x59b670e9fA9D0A427751Af201D676719a970857b",
        geniusAddress: "0x5FbDB2315678afecb367f032d93F642f64180aa3",
        minersAddress: "0x0165878A594ca255338adfa4d48449f69242Eb8F",
        calendarAddress: "0xdc64a140aa3e981100a9beca4e685f962f0cf6c9",
        geniusUltimateCost: "88800000000000",
        geniusBoosterCost: "22220000000000",
        nativeTokenUltimateCost: "1346474601971190000",
        nativeTokenBoosterCost: "336921910538287000",
        stableCoinAddress: "0x9A9f2CCfdE556A7E9Ff0848998Aa4a0CFD8863AE",
        stableCoinUltimateCost: "17760000000000000000",
        stableCoinBoosterCost: "4444000000000000000",
        stabilityAddress: "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0",
        royaltyAddress: "0xa85233C63b9Ee964Add6F2cffe00Fd84eb32338f",
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
    const Edition = await deployContract(
        edition.name,
        [
            config.geniusAddress,
            config.genftAddress,
            config.stabilityAddress,
            config.calendarAddress,
            config.royaltyAddress,
            config.genftV1Address,
            edition.baseURI
        ],
        edition001V2PrivateKey
    );
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
