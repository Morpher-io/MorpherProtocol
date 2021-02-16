const MorpherOracle = artifacts.require("MorpherOracle");
const MorpherState = artifacts.require("MorpherState");
const MorpherToken = artifacts.require("MorpherToken");
const MorpherTradeEngine = artifacts.require("MorpherTradeEngine");

const truffleAssert = require('truffle-assertions');

const { roundToInteger, getLeverage } = require('./helpers/tradeFunctions');

let BTC = '0x0bc89e95f9fdaab7e8a11719155f2fd638cb0f665623f3d12aab71d1a125daf9';

const BN = require("bn.js");

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


contract('MorpherOracle lock in price testing', (accounts) => {
    it('user cant trade an inactive market', async () => {
        const [deployerAddress, testAddress1] = accounts;
        const oracle = await MorpherOracle.deployed();
        const state = await MorpherState.deployed();
        const morpherToken = await MorpherToken.deployed();
        await morpherToken.transfer(testAddress1, web3.utils.toWei("1", "ether"));
        
        let userBalance = await morpherToken.balanceOf(testAddress1);
        assert.equal(userBalance.toString(), web3.utils.toWei("1", "ether"));
        /**
         * Create a position
         */
        let orderId = (await oracle.createOrder(BTC, 0, roundToInteger(500), true, getLeverage(1), 0, 0, 0, 0, { from: testAddress1 })).logs[0].args._orderId;
        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await oracle.__callback(orderId, roundToInteger(100), roundToInteger(100), 0, 0, 0, 0, { from: deployerAddress });
        
        userBalance = await morpherToken.balanceOf(testAddress1);
        assert.equal(userBalance.toString(), web3.utils.toWei(new BN(1), "ether").sub(new BN(roundToInteger(500))).toString());

        await state.deActivateMarket(BTC);

        await truffleAssert.fails(oracle.createOrder(BTC, 0, roundToInteger(500), true, getLeverage(1), 0, 0, 0, 0, { from: testAddress1 }), truffleAssert.ErrorType.REVERT);
    });

    
    it('user cant close an inactive position if market locked in price was not set', async () => {
        const [deployerAddress, testAddress1] = accounts;
        const oracle = await MorpherOracle.deployed();
        const state = await MorpherState.deployed();
        

        //try to close the position from above
        await truffleAssert.fails(oracle.createOrder(BTC, 5, 0, false, getLeverage(1), 0, 0, 0, 0, { from: testAddress1 }), truffleAssert.ErrorType.REVERT, "MorpherTradeEngine: Can't close a position, market not active and closing price not locked");
        
    });

    it('A forever price can be set to close a market which is not active anymore', async () => {
        
        const [deployerAddress, testAddress1] = accounts;
        const oracle = await MorpherOracle.deployed();
        const morpherTradeEngine = await MorpherTradeEngine.deployed();
        let result = await oracle.setDeactivatedMarketPrice(BTC, roundToInteger(100));
        await truffleAssert.eventEmitted(result, 'LockedPriceForClosingPositions');

        let price = await morpherTradeEngine.getDeactivatedMarketPrice(BTC);
        assert.equal(price.toString(), roundToInteger(100));
    });

    
    it('user cant partially close an inactive position if market locked in price was set', async () => {
        const [deployerAddress, testAddress1] = accounts;
        const oracle = await MorpherOracle.deployed();
        
        //try to close the position from above
        await truffleAssert.fails(oracle.createOrder(BTC, 4, 0, false, getLeverage(1), 0, 0, 0, 0, { from: testAddress1 }), truffleAssert.ErrorType.REVERT, "MorpherTradeEngine: Deactivated market order needs all shares to be closed");

    });

    it('user can fully close an inactive position if market locked in price was set', async () => {
        const [deployerAddress, testAddress1] = accounts;
        const oracle = await MorpherOracle.deployed();
        
        const morpherToken = await MorpherToken.deployed();
        
        //try to close the position from above
        let result = await oracle.createOrder(BTC, 5, 0, false, getLeverage(1), 0, 0, 0, 0, { from: testAddress1 });
        await truffleAssert.eventEmitted(result, 'OrderProcessed');
        let userBalance = await morpherToken.balanceOf(testAddress1);
        assert.equal(userBalance.toString(), web3.utils.toWei("1", "ether"));
    });

});

function pad_with_zeroes(number, length) {

    var my_string = '' + number;
    while (my_string.length < length) {
        my_string = '0' + my_string;
    }

    return my_string;

}