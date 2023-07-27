// Variables to replace, below:
//      * COINMARKETCAP_API_KEY
require("hardhat-prettier");
require("@nomicfoundation/hardhat-toolbox");
require('dotenv').config();
require("hardhat-contract-sizer");
require("hardhat-gas-reporter");
require('dotenv').config();
const {
  edition001V2PublicKey,
  edition001V2PrivateKey,
  oaGrantorPrivateKey
} = process.env;

const {
//  goerli,
//  fuji,
//  eth,
//  bsc,
//  polygon,
//  avax
} = process.env;

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.4",
        settings: {
          optimizer: {
            enabled: true,
            runs: 50,
          },
        },
      }
    ]
  },
  networks: {
    hardhat: {
      blockGasLimit: 352450000,
      allowUnlimitedContractSize: true
    },
//    goerli: {
//      url: goerli,
//      accounts: [
//        edition001V2PrivateKey,
//        oaGrantorPrivateKey
//      ],
//    },
//    fuji: {
//      url: fuji,
//      accounts: [
//        edition001V2PrivateKey,
//        oaGrantorPrivateKey
//      ],
//    },
//    eth: {
//      url: eth,
//      accounts: [
//        edition001V2PrivateKey,
//        oaGrantorPrivateKey
//      ],
//    },
//    bsc: {
//      url: bsc,
//      accounts: [
//        edition001V2PrivateKey,
//        oaGrantorPrivateKey
//      ],
//    },
//    polygon: {
//      url: polygon,
//      accounts: [
//        edition001V2PrivateKey,
//        oaGrantorPrivateKey
//      ],
//    },
//    avax: {
//      url: avax,
//      accounts: [
//        edition001V2PrivateKey,
//        oaGrantorPrivateKey
//      ],
//    },
  },
  gasReporter: {
    enabled: true,
    //gasPrice: 112, // gwei
    currency: "ETH",
    token: "ETH",
    coinmarketcap: process.env.COINMARKETCAP_API_KEY, 
    //gasPriceApi: "https://api.etherscan.io/api?module=proxy&action=eth_gasPrice"
  },
};
