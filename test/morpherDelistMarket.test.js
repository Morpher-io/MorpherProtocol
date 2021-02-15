const MorpherOracle = artifacts.require("MorpherOracle");
const MorpherState = artifacts.require("MorpherState");

const truffleAssert = require('truffle-assertions');

let BTC = '0x0bc89e95f9fdaab7e8a11719155f2fd638cb0f665623f3d12aab71d1a125daf9';

contract('MorpherOracle delist Market', (accounts) => {
    it('test MorpherOracle delistMarket emits the correct events', async () => {
        const deployerAddress = accounts[0]; const testAddress1 = accounts[1]; const testAddress2 = accounts[2];
        const oracle = await MorpherOracle.deployed();
        let result = await oracle.delistMarket(web3.utils.sha3('CRYPTO_BTC'), true);
        truffleAssert.eventEmitted(result, "DelistMarketComplete");
    });

    it('test MorpherOracle delistMarket emits the correct events', async () => {
        const [deployerAddress, addr1, addr2, addr3, addr4, addr5, addr6, addr7] = accounts;
        const morpherState = await MorpherState.deployed();
        await morpherState.setPosition(addr1, BTC, 0, 100, 0, 100000000, 0, 100000000, 0, { from: deployerAddress });
        await morpherState.setPosition(addr2, BTC, 0, 100, 0, 100000000, 0, 100000000, 0, { from: deployerAddress });
        await morpherState.setPosition(addr3, BTC, 0, 100, 0, 100000000, 0, 100000000, 0, { from: deployerAddress });
        await morpherState.setPosition(addr4, BTC, 0, 100, 0, 100000000, 0, 100000000, 0, { from: deployerAddress });
        await morpherState.setPosition(addr5, BTC, 0, 100, 0, 100000000, 0, 100000000, 0, { from: deployerAddress });
        const oracle = await MorpherOracle.deployed();
        let result = await oracle.delistMarket(BTC, true);
        truffleAssert.eventEmitted(result, "DelistMarketComplete");
    });

    it('test MorpherOracle delistMarket emits the correct events', async () => {
        const [deployerAddress] = accounts;
        const morpherState = await MorpherState.deployed();
        for (let i = 1; i <= 30; i++) {
            await morpherState.setPosition("0x" + pad_with_zeroes(i, 40), BTC, 0, 100, 0, 100000000, 0, 100000000, 0, { from: deployerAddress });
        }
        const oracle = await MorpherOracle.deployed();
        let result = await oracle.delistMarket(BTC, true, { gas: 300000 });
        truffleAssert.eventEmitted(result, "DelistMarketIncomplete");
        
        result = await oracle.delistMarket(BTC, false);
        truffleAssert.eventEmitted(result, "DelistMarketComplete");
    });
});

function pad_with_zeroes(number, length) {

    var my_string = '' + number;
    while (my_string.length < length) {
        my_string = '0' + my_string;
    }

    return my_string;

}