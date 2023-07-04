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
const settings = {
    name: "RoyaltyReceiver",
    localhost: {
        // replace these with your locally deployed ones
        geniusAddress: "0x5FbDB2315678afecb367f032d93F642f64180aa3",
        stabilityAddress: "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0",
        minersAddress: "0x0165878A594ca255338adfa4d48449f69242Eb8F",
        penaltyAddress: "0x5FC8d32690cc91D4c39d9d3abcBD16989F875707",
        genftAddress: "0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6",
    },
    fuji: {
        geniusAddress: "0x444444444444C1a66F394025Ac839A535246FCc8",
        stabilityAddress: "",
        minersAddress: "",
    },
    eth: {
        geniusAddress: "0x444444444444C1a66F394025Ac839A535246FCc8",
        stabilityAddress: "",
        minersAddress: "",
    },
    bsc: {
        geniusAddress: "0x444444444444C1a66F394025Ac839A535246FCc8",
        stabilityAddress: "",
        minersAddress: "",
    },
    polygon: {
        geniusAddress: "0x444444444444C1a66F394025Ac839A535246FCc8",
        stabilityAddress: "",
        minersAddress: "",
    },
    avax: {
        geniusAddress: "0x444444444444C1a66F394025Ac839A535246FCc8",
        stabilityAddress: "",
        minersAddress: "",
    },
    goerli: {
        geniusAddress: "0x1448cf0e964460CA18a2E2d8D56eb1eD5Aae085f",
        stabilityAddress: "0x9b122945152Db5EdF42A09b3eabf93C9b9b17490",
        minersAddress: "0x020983C9eFd12863B74618E25d978A25D1121afe",
        penaltyAddress: "0x135F2eeA67eC8e418ca57fB45E0320b65d2A8D21",
    }
}

async function main() {

    const { edition001V2PublicKey } = process.env;
    const [edition001V2PrivateKey] = await hre.ethers.getSigners();

    // Check if the running network is neither fuji nor avax
    // if (hre.network.name != 'fuji' && hre.network.name != 'avax') {
    //     console.error("The network is not Avalanche.");
    //     process.exit(0);
    // }

    // Check if the deployment variables are configured on Avalanche mainnet or testnet
    const config = settings[hre.network.name];
    if (config == undefined || config == null) {
        console.error(`${hre.network.name} is not configured yet`);
        process.exit(0);
    }

    // Deploy edition contract
    const RoyaltyReceiver = await deployContract(
        settings.name,
        [
            /**
        Genius.address,
        StabilityPool.address,
        Miners.address,
        Penalty.address
            **/
            config.geniusAddress,
            config.stabilityAddress,
            config.minersAddress,
            config.penaltyAddress,
            config.genftAddress
        ],
        edition001V2PrivateKey
    );
    await RoyaltyReceiver.deployed();
    console.log("RoyaltyReceiver deployed to: ", RoyaltyReceiver.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
