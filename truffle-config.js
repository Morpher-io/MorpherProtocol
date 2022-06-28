require("dotenv").config();
let HDWalletProvider = require("@truffle/hdwallet-provider");

module.exports = {
  contracts_directory: './contracts/',
  networks: {
    local: {
      host: "127.0.0.1",
      port: 8545,
      network_id: "*",
      //websockets: true
    },
    morpher: {
      provider: () =>
        new HDWalletProvider(
          process.env.DEPLOYER_PK,
          "wss://sidechain-ws.morpher.com:8546"
        ),
      network_id: "21",
      timeoutBlocks: 200,
      blockscoutUrl: "https://blockscout-prod-164690568.eu-central-1.elb.amazonaws.com",
      verify: {
        apiUrl: 'https://scan.morpher.com/api',
        apiKey: '',
        explorerUrl: 'https://scan.morpher.com/',
      }
    },
    polygon: {
     
        host: "https://rpc-mainnet.matic.network",
        port: 8545,
        network_id: "*",
        //websockets: true
      network_id: "137",
      timeoutBlocks: 200
    },
    morphertest: {
      provider: () =>
      new HDWalletProvider(
        process.env.MORPHER_DEPLOYER_PK,
        "wss://sidechain-staging.morpher.com:8546"
      ),
      network_id: "211",
      chainId: 211,
      networkCheckTimeout: 5000
      //timeoutBlocks: 200,
    },
    ropsten: {
      provider: () =>
        new HDWalletProvider(
          [process.env.MORPHER_DEPLOYER_PK, process.env.MORPHER_ADMINISTRATOR_KEY],
          "wss://ropsten.infura.io/ws/v3/" + process.env.INFURA_PROJECT_ID
        ),
      network_id: '3',
      gasPrice: 15000000000,
    },
    mainnet: {
      provider: () =>
        new HDWalletProvider(
          process.env.DEPLOYER_PK,
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
    mumbai: {
      provider: () =>
      new HDWalletProvider(
        process.env.DEPLOYER_PK,
       "https://matic-testnet-archive-rpc.bwarelabs.com"
      ),
      network_id: '*',
      chainId: '80001',
      gasPrice: 1500000000,
      networkCheckTimeout: 15000
    },
  },
  compilers: {
    solc: {
      version: "0.8.11",
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
  },
  blockscoutUrl: 'http://sidechain-dev.morpher.com:8082',
  plugins: ['truffle-plugin-verify', 'truffle-plugin-stdjsonin'],
  api_keys: {
    etherscan: process.env.ETHERSCAN_API_KEY,
    polygonscan: process.env.POLYGONSCAN_API_KEY
  }
};
