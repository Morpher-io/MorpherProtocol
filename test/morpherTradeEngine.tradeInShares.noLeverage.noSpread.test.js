const MorpherToken = artifacts.require("MorpherToken");
const MorpherTradeEngine = artifacts.require("MorpherTradeEngine");
const MorpherState = artifacts.require("MorpherState");
const MorpherOracle = artifacts.require("MorpherOracle");

const { getLeverage } = require('./helpers/tradeFunctions');

const BN = require('bn.js');

const symbol = "CRYPTO_BTC";
const MARKET = web3.utils.sha3(symbol);


function roundToInteger(price) {
    return Math.round(price * Math.pow(10, 8));
}

function sleep(ms) {
    return new Promise(resolve => {
        setTimeout(resolve, ms);
    });
};

contract('MorpherTradeEngine', async (accounts) => {

    // ---- TEST 1 -----
    // userBalance               = 1000000000000000000000;
    // position.averagePrice     = 0;
    // position.longShares       = 0;
    // position.shortShares      = 0;
    //
    // market.price              = 15000000000;
    // market.spread             = 0;
    //
    // trade.amount              = 3;
    // trade.amountGivenInShares = true;
    // trade.direction           = long; //true
    //
    // ---- RESULT 1 -----
    //
    // position.value            = 45000000000;
    // position.averagePrice     = 15000000000;
    // position.longShares       = 3;
    // position.shortShares      = 0;
    //
    // userBalance               = 999999999955000000000‬;
    it('test case 1: open Long, 3 BTC Shares, each 150MPH', async () => {
        const [oracleCallbackAddress, tradingAccount] = accounts;
        const morpherTradeEngine = await MorpherTradeEngine.deployed();
        const morpherToken = await MorpherToken.deployed();
        const morpherState = await MorpherState.deployed();
        const morpherOracle = await MorpherOracle.deployed();

        /**
         * SETTINGS
         */
        const userStartingMPHBalance = web3.utils.toWei(new BN(1000), "ether");

        const amountGivenInShares = true;
        const shares = 3;
        const tradeDirectionIsLong = true;
        const leverage = 1;
        const pricePerShare = web3.utils.toWei(new BN(150), 'ether');
        const spread = 0;
        const liquidationTimestamp = 0;
        const callbackGasEscrowForNextTrade = 0;

        await morpherState.activateMarket(MARKET);


        const balanceToUser = userStartingMPHBalance.sub(await morpherState.balanceOf(tradingAccount));

        // Set balance of testing account.
        //(address to, uint256 tokens)
        await morpherToken.transfer(tradingAccount, balanceToUser, { from: oracleCallbackAddress });

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(MARKET, amountGivenInShares, shares, tradeDirectionIsLong, getLeverage(leverage), 0, 0, 0, 0, { from: tradingAccount })).logs[0].args._orderId;

        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, pricePerShare, pricePerShare, spread, liquidationTimestamp, 0, callbackGasEscrowForNextTrade, { from: oracleCallbackAddress });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(tradingAccount, MARKET);

        // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = new BN(position._longShares).mul(
            (await morpherTradeEngine.longShareValue(position._meanEntryPrice.toString(),
                position._meanEntryLeverage.toString(), position._liquidationPrice.toString(),
                pricePerShare, spread, getLeverage(leverage), !tradeDirectionIsLong))
        );

        let userBalance = (await morpherState.balanceOf(tradingAccount));

        assert.equal(positionValue.toString(), pricePerShare.mul(new BN(shares)).toString(), "Position value isn't spread*price");

        assert.equal(position._meanEntryPrice.toString(), pricePerShare.toString(), "MeanEntryPrice isn't price per share");
        assert.equal(position._longShares.toNumber(), shares, "longShares doesn't reflect number of bought shares");
        assert.equal(position._shortShares.toNumber(), 0, "There should be no short shares");

        assert.equal(userBalance.toString(), balanceToUser.sub(pricePerShare.mul(new BN(shares))), "new User balance did not get the shares deducted");
    });

});

contract('MorpherTradeEngine', async (accounts) => {
    // ---- TEST 2 -----
    // userBalance               = 1000000000000000000000;
    // position.averagePrice     = 0;
    // position.longShares       = 0;
    // position.shortShares      = 0;
    //
    // market.price              = 1000000000;
    // market.spread             = 0;
    //
    // trade.amount              = 5;
    // trade.amountGivenInShares = true;
    // trade.direction           = short; //false
    //
    // ---- RESULT 2 -----
    //
    // position.value            = 5000000000;
    // position.averagePrice     = 1000000000;
    // position.longShares       = 0;
    // position.shortShares      = 5;
    //
    // userBalance               = 999999999995000000000‬;
    it('test case 2: Open Short, 3 BTC shares, 10MPH each', async () => {
        const [oracleCallbackAddress, tradingAccount] = accounts;
        const morpherTradeEngine = await MorpherTradeEngine.deployed();
        const morpherToken = await MorpherToken.deployed();
        const morpherState = await MorpherState.deployed();
        const morpherOracle = await MorpherOracle.deployed();

        const userStartingMPHBalance = web3.utils.toWei(new BN(1000), "ether");

        const amountGivenInShares = true;
        const shares = 5;
        const tradeDirectionIsLong = true;
        const leverage = 1;
        const pricePerShare = web3.utils.toWei(new BN(10), 'ether');
        const spread = 0;
        const liquidationTimestamp = 0;
        const callbackGasEscrowForNextTrade = 0;

        await morpherState.activateMarket(MARKET);

        // Set balance of testing account.
        const balanceToUser = userStartingMPHBalance.sub(await morpherState.balanceOf(tradingAccount)); //fill up the account to 1000 MPH
        await morpherToken.transfer(tradingAccount, balanceToUser, { from: oracleCallbackAddress });

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(MARKET, amountGivenInShares, shares, tradeDirectionIsLong, getLeverage(leverage), 0, 0, 0, 0, { from: tradingAccount })).logs[0].args._orderId;

        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, pricePerShare, pricePerShare, spread, liquidationTimestamp, 0, callbackGasEscrowForNextTrade, { from: oracleCallbackAddress });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(tradingAccount, MARKET);

        // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = new BN(position._longShares).mul(
            (await morpherTradeEngine.longShareValue(position._meanEntryPrice.toString(),
                position._meanEntryLeverage.toString(), position._liquidationPrice.toString(),
                pricePerShare, spread, getLeverage(leverage), !tradeDirectionIsLong))
        );

        let userBalance = (await morpherState.balanceOf(tradingAccount));

        assert.equal(positionValue.toString(), pricePerShare.mul(new BN(shares)).toString(), "Position value isn't spread*price");

        assert.equal(position._meanEntryPrice.toString(), pricePerShare.toString(), "MeanEntryPrice isn't price per share");
        assert.equal(position._longShares.toNumber(), shares, "longShares doesn't reflect number of bought shares");
        assert.equal(position._shortShares.toNumber(), 0, "There should be no short shares");

        assert.equal(userBalance.toString(), balanceToUser.sub(pricePerShare.mul(new BN(shares))), "new User balance did not get the shares deducted");
    });
});

contract('MorpherTradeEngine', (accounts) => {
    // ---- TEST 3 -----
    // userBalance               = 500000000000000000000;
    // position.averagePrice     = 5000000000;
    // position.longShares       = 5;
    // position.shortShares      = 0;
    //
    // market.price              = 8000000000;
    // market.spread             = 0;
    //
    // trade.amount              = 5;
    // trade.amountGivenInShares = true;
    // trade.direction           = short; // false
    //
    // ---- RESULT 3 -----
    //
    // position.value            = 0;
    // position.averagePrice     = 0;
    // position.longShares       = 0;
    // position.shortShares      = 0;
    //
    // userBalance               = 500000000040000000000‬;
    it('test case 3: close a long position', async () => {

        const [oracleCallbackAddress, tradingAccount] = accounts;
        const morpherTradeEngine = await MorpherTradeEngine.deployed();
        const morpherToken = await MorpherToken.deployed();
        const morpherState = await MorpherState.deployed();
        const morpherOracle = await MorpherOracle.deployed();

        /**
         * SETTINGS
         */
        const userStartingMPHBalance = web3.utils.toWei(new BN(500), "ether");

        const pricePerExistingShare = web3.utils.toWei(new BN(5), 'ether'); //the existing position was opened with 5 MPH
        const existingPositionTradeDirectionIsLong = true;

        const amountGivenInShares = true;
        const shares = 5;
        const tradeDirectionIsLong = false;
        const leverage = 1;
        const pricePerShare = web3.utils.toWei(new BN(8), 'ether'); //we close it with 8 MPH
        const spread = 0;
        const liquidationTimestamp = 0;
        const callbackGasEscrowForNextTrade = 0; //we disable the gas escrow for testing

        await morpherState.activateMarket(MARKET);

        // Set balance of testing account.
        const balanceToUser = userStartingMPHBalance.sub(await morpherState.balanceOf(tradingAccount)); //fill up the account to 1000 MPH
        await morpherToken.transfer(tradingAccount, balanceToUser, { from: oracleCallbackAddress });

        //create a position in the tradeEngine
        //(_newMeanEntryPrice, _newMeanEntryLeverage, _long)
        let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(pricePerExistingShare, getLeverage(leverage), existingPositionTradeDirectionIsLong));
        //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
        await morpherState.setPosition(tradingAccount, MARKET, 0, shares, 0, pricePerExistingShare, 0, getLeverage(leverage), liquidationPrice, { from: oracleCallbackAddress });

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(MARKET, amountGivenInShares, shares, tradeDirectionIsLong, getLeverage(leverage), 0, 0, 0, 0, { from: tradingAccount })).logs[0].args._orderId;

        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, pricePerShare, pricePerShare, spread, liquidationTimestamp, 0, callbackGasEscrowForNextTrade, { from: oracleCallbackAddress });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(tradingAccount, web3.utils.sha3(symbol));

        // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = new BN(position._longShares).mul(
            (await morpherTradeEngine.longShareValue(position._meanEntryPrice.toString(),
                position._meanEntryLeverage.toString(), position._liquidationPrice.toString(),
                pricePerShare, spread, getLeverage(leverage), !tradeDirectionIsLong))
        );

        let userBalance = (await morpherState.balanceOf(tradingAccount));

        assert.equal(positionValue.toString(), 0, "Position value isn't spread*price");

        assert.equal(position._meanEntryPrice.toString(), 0, "MeanEntryPrice isn't price per share");
        assert.equal(position._longShares.toNumber(), 0, "There should be no long shares");
        assert.equal(position._shortShares.toNumber(), 0, "There should be no short shares");

        assert.equal(userBalance.toString(), balanceToUser.add(pricePerShare.mul(new BN(shares))).toString(), "new User balance did not get the shares deducted");

    });
});

contract('MorpherTradeEngine', (accounts) => {
    // ---- TEST 4 -----
    // userBalance               = 400000000000000000000;
    // position.averagePrice     = 4000000000;
    // position.longShares       = 0;
    // position.shortShares      = 5;
    //
    // market.price              = 5000000000;
    // market.spread             = 0;
    //
    // trade.amount              = 5;
    // trade.amountGivenInShares = true;
    // trade.direction           = long; // true
    //
    // ---- RESULT 4 -----
    //
    // position.value            = 0;
    // position.averagePrice     = 0;
    // position.longShares       = 0;
    // position.shortShares      = 0;
    //
    // userBalance               = 400000000015000000000‬;
    it('test case 4: close a short position', async () => {
        
        const [oracleCallbackAddress, tradingAccount] = accounts;
        const morpherTradeEngine = await MorpherTradeEngine.deployed();
        const morpherToken = await MorpherToken.deployed();
        const morpherState = await MorpherState.deployed();
        const morpherOracle = await MorpherOracle.deployed();

        /**
         * SETTINGS
         */
        const userStartingMPHBalance = web3.utils.toWei(new BN(400), "ether");


        const pricePerExistingShare = web3.utils.toWei(new BN(4), 'ether'); //the existing position was opened with 4 MPH
        const existingPositionTradeDirectionIsLong = false; //short

        const amountGivenInShares = true;
        const shares = 5;
        const tradeDirectionIsLong = true;
        const leverage = 1;
        const pricePerShare = web3.utils.toWei(new BN(5), 'ether'); //we close it with 5 MPH
        const spread = 0;
        const liquidationTimestamp = 0;
        const callbackGasEscrowForNextTrade = 0; //we disable the gas escrow for testing

        await morpherState.activateMarket(MARKET);

        // Set balance of testing account.
        const balanceToUser = userStartingMPHBalance.sub(await morpherState.balanceOf(tradingAccount)); //fill up the account to X MPH
        await morpherToken.transfer(tradingAccount, balanceToUser, { from: oracleCallbackAddress });

        //create a position in the tradeEngine
        //(_newMeanEntryPrice, _newMeanEntryLeverage, _long)
        let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(pricePerExistingShare, getLeverage(leverage), existingPositionTradeDirectionIsLong));
        //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
        await morpherState.setPosition(tradingAccount, MARKET, 0, 0, shares, pricePerExistingShare, 0, getLeverage(leverage), liquidationPrice, { from: oracleCallbackAddress });

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(MARKET, amountGivenInShares, shares, tradeDirectionIsLong, getLeverage(leverage), 0, 0, 0, 0, { from: tradingAccount })).logs[0].args._orderId;

        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, pricePerShare, pricePerShare, spread, liquidationTimestamp, 0, callbackGasEscrowForNextTrade, { from: oracleCallbackAddress });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(tradingAccount, web3.utils.sha3(symbol));

        // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = new BN(position._longShares).mul(
            (await morpherTradeEngine.longShareValue(position._meanEntryPrice.toString(),
                position._meanEntryLeverage.toString(), position._liquidationPrice.toString(),
                pricePerShare, spread, getLeverage(leverage), !tradeDirectionIsLong))
        );

        let userBalance = (await morpherState.balanceOf(tradingAccount));

        assert.equal(positionValue.toString(), 0, "Position value isn't spread*price");

        assert.equal(position._meanEntryPrice.toString(), 0, "MeanEntryPrice isn't price per share");
        assert.equal(position._longShares.toNumber(), 0, "There should be no long shares");
        assert.equal(position._shortShares.toNumber(), 0, "There should be no short shares");

        assert.equal(userBalance.toString(), balanceToUser.add(pricePerExistingShare.mul(new BN(shares)).mul(new BN(2)).sub(pricePerShare.mul(new BN(shares)))).toString(), "new User balance did not get the shares deducted");

    });
});

