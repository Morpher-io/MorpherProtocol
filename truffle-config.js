require("dotenv").config();
let HDWalletProvider = require("@truffle/hdwallet-provider");

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
          process.env.MORPHER_DEPLOYER_PK,
          "https://sidechain.morpher.com"
        ),
      network_id: "21",
      timeoutBlocks: 200,
    },
    morphertest: {
      provider: () =>
        new HDWalletProvider(
          [process.env.MORPHER_DEPLOYER_PK, process.env.MORPHER_ADMINISTRATOR_KEY],
          "wss://sidechain-test-ws.morpher.com:8546"
        ),
      network_id: "21",
      chainId: 21,
      //timeoutBlocks: 200,
    },
    ropsten: {
      provider: () =>
        new HDWalletProvider(
          process.env.MORPHER_DEPLOYER_KEY,
          "wss://ropsten.infura.io/ws/v3/" + process.env.INFURA_PROJECT_ID
        ),
      network_id: '3',
      gasPrice: 15000000000,
    },
    mainnet: {
      provider: () =>
        new HDWalletProvider(
          process.env.MORPHER_DEPLOYER_PK,
          "wss://mainnet.infura.io/ws/v3/" + process.env.INFURA_PROJECT_ID
        ),
      network_id: '1',
      gasPrice: 150000000000,
    },
    kovan: {
      provider: () =>
        new HDWalletProvider(
          process.env.MORPHER_DEPLOYER_PK,
          "wss://kovan.infura.io/ws/v3/" + process.env.INFURA_PROJECT_ID
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
