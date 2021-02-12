const MorpherOracle = artifacts.require("MorpherOracle");

const truffleAssert = require('truffle-assertions');

contract('MorpherOracle delist Market', (accounts) => {
    it('test MorpherOracle delistMarket emits the correct events', async () => {
        const deployerAddress = accounts[0]; const testAddress1 = accounts[1]; const testAddress2 = accounts[2];
        const oracle = await MorpherOracle.deployed();
        let result = await oracle.delistMarket(web3.utils.sha3('CRYPTO_BTC'), true);
        truffleAssert.eventEmitted(result, "DelistMarketComplete");
    });
});