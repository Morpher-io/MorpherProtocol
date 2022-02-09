require("dotenv").config();
let HDWalletProvider = require("@truffle/hdwallet-provider");
<<<<<<< HEAD
let Web3 = require("web3");
=======
const Web3 = require('web3');
>>>>>>> master

module.exports = {
  networks: {
    local: {
      host: "127.0.0.1",
      port: 8545,
      network_id: "*",
      //from: '0x346D8BA24650Ba37c42750a84810613Abb4A83FB',
      test_timeout: 3600000,
    },
    morpher: {
      provider: () =>
        new HDWalletProvider(
          process.env.MORPHER_DEPLOYER_PK,
          "https://sidechain.morpher.com"
        ),
      network_id: "21",
      timeoutBlocks: 200,
    },
    morphertest: {
      provider: () =>
        new HDWalletProvider(
          [process.env.MORPHER_ADMINISTRATOR_KEY],
          "https://sidechain-test.morpher.com"
        ),
      network_id: "21",
      chainId: 21,
      timeoutBlocks: 200,
    },
    ropsten: {
      provider: () =>
        new HDWalletProvider(
          process.env.MORPHER_DEPLOYER_KEY,
          new Web3.providers.WebsocketProvider("wss://ropsten.infura.io/ws/v3/" + process.env.INFURA_PROJECT_ID)
        ),
      network_id: '3',
      gasPrice: 15000000000,
    },
    mainnet: {
      provider: () =>
        new HDWalletProvider(
          process.env.MORPHER_DEPLOYER_PK,
          new Web3.providers.WebsocketProvider("wss://mainnet.infura.io/ws/v3/" + process.env.INFURA_PROJECT_ID)
        ),
      network_id: '1',
      gasPrice: 150000000000,
    },
    kovan: {
      provider: () =>
        new HDWalletProvider(
          process.env.MORPHER_DEPLOYER_PK,
          new Web3.providers.WebsocketProvider("wss://kovan.infura.io/ws/v3/" + process.env.INFURA_PROJECT_ID)
        ),
      network_id: '*',
      gasPrice: 10000000000,
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
    before_timeout: 120000 // Here is 2min but can be whatever timeout is suitable for you.
  }
};
