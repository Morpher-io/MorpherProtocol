require("dotenv").config();
let HDWalletProvider = require("@truffle/hdwallet-provider");
let Web3 = require("web3");

module.exports = {
  networks: {
    local: {
      // provider: () =>
      //   new HDWalletProvider(
      //     process.env.MORPHER_DEPLOYER_KEY,
      //     new Web3.providers.WebsocketProvider('http://127.0.0.1:8545'), 0, 5
      //   ),
      host: '127.0.0.1',
      port: '7545',
      network_id: "*",
      //from: '0x346D8BA24650Ba37c42750a84810613Abb4A83FB',
      test_timeout: 3600000,
    },
    morpher: {
      provider: () =>
        new HDWalletProvider(
          process.env.MORPHER_DEPLOYER_KEY,
          "https://sidechain.morpher.com"
        ),
      network_id: "21",
      timeoutBlocks: 200,
    },
    ropsten: {
      provider: () =>
        new HDWalletProvider(
          process.env.MORPHER_DEPLOYER_KEY,
          "https://ropsten.infura.io/v3/" + process.env.INFURA_PROJECT_ID
        ),
      network_id: '3',
      gasPrice: 15000000000,
    },
    kovan: {
      provider: () =>
        new HDWalletProvider(
          process.env.MORPHER_DEPLOYER_KEY,
          "https://kovan.infura.io/v3/"  + process.env.INFURA_PROJECT_ID
        ),
      network_id: '*',
      gasPrice: 2000000000,
    },
  },
  compilers: {
    solc: {
      version: "0.5.16",
      settings: {
        optimizer: {
          enabled: true,
          runs: 200,
        },
      },
    },
  },
  mocha: {
    enableTimeouts: false,
    before_timeout: 3600000,
    test_timeout: 3600000,
  }
};