contract('MorpherTradeEngine', (accounts) => {
    // ---- TEST 5 -----
    // userBalance               = 1500000000000000000000;
    // position.averagePrice     = 5000000000;
    // position.longShares       = 10;
    // position.shortShares      = 0;
    //
    // market.price              = 20000000000;
    // market.spread             = 0;
    //
    // trade.amount              = 5;
    // trade.amountGivenInShares = true;
    // trade.direction           = long; // true
    //
    // ---- RESULT 5 -----
    //
    // position.value            = 300000000000;
    // position.averagePrice     = 20000000000;
    // position.longShares       = 15;
    // position.shortShares      = 0;
    //
    // userBalance               = 1499999999900000000000;
    it('test case 5: extend an existing long position', async () => {
        let account0 = accounts[0]; let account1 = accounts[1];

        let morpherTradeEngine = await MorpherTradeEngine.deployed();
        let morpherToken = await MorpherToken.deployed();
        let morpherState = await MorpherState.deployed();
        let morpherOracle = await MorpherOracle.deployed();

        // Set balance of testing account.
        //(address to, uint256 tokens)
        await morpherToken.transfer(account1, '1500000000000000000000');

        //(_newMeanEntryPrice, _newMeanEntryLeverage, _long)
        let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(50), 100000000, true)).toNumber();

        //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
        await morpherState.setPosition(account1, MARKET, 0, 10, 0, roundToInteger(50), 0, 100000000, liquidationPrice, { from: account0 });

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(MARKET, true, 5, true, 100000000, 0, 0, 0, 0, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(200), 0, 0, 0, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, MARKET);

        // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._longShares.toNumber() *
            (await morpherTradeEngine.longShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), position._liquidationPrice.toNumber(),
                roundToInteger(200), 0, 100000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue, roundToInteger(3000));

        assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(200));
        assert.equal(position._longShares.toNumber(), 15);
        assert.equal(position._shortShares.toNumber(), 0);


        assert.equal(userBalance.toString(), new BN('1499999999900000000000').toString());
    });
});

contract('MorpherTradeEngine', (accounts) => {
    // ---- TEST 6 -----
    // userBalance               = 1000000000000000000000;
    // position.averagePrice     = 10000000000;
    // position.longShares       = 0;
    // position.shortShares      = 500000000;
    //
    // market.price              = 8000000000;
    // market.spread             = 0;
    //
    // trade.amount              = 500000000;
    // trade.amountGivenInShares = true;
    // trade.direction           = short; // false
    //
    // ---- RESULT 6 -----
    //
    // position.value            = 10000000000000000000‬;
    // position.averagePrice     = 8000000000;
    // position.longShares       = 0;
    // position.shortShares      = 1250000000‬;
    //
    // userBalance               = 996000000000000000000;
    it('test case 6: extend an existing short position (short 5) and short (+5) = short 10, deduct from balance', async () => {
        let account0 = accounts[0]; let account1 = accounts[1];

        let morpherTradeEngine = await MorpherTradeEngine.deployed();
        let morpherToken = await MorpherToken.deployed();
        let morpherState = await MorpherState.deployed();
        let morpherOracle = await MorpherOracle.deployed();

        // Set balance of testing account.
        //(address to, uint256 tokens)
        await morpherToken.transfer(account1, '1000000000000000000000');

        //(_newMeanEntryPrice, _newMeanEntryLeverage, _long)
        let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(5), 100000000, true)).toNumber();

        //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
        await morpherState.setPosition(account1, MARKET, 0, 0, roundToInteger(5), 10000000000, 0, 100000000, liquidationPrice, { from: account0 });

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(MARKET, true, roundToInteger(5), false, 100000000, 0, 0, 0, 0, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(80), 0, 0, 0, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, MARKET);

        // shortShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._shortShares.toNumber() *
            (await morpherTradeEngine.shortShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), position._liquidationPrice.toNumber(),
                roundToInteger(80), 0, 100000000, true)).toString();

        let userBalance = (await morpherState.balanceOf(account1));

        assert.equal(positionValue, 10000000000000000000);

        assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(80));
        assert.equal(position._longShares.toNumber(), 0);
        assert.equal(position._shortShares.toNumber(), roundToInteger(12.5));

        assert.equal(userBalance.toString(), new BN('996000000000000000000').toString());
    });
});

contract('MorpherTradeEngine', (accounts) => {
    // ---- TEST 7 -----
    // userBalance               = 500000000000000000000;
    // position.averagePrice     = 5000000000;
    // position.longShares       = 10;
    // position.shortShares      = 0;
    //
    // market.price              = 4000000000;
    // market.spread             = 0;
    //
    // trade.amount              = 15;
    // trade.amountGivenInShares = true;
    // trade.direction           = short; // false
    //
    // ---- RESULT 7 -----
    //
    // position.value            = 20000000000;
    // position.averagePrice     = 4000000000;
    // position.longShares       = 0;
    // position.shortShares      = 5;
    //
    // userBalance               = 500000000020000000000‬;
    it('test case 7: rollover short (10 shares) to long (+15 shares) = long 10 shares. Payout the Rest', async () => {
        let account0 = accounts[0]; let account1 = accounts[1];

        let morpherTradeEngine = await MorpherTradeEngine.deployed();
        let morpherToken = await MorpherToken.deployed();
        let morpherState = await MorpherState.deployed();
        let morpherOracle = await MorpherOracle.deployed();

        // Set balance of testing account.
        //(address to, uint256 tokens)
        await morpherToken.transfer(account1, '500000000000000000000');

        //(_newMeanEntryPrice, _newMeanEntryLeverage, _long)
        let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(50), 100000000, true)).toNumber();

        //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
        await morpherState.setPosition(account1, MARKET, 0, 10, 0, roundToInteger(50), 0, 100000000, liquidationPrice, { from: account0 });

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(MARKET, true, 15, false, 100000000, 0, 0, 0, 0, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(40), 0, 0, 0, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, MARKET);

        // shortShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._shortShares.toNumber() *
            (await morpherTradeEngine.shortShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), position._liquidationPrice.toNumber(),
                roundToInteger(40), 0, 100000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue, roundToInteger(200));

        assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(40));
        assert.equal(position._longShares.toNumber(), 0);
        assert.equal(position._shortShares.toNumber(), 5);

        assert.equal(userBalance, '500000000020000000000');
    });
});

contract('MorpherTradeEngine', (accounts) => {
    // ---- TEST 8 -----
    // userBalance               = 400000000000000000000;
    // position.averagePrice     = 10000000000;
    // position.longShares       = 0;
    // position.shortShares      = 2;
    //
    // market.price              = 8000000000;
    // market.spread             = 0;
    //
    // trade.amount              = 3;
    // trade.amountGivenInShares = true;
    // trade.direction           = long; // true
    //
    // ---- RESULT 8 -----
    //
    // position.value            = 8000000000;
    // position.averagePrice     = 8000000000;
    // position.longShares       = 1;
    // position.shortShares      = 0;
    //
    // userBalance               = 400000000016000000000;
    it('test case 8: rollover short (2) and long (+3) = long 1 and payout the rest', async () => {
        let account0 = accounts[0]; let account1 = accounts[1];

        let morpherTradeEngine = await MorpherTradeEngine.deployed();
        let morpherToken = await MorpherToken.deployed();
        let morpherState = await MorpherState.deployed();
        let morpherOracle = await MorpherOracle.deployed();

        // Set balance of testing account.
        //(address to, uint256 tokens)
        await morpherToken.transfer(account1, '400000000000000000000');

        //(_newMeanEntryPrice, _newMeanEntryLeverage, _long)
        let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(100), 100000000, false)).toNumber();

        //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
        await morpherState.setPosition(account1, MARKET, 0, 0, 2, roundToInteger(100), 0, 100000000, liquidationPrice, { from: account0 });

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(MARKET, true, 3, true, 100000000, 0, 0, 0, 0, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(80), 0, 0, 0, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, MARKET);

        // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._longShares.toNumber() *
            (await morpherTradeEngine.longShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), position._liquidationPrice.toNumber(),
                roundToInteger(80), 0, 100000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue, roundToInteger(80));

        assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(80));
        assert.equal(position._longShares.toNumber(), 1);
        assert.equal(position._shortShares.toNumber(), 0);

        assert.equal(userBalance, '400000000016000000000');
    });
});

contract('MorpherTradeEngine', (accounts) => {
    // ---- TEST 9 -----
    // userBalance               = 80000000000000000000;
    // position.averagePrice     = 9000000000;
    // position.longShares       = 0;
    // position.shortShares      = 1;
    //
    // market.price              = 20000000000;
    // market.spread             = 0;
    //
    // trade.amount              = 1;
    // trade.amountGivenInShares = true;
    // trade.direction           = long;
    //
    // ---- RESULT 9 -----
    //
    // position.value            = 0;
    // position.averagePrice     = 0;
    // position.longShares       = 0;
    // position.shortShares      = 0;
    //
    // userBalance               = 80000000000000000000;
    it('test case 9: close short, liquidation because of market price movement', async () => {
        let account0 = accounts[0]; let account1 = accounts[1];

        let morpherTradeEngine = await MorpherTradeEngine.deployed();
        let morpherToken = await MorpherToken.deployed();
        let morpherState = await MorpherState.deployed();
        let morpherOracle = await MorpherOracle.deployed();

        // Set balance of testing account.
        //(address to, uint256 tokens)
        await morpherToken.transfer(account1, '80000000000000000000');

        //(_newMeanEntryPrice, _newMeanEntryLeverage, _long)
        let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(90), 100000000, false)).toNumber();

        //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
        await morpherState.setPosition(account1, MARKET, 0, 0, 1, roundToInteger(90), 0, 100000000, liquidationPrice, { from: account0 });

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(MARKET, true, 1, true, 100000000, 0, 0, 0, 0, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        //(_orderId, _price, originalPrice, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(200), 0, 0, 0, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, MARKET);

        // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._longShares.toNumber() *
            (await morpherTradeEngine.longShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), position._liquidationPrice.toNumber(),
                roundToInteger(200), 0, 100000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue, 0);

        assert.equal(position._meanEntryPrice.toNumber(), 0);
        assert.equal(position._longShares.toNumber(), 0);
        assert.equal(position._shortShares.toNumber(), 0);

        assert.equal(userBalance, '80000000000000000000');
    });
});

contract('MorpherTradeEngine', (accounts) => {
    //---- TEST 10 -----
    // userBalance               = 1000000000000000000000;
    // position.averagePrice     = 30000000000;
    // position.longShares       = 1;
    // position.shortShares      = 0;

    // market.price              = 40000000000;
    // market.spread             = 0;

    // trade.amount              = 1;
    // trade.amountGivenInShares = true;
    // trade.direction           = short;

    // ---- RESULT 10 -----

    // position.value            = 0;
    // position.averagePrice     = 0;
    // position.longShares       = 0;
    // position.shortShares      = 0;

    // userBalance               = 1000000000040000000000;
    it('test case 10: closing a long position', async () => {
        let account0 = accounts[0]; let account1 = accounts[1];

        let morpherTradeEngine = await MorpherTradeEngine.deployed();
        let morpherToken = await MorpherToken.deployed();
        let morpherState = await MorpherState.deployed();
        let morpherOracle = await MorpherOracle.deployed();

        // Set balance of testing account.
        //(address to, uint256 tokens)
        await morpherToken.transfer(account1, '1000000000000000000000');

        //(_newMeanEntryPrice, _newMeanEntryLeverage, _long)
        let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(300), 100000000, true)).toNumber();

        //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
        await morpherState.setPosition(account1, MARKET, 0, 1, 0, roundToInteger(300), 0, 100000000, liquidationPrice, { from: account0 });

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(MARKET, true, 1, false, 100000000, 0, 0, 0, 0,{ from: account1, value: 301000000000000 })).logs[0].args._orderId;

        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(400), 0, 0, 0, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, MARKET);

        // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._longShares.toNumber() *
            (await morpherTradeEngine.longShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), position._liquidationPrice.toNumber(),
                roundToInteger(400), 0, 100000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue, 0);

        assert.equal(position._meanEntryPrice.toNumber(), 0);
        assert.equal(position._longShares.toNumber(), 0);
        assert.equal(position._shortShares.toNumber(), 0);

        assert.equal(userBalance, '1000000000040000000000');
    });
});
