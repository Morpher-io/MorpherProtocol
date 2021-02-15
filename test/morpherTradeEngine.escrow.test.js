const MorpherToken = artifacts.require("MorpherToken");
const MorpherTradeEngine = artifacts.require("MorpherTradeEngine");
const MorpherOracle = artifacts.require("MorpherOracle");

const truffleAssert = require('truffle-assertions');
const BN = require("bn.js");

const { getLeverage } = require('./helpers/tradeFunctions');

const MARKET = 'CRYPTO_BTC';
const gasPriceInGwei = 200; //gwei gas price for callback funding

const historicalGasConsumptionFromOracle = []; //an array that holds the gas 

const average = arr => arr.reduce((sume, el) => sume + el, 0) / arr.length;

const escrowAddress = "0x1111111111111111111111111111111111111111";

contract('MorpherOracle', (accounts) => {

    const [
        deployerAddress,
        testUserAddress,
        oracleCallbackAddress
    ] = accounts;


    it('Escrow 100 MPH with 100 MPH open position with 100 MPH price will have 1 share and User has 0 tokens left', async () => {
        
        const morpherOracle = await MorpherOracle.deployed();
        const morpherTradeEngine = await MorpherTradeEngine.deployed();
        const morpherToken = await MorpherToken.deployed();

        // Topup test accounts with MorpherToken.
        await morpherToken.transfer(testUserAddress, 10, { from: deployerAddress }); //10 tokens to address

        // Test successful state variables change and order creation.
        await morpherOracle.overrideGasForCallback(0);
        await morpherOracle.enableCallbackAddress(oracleCallbackAddress);

        const txReceipt = await morpherOracle.createOrder(web3.utils.sha3(MARKET), 0, 10, true, getLeverage(1), 0, 0, 0, 0, { from: testUserAddress }); //10 tokens open order

        const balanceAfterOpenOrder = await morpherToken.balanceOf(escrowAddress);
        assert.equal(balanceAfterOpenOrder.toString(), 10, "Balance in escrow should be 10");
        const balanceAfterOpenOrderTestUser = await morpherToken.balanceOf(testUserAddress);
        assert.equal(balanceAfterOpenOrderTestUser.toString(), 0, "Balance of User should be 0");

        await morpherOracle.__callback(txReceipt.logs[0].args['_orderId'], 10, 10, 0, 0, Date.now(), 0, { from: oracleCallbackAddress });

        
        const balanceAfterProcessOrder = await morpherToken.balanceOf(escrowAddress);
        assert.equal(balanceAfterProcessOrder.toString(), 0, "Balance in escrow should be 0");
        
        const balanceAfterProcessOrderTestUser = await morpherToken.balanceOf(testUserAddress);
        assert.equal(balanceAfterProcessOrderTestUser.toString(), 0, "Balance of User should be 0");

        const order = await morpherTradeEngine.getOrder(txReceipt.logs[0].args['_orderId']);
        assert.equal(order._closeSharesAmount, '0'); // callback was called successfully
        assert.equal(order._openMPHTokenAmount, '0'); // callback was called successfully
    });

    
    it('Canceling an order will pay back the escrow', async () => {
        
        const morpherOracle = await MorpherOracle.deployed();
        const morpherTradeEngine = await MorpherTradeEngine.deployed();
        const morpherToken = await MorpherToken.deployed();

        // Topup test accounts with MorpherToken.
        await morpherToken.transfer(testUserAddress, 10, { from: deployerAddress }); //10 tokens to address

        // Test successful state variables change and order creation.
        await morpherOracle.overrideGasForCallback(0);
        await morpherOracle.enableCallbackAddress(oracleCallbackAddress);

        const txReceipt = await morpherOracle.createOrder(web3.utils.sha3(MARKET), 0, 10, true, getLeverage(1), 0, 0, 0, 0, { from: testUserAddress }); //10 tokens open order

        const balanceAfterOpenOrder = await morpherToken.balanceOf(escrowAddress);
        assert.equal(balanceAfterOpenOrder.toString(), 10, "Balance in escrow should be 10");
        const balanceAfterOpenOrderTestUser = await morpherToken.balanceOf(testUserAddress);
        assert.equal(balanceAfterOpenOrderTestUser.toString(), 0, "Balance of User should be 0");

        await morpherOracle.initiateCancelOrder(txReceipt.logs[0].args['_orderId'], { from: testUserAddress });
        await morpherOracle.cancelOrder(txReceipt.logs[0].args['_orderId'], { from: oracleCallbackAddress });

        
        const balanceAfterProcessOrder = await morpherToken.balanceOf(escrowAddress);
        assert(balanceAfterProcessOrder.toString(), 10, "Balance in escrow should be 0");
        
        const balanceAfterProcessOrderTestUser = await morpherToken.balanceOf(testUserAddress);
        assert(balanceAfterProcessOrderTestUser.toString(), 10, "Balance of User should be 10");

        const order = await morpherTradeEngine.getOrder(txReceipt.logs[0].args['_orderId']);
        assert.equal(order._closeSharesAmount, '0'); // callback was called successfully
        assert.equal(order._openMPHTokenAmount, '0'); // callback was called successfully
    });

});