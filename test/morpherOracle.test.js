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

contract('MorpherOracle', (accounts) => {

    const [
        deployerAddress,
        testUserAddress,
        oracleCallbackAddress
    ] = accounts;


    it('Deployer can enable and disable oracle callback addresses', async () => {
        const morpherOracle = await MorpherOracle.deployed();

        let isAllowed = await morpherOracle.callBackAddress(oracleCallbackAddress);
        assert.equal(isAllowed, false);

        await morpherOracle.enableCallbackAddress(oracleCallbackAddress);

        isAllowed = await morpherOracle.callBackAddress(oracleCallbackAddress);
        assert.equal(isAllowed, true);
    });

    it('Oracle can be paused', async () => {
        const morpherOracle = await MorpherOracle.deployed();
        const morpherTradeEngine = await MorpherTradeEngine.deployed();
        const morpherToken = await MorpherToken.deployed();
        await morpherToken.transfer(testUserAddress, web3.utils.toWei("1", "ether"), { from: deployerAddress });
        const orderId1 = (await morpherOracle.createOrder(web3.utils.sha3(MARKET), true, 10, true, 100000000, 0, 0, 0, 0, { from: testUserAddress })).logs[0].args._orderId;
        // Asserts
        assert.notEqual(orderId1, null);
        // Test order failure if oracle is paused.
        await morpherOracle.pauseOracle({ from: deployerAddress });
        await truffleAssert.reverts(morpherOracle.createOrder(web3.utils.sha3(MARKET), true, 200, true, 100000000, 0, 0, 0, 0, { from: testUserAddress }), "Oracle paused");
        await truffleAssert.reverts(morpherOracle.__callback(orderId1, 100000000, 100000000, 1000000, 0, 1234, 0, { from: oracleCallbackAddress }), "Oracle paused");

        // Test last created order is orderId1 not orderId2 because Oracle was paused.
        const lastOrderId = await morpherTradeEngine.lastOrderId();
        assert.equal(lastOrderId, orderId1);
        // Test order creation after unpausing oracle.
        await morpherOracle.unpauseOracle({ from: deployerAddress });

        await morpherOracle.__callback(orderId1, 100000000, 100000000, 1000000, 0, 1234, 0, { from: oracleCallbackAddress });

        // orderID1 should have '0' values because we successfully called the callback.
        const order = await morpherTradeEngine.getOrder(orderId1);
        assert.equal(order._tradeAmount, '0'); // callback was called successfully
    });


    it('Orders can be canceled', async () => {
        const morpherOracle = await MorpherOracle.deployed();
        const morpherTradeEngine = await MorpherTradeEngine.deployed();
        const morpherToken = await MorpherToken.deployed();
        await morpherToken.transfer(testUserAddress, web3.utils.toWei("1", "ether"), { from: deployerAddress });

        // Test new order creation and cancellation.
        const orderId = (await morpherOracle.createOrder(web3.utils.sha3(MARKET), true, 200, true, 100000000, 0, 0, 0, 0, { from: testUserAddress })).logs[0].args._orderId;
        assert.notEqual(orderId, null);

        await morpherOracle.cancelOrder(orderId, { from: testUserAddress });

        const order = await morpherTradeEngine.getOrder(orderId);
        assert.equal(order._tradeAmount, '0'); // callback was called successfully
    });

    it('goodUntil fails if in the past', async () => {
        const morpherOracle = await MorpherOracle.deployed();
        const morpherToken = await MorpherToken.deployed();

        // Topup test accounts with MorpherToken.
        await morpherToken.transfer(testUserAddress, web3.utils.toWei("1", "ether"), { from: deployerAddress });
        await morpherToken.transfer(oracleCallbackAddress, web3.utils.toWei("1", "ether"), { from: deployerAddress });

        // Test successful state variables change and order creation.
        await morpherOracle.overrideGasForCallback(0);
        await morpherOracle.enableCallbackAddress(oracleCallbackAddress);


        const goodUntil = Math.round((Date.now() / 1000))-10;
        const txReceipt = await morpherOracle.createOrder(web3.utils.sha3(MARKET), true, 10, true, getLeverage(1), 0, 0, goodUntil, 0, { from: testUserAddress });

        // Asserts
        assert.equal(txReceipt.logs[0].args['_goodUntil'], goodUntil);

        await truffleAssert.fails(
            morpherOracle.__callback(txReceipt.logs[0].args['_orderId'], 100000000, 100000000, 0, 0, Math.round(Date.now() / 1000), 0, { from: oracleCallbackAddress }),
            truffleAssert.ErrorType.REVERT,
            "Error: Order Conditions are not met"
        );
    });

    it('goodUntil works if in the future', async () => {
        const morpherOracle = await MorpherOracle.deployed();
        const morpherTradeEngine = await MorpherTradeEngine.deployed();
        const morpherToken = await MorpherToken.deployed();

        // Topup test accounts with MorpherToken.
        await morpherToken.transfer(testUserAddress, web3.utils.toWei("1", "ether"), { from: deployerAddress });
        await morpherToken.transfer(oracleCallbackAddress, web3.utils.toWei("1", "ether"), { from: deployerAddress });

        // Test successful state variables change and order creation.
        await morpherOracle.overrideGasForCallback(0);
        await morpherOracle.enableCallbackAddress(oracleCallbackAddress);


        const goodUntil = Math.round((Date.now() / 1000)) + 120;
        const txReceipt = await morpherOracle.createOrder(web3.utils.sha3(MARKET), true, 10, true, getLeverage(1), 0, 0, goodUntil, 0, { from: testUserAddress });

        // Asserts
        assert.equal(txReceipt.logs[0].args['_goodUntil'], goodUntil);

        await morpherOracle.__callback(txReceipt.logs[0].args['_orderId'], 100000000, 100000000, 0, 0, Math.round(Date.now() / 1000), 0, { from: oracleCallbackAddress });

        const order = await morpherTradeEngine.getOrder(txReceipt.logs[0].args['_orderId']);
        assert.equal(order._tradeAmount, '0'); // callback was called successfully
    });

    it('goodFrom fails if in the future', async () => {
        const morpherOracle = await MorpherOracle.deployed();
        const morpherToken = await MorpherToken.deployed();

        // Topup test accounts with MorpherToken.
        await morpherToken.transfer(testUserAddress, web3.utils.toWei("1", "ether"), { from: deployerAddress });
        await morpherToken.transfer(oracleCallbackAddress, web3.utils.toWei("1", "ether"), { from: deployerAddress });

        // Test successful state variables change and order creation.
        await morpherOracle.overrideGasForCallback(0);
        await morpherOracle.enableCallbackAddress(oracleCallbackAddress);


        const goodFrom = Math.round((Date.now() / 1000))+10;
        const txReceipt = await morpherOracle.createOrder(web3.utils.sha3(MARKET), true, 10, true, getLeverage(1), 0, 0, 0, goodFrom, { from: testUserAddress });

        // Asserts
        assert.equal(txReceipt.logs[0].args['_goodFrom'], goodFrom);

        await truffleAssert.fails(
            morpherOracle.__callback(txReceipt.logs[0].args['_orderId'], 100000000, 100000000, 0, 0, Math.round(Date.now() / 1000), 0, { from: oracleCallbackAddress }),
            truffleAssert.ErrorType.REVERT,
            "Error: Order Conditions are not met"
        );
    });

    it('goodFrom works if in the past', async () => {
        const morpherOracle = await MorpherOracle.deployed();
        const morpherTradeEngine = await MorpherTradeEngine.deployed();
        const morpherToken = await MorpherToken.deployed();

        // Topup test accounts with MorpherToken.
        await morpherToken.transfer(testUserAddress, web3.utils.toWei("1", "ether"), { from: deployerAddress });
        await morpherToken.transfer(oracleCallbackAddress, web3.utils.toWei("1", "ether"), { from: deployerAddress });

        // Test successful state variables change and order creation.
        await morpherOracle.overrideGasForCallback(0);
        await morpherOracle.enableCallbackAddress(oracleCallbackAddress);


        const goodFrom = Math.round((Date.now() / 1000)) - 10;
        const txReceipt = await morpherOracle.createOrder(web3.utils.sha3(MARKET), true, 10, true, getLeverage(1), 0, 0, 0, goodFrom, { from: testUserAddress });

        // Asserts
        assert.equal(txReceipt.logs[0].args['_goodFrom'], goodFrom);

        await morpherOracle.__callback(txReceipt.logs[0].args['_orderId'], 100000000, 100000000, 0, 0, Math.round(Date.now() / 1000), 0, { from: oracleCallbackAddress });

        const order = await morpherTradeEngine.getOrder(txReceipt.logs[0].args['_orderId']);
        assert.equal(order._tradeAmount, '0'); // callback was called successfully
    });

    
    it('onlyIfPriceAbove fails if smaller', async () => {
        const morpherOracle = await MorpherOracle.deployed();
        const morpherToken = await MorpherToken.deployed();

        // Topup test accounts with MorpherToken.
        await morpherToken.transfer(testUserAddress, web3.utils.toWei("1", "ether"), { from: deployerAddress });
        await morpherToken.transfer(oracleCallbackAddress, web3.utils.toWei("1", "ether"), { from: deployerAddress });

        // Test successful state variables change and order creation.
        await morpherOracle.overrideGasForCallback(0);
        await morpherOracle.enableCallbackAddress(oracleCallbackAddress);


        const priceAbove = 12;
        const txReceipt = await morpherOracle.createOrder(web3.utils.sha3(MARKET), true, 10, true, getLeverage(1), priceAbove, 0, 0, 0, { from: testUserAddress });

        // Asserts
        assert.equal(txReceipt.logs[0].args['_onlyIfPriceAbove'], priceAbove);

        await truffleAssert.fails(
            morpherOracle.__callback(txReceipt.logs[0].args['_orderId'], 11, 11, 0, 0, Math.round(Date.now() / 1000), 0, { from: oracleCallbackAddress }),
            truffleAssert.ErrorType.REVERT,
            "Error: Order Conditions are not met"
        );
    });

    it('onlyIfPriceAbove works if price larger than current price', async () => {
        const morpherOracle = await MorpherOracle.deployed();
        const morpherTradeEngine = await MorpherTradeEngine.deployed();
        const morpherToken = await MorpherToken.deployed();

        // Topup test accounts with MorpherToken.
        await morpherToken.transfer(testUserAddress, web3.utils.toWei("1", "ether"), { from: deployerAddress });
        await morpherToken.transfer(oracleCallbackAddress, web3.utils.toWei("1", "ether"), { from: deployerAddress });

        // Test successful state variables change and order creation.
        await morpherOracle.overrideGasForCallback(0);
        await morpherOracle.enableCallbackAddress(oracleCallbackAddress);


        const priceAbove = 10;
        const txReceipt = await morpherOracle.createOrder(web3.utils.sha3(MARKET), true, 10, true, getLeverage(1), priceAbove, 0, 0, 0, { from: testUserAddress });

        // Asserts
        assert.equal(txReceipt.logs[0].args['_onlyIfPriceAbove'], priceAbove);

        await morpherOracle.__callback(txReceipt.logs[0].args['_orderId'], 11, 11, 0, 0, Math.round(Date.now() / 1000), 0, { from: oracleCallbackAddress });

        const order = await morpherTradeEngine.getOrder(txReceipt.logs[0].args['_orderId']);
        assert.equal(order._tradeAmount, '0'); // callback was called successfully
    });

    
    it('onlyIfPriceBelow fails if smaller', async () => {
        const morpherOracle = await MorpherOracle.deployed();
        const morpherToken = await MorpherToken.deployed();

        // Topup test accounts with MorpherToken.
        await morpherToken.transfer(testUserAddress, web3.utils.toWei("1", "ether"), { from: deployerAddress });
        await morpherToken.transfer(oracleCallbackAddress, web3.utils.toWei("1", "ether"), { from: deployerAddress });

        // Test successful state variables change and order creation.
        await morpherOracle.overrideGasForCallback(0);
        await morpherOracle.enableCallbackAddress(oracleCallbackAddress);


        const priceBelow = 9;
        const txReceipt = await morpherOracle.createOrder(web3.utils.sha3(MARKET), true, 10, true, getLeverage(1), 0, priceBelow, 0, 0, { from: testUserAddress });

        // Asserts
        assert.equal(txReceipt.logs[0].args['_onlyIfPriceBelow'], priceBelow);

        await truffleAssert.fails(
            morpherOracle.__callback(txReceipt.logs[0].args['_orderId'], 11, 11, 0, 0, Math.round(Date.now() / 1000), 0, { from: oracleCallbackAddress }),
            truffleAssert.ErrorType.REVERT,
            "Error: Order Conditions are not met"
        );
    });

    it('onlyIfPriceBelow works if price larger than current price', async () => {
        const morpherOracle = await MorpherOracle.deployed();
        const morpherTradeEngine = await MorpherTradeEngine.deployed();
        const morpherToken = await MorpherToken.deployed();

        // Topup test accounts with MorpherToken.
        await morpherToken.transfer(testUserAddress, web3.utils.toWei("1", "ether"), { from: deployerAddress });
        await morpherToken.transfer(oracleCallbackAddress, web3.utils.toWei("1", "ether"), { from: deployerAddress });

        // Test successful state variables change and order creation.
        await morpherOracle.overrideGasForCallback(0);
        await morpherOracle.enableCallbackAddress(oracleCallbackAddress);


        const priceBelow = 12;
        const txReceipt = await morpherOracle.createOrder(web3.utils.sha3(MARKET), true, 10, true, getLeverage(1), 0, priceBelow, 0, 0, { from: testUserAddress });

        // Asserts
        assert.equal(txReceipt.logs[0].args['_onlyIfPriceBelow'], priceBelow);

        await morpherOracle.__callback(txReceipt.logs[0].args['_orderId'], 11, 11, 0, 0, Math.round(Date.now() / 1000), 0, { from: oracleCallbackAddress });

        const order = await morpherTradeEngine.getOrder(txReceipt.logs[0].args['_orderId']);
        assert.equal(order._tradeAmount, '0'); // callback was called successfully
    });

    it('Oracle can do gasCallbacks correctly', async () => {
        const morpherOracle = await MorpherOracle.deployed();
        const morpherTradeEngine = await MorpherTradeEngine.deployed();
        const morpherToken = await MorpherToken.deployed();

        // Topup test accounts with MorpherToken.
        await morpherToken.transfer(testUserAddress, web3.utils.toWei("1", "ether"), { from: deployerAddress });
        await morpherToken.transfer(oracleCallbackAddress, web3.utils.toWei("1", "ether"), { from: deployerAddress });

        // Test successful state variables change and order creation.
        const setGasForCallbackValue = web3.utils.toWei("0.001", "ether");
        await morpherOracle.overrideGasForCallback(setGasForCallbackValue);
        await morpherOracle.enableCallbackAddress(oracleCallbackAddress);

        const gasForCallback = await morpherOracle.gasForCallback();
        assert.equal(gasForCallback.toString(), setGasForCallbackValue);

        const orderId1 = (await morpherOracle.createOrder(web3.utils.sha3(MARKET), true, 10, true, 100000000, 0, 0, 0, 0, { from: testUserAddress, value: gasForCallback })).logs[0].args._orderId;

        // Asserts
        assert.notEqual(orderId1, null);

        await morpherOracle.__callback(orderId1, 100000000, 100000000, 1000000, 0, 1234, setGasForCallbackValue, { from: oracleCallbackAddress });

        // orderID1 should have '0' values because we successfully called the callback.
        const order = await morpherTradeEngine.getOrder(orderId1);
        assert.equal(order._tradeAmount, '0'); // callback was called successfully
    });

    it('Gas Escrow does not drain Oracle Wallet', async () => {
        const morpherOracle = await MorpherOracle.deployed();
        const morpherToken = await MorpherToken.deployed();

        // Topup test accounts with MorpherToken.
        await morpherToken.transfer(testUserAddress, web3.utils.toWei("1", "ether"), { from: deployerAddress });
        await morpherToken.transfer(oracleCallbackAddress, web3.utils.toWei("1", "ether"), { from: deployerAddress });

        // Test successful state variables change and order creation.
        const setGasForCallbackValue = web3.utils.toWei("0.001", "ether");
        await morpherOracle.overrideGasForCallback(setGasForCallbackValue);
        await morpherOracle.enableCallbackAddress(oracleCallbackAddress);
        await morpherOracle.setCallbackCollectionAddress(oracleCallbackAddress);

        let nextOrderGasEscrowInEther = await morpherOracle.gasForCallback();
        assert.equal(nextOrderGasEscrowInEther.toString(), setGasForCallbackValue);


        // let web3Contract = new web3.eth.Contract(morpherOracle.abi, morpherOracle.address);
        const oracleStartingBalance = await web3.eth.getBalance(oracleCallbackAddress);
        // console.log("Round;Average Gas last Transactions;Gas Estimated;Gas Used;Balance Oracle");

        for (let i = 0; i < 10; i++) {

            let orderId = (await morpherOracle.createOrder(web3.utils.sha3(MARKET), true, 10, true, 100000000, 0, 0, 0, 0, { from: testUserAddress, value: nextOrderGasEscrowInEther })).logs[0].args._orderId;

            // Asserts
            assert.notEqual(orderId, null);

            /**
             * this is not the same as the gas cost for the transaction
             */
            const transactionRequiresGasToFinish = await morpherOracle.__callback.estimateGas(orderId, 100000000, 100000000, 1000000, 0, 1234, nextOrderGasEscrowInEther, { from: oracleCallbackAddress });

            if(historicalGasConsumptionFromOracle.length == 0) {
                historicalGasConsumptionFromOracle.push(transactionRequiresGasToFinish); // we don't have anything yet, we need to start with something
            }

            const gasRequiredOnAverage = Math.round(average(historicalGasConsumptionFromOracle));

            // let gasEstimateWeb3 = await web3Contract.methods.__callback(orderId, 100000000, 1000000, 0, 1234, nextOrderGas).estimateGas({ from: oracleCallbackAddress });
            // console.log(gasEstimateWeb3);


            nextOrderGasEscrowInEther = web3.utils.toWei((gasRequiredOnAverage * gasPriceInGwei).toString(), "gwei");

            let balanceBefore = await web3.eth.getBalance(oracleCallbackAddress);

            /**
             * we provide more gas and get the rest refunded
             * But the user needs to pay our oracle on average the amount back we paid. So our oracle never runs out of money
             */
            let receipt = await morpherOracle.__callback(orderId, 100000000, 100000000, 1000000, 0, 1234, nextOrderGasEscrowInEther, { from: oracleCallbackAddress, gas: web3.utils.toHex(transactionRequiresGasToFinish + 100000), gasPrice: web3.utils.toWei(gasPriceInGwei.toString(), 'gwei') });

            // let balanceAfter = await web3.eth.getBalance(oracleCallbackAddress);
            // console.log(i + ";" + gasRequiredOnAverage + ";" + transactionRequiresGasToFinish + ";" + receipt.receipt.gasUsed + ";" + web3.utils.fromWei(balanceAfter, 'ether'));
            historicalGasConsumptionFromOracle.push(receipt.receipt.gasUsed);
            if(historicalGasConsumptionFromOracle.length > 10) {
                historicalGasConsumptionFromOracle.shift();
            }

            // assert.isTrue(gasEstimateForCallback >= receipt.receipt.gasUsed, "Gas used was more than what we estimated");

        }

        const oracleBalanceAfterOrders = new BN(await web3.eth.getBalance(oracleCallbackAddress));
        assert.isTrue(oracleBalanceAfterOrders.gte(new BN(oracleStartingBalance)), "We're loosing money at the callback, it should not happen normally " + oracleBalanceAfterOrders + " vs " + oracleStartingBalance);
        //console.log(oracleBalanceAfterOrders, oracleStartingBalance);
    });
});