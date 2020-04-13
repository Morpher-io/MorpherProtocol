const MorpherToken = artifacts.require("MorpherToken");
const MorpherTradeEngine = artifacts.require("MorpherTradeEngine");
const MorpherOracle = artifacts.require("MorpherOracle");

const truffleAssert = require('truffle-assertions');

const CRYPTO_BTC = '0x0bc89e95f9fdaab7e8a11719155f2fd638cb0f665623f3d12aab71d1a125daf9';

contract('MorpherOracle', (accounts) => {
    it('test initial state and create order functionality', async () => {
        const deployerAddress = accounts[0]; const testAddress1 = accounts[1]; const testAddress2 = accounts[2];

        const morpherOracle = await MorpherOracle.deployed();
        const morpherTradeEngine = await MorpherTradeEngine.deployed();
        const morpherToken = await MorpherToken.deployed();

        // Topup test accounts with MorpherToken.
        await morpherToken.transfer(testAddress1, '1000000000000', { from: deployerAddress });
        await morpherToken.transfer(testAddress2, '1000000000000', { from: deployerAddress });

        // Test successful state variables change and order creation.
        await morpherOracle.setGasForCallback('400000000000000');
        await morpherOracle.enableCallbackAddress(testAddress2);
        const orderId1 = (await morpherOracle.createOrder(CRYPTO_BTC, true, 10, true, 100000000, { from: testAddress1, value: '400000000000000' })).logs[0].args._orderId;

        const gasForCallback = await morpherOracle.gasForCallback();
        const isTestAddress2CallbackAddress = await morpherOracle.callBackAddress(testAddress2);

        // Asserts
        assert.equal(gasForCallback.toString(), '400000000000000');
        assert.equal(isTestAddress2CallbackAddress, true);
        assert.notEqual(orderId1, null);

        // Set gasForCallback back to 0 for ease of use in the assertions below
        await morpherOracle.setGasForCallback('0');

        // Test order failure if oracle is paused.
        await morpherOracle.pauseOracle({ from: deployerAddress });

        await truffleAssert.reverts(morpherOracle.createOrder(CRYPTO_BTC, true, 200, true, 100000000, { from: testAddress1 }), "Oracle paused");
        // await truffleAssert.reverts(morpherOracle.cancelOrder(orderId1, { from: testAddress1 }), "Oracle paused");
        await truffleAssert.reverts(morpherOracle.__callback(orderId1, 100000000, 1000000, 0, 1234, { from: testAddress2 }), "Oracle paused");

        // Test last created order is orderId1 not orderId2 because Oracle was paused.
        const lastOrderId = await morpherTradeEngine.lastOrderId();
        assert.equal(lastOrderId, orderId1);

        // Test order creation after unpausing oracle.
        await morpherOracle.unpauseOracle({ from: deployerAddress });

        await morpherOracle.__callback(orderId1, 100000000, 1000000, 0, 1234, { from: testAddress2 });

        // orderID1 should have '0' values because we successfully called the callback.
        const firstOrder = await morpherTradeEngine.getOrder(orderId1);
        assert.equal(firstOrder._tradeAmount, '0'); // callback was called successfully

        // Test new order creation and cancellation.
        const orderId3 = (await morpherOracle.createOrder(CRYPTO_BTC, true, 200, true, 100000000, { from: testAddress1 })).logs[0].args._orderId;
        assert.notEqual(orderId3, null);

        await morpherOracle.cancelOrder(orderId3, { from: testAddress1 });

        const thirdOrder = await morpherTradeEngine.getOrder(orderId3);
        assert.equal(thirdOrder._tradeAmount, '0'); // callback was called successfully
    });
});