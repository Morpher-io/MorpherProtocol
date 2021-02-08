require("dotenv").config();
let HDWalletProvider = require("truffle-hdwallet-provider");

module.exports = {
  networks: {
    local: {
      host: "127.0.0.1",
      port: 8545,
      network_id: "*",
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
          process.env.MORPHER_DEPLOYER_PK,
          "https://kovan.infura.io/v3/" + process.env.INFURA_PROJECT_ID
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
    before_timeout: 120000 // Here is 2min but can be whatever timeout is suitable for you.
  }
};
