require('dotenv').config()
let HDWalletProvider = require("truffle-hdwallet-provider");

module.exports = {
    networks: {
        local: {
            host: "127.0.0.1",
            port: 7545,
            network_id: "*",
        },
        morpher: {
            provider: () => new HDWalletProvider(process.env.MORPHER_DEPLOYER_KEY, "https://sidechain.morpher.com"),
            network_id: "21",
            timeoutBlocks: 200,
        },
    },
    solc: {
        optimizer: {
            enabled: true,
            runs: 200
        }
    }
};
