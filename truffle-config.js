require("dotenv").config();
let HDWalletProvider = require("truffle-hdwallet-provider");

module.exports = {
  networks: {
    local: {
      host: "127.0.0.1",
      port: 7545,
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
          "https://ropsten.infura.io/v3/bd662e299bd84d23add2c296449da83b"
        ),
      network_id: '3',
      gasPrice: 15000000000,
    },
    kovan: {
      provider: () =>
        new HDWalletProvider(
          process.env.MORPHER_DEPLOYER_KEY,
          "https://kovan.infura.io/v3/bd662e299bd84d23add2c296449da83b"
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
};
