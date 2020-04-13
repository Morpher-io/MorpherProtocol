require('dotenv').config()
let HDWalletProvider = require("truffle-hdwallet-provider");

module.exports = {
    networks: {
        local: {
            host: "127.0.0.1",
            port: 7545,
            network_id: "*",
        },
        // Change values accordingly to connect to any chain.
        // dev: {
        //     host: "127.0.0.1",
        //     port: 7545,
        //     network_id: "*",
        // },
    },
    solc: {
        optimizer: {
            enabled: true,
            runs: 200
        }
    }
};
