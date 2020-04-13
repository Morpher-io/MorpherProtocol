const MorpherToken = artifacts.require("MorpherToken");
const MorpherTradeEngine = artifacts.require("MorpherTradeEngine");
const MorpherState = artifacts.require("MorpherState");
const MorpherOracle = artifacts.require("MorpherOracle");

let BTC = '0x0bc89e95f9fdaab7e8a11719155f2fd638cb0f665623f3d12aab71d1a125daf9';

const BigNumber = require('bignumber.js');

function roundToInteger(price){
    return Math.round(price * Math.pow(10, 8));
}

function sleep(ms){
    return new Promise(resolve => {
        setTimeout(resolve, ms);
    });
};

contract('MorpherTradeEngine', (accounts) => {
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
    it('test case 1', async () => {
        let account0 = accounts[0]; let account1 = accounts[1];

        let morpherTradeEngine = await MorpherTradeEngine.deployed();
        let morpherToken = await MorpherToken.deployed();
        let morpherState = await MorpherState.deployed();
        let morpherOracle = await MorpherOracle.deployed();
        
        // Set balance of testing account.
        //(address to, uint256 tokens)
        await morpherToken.transfer(account1, '1000000000000000000000');

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, true, 3, true, 100000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(150), 0, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

        // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._longShares.toNumber() *
        (await morpherTradeEngine.longShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), position._liquidationPrice.toNumber(),
            roundToInteger(150), 0, 100000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue, roundToInteger(450));

        assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(150));
        assert.equal(position._longShares.toNumber(), 3);
        assert.equal(position._shortShares.toNumber(), 0);

        assert.equal(userBalance,'999999999955000000000');
    });
});

contract('MorpherTradeEngine', (accounts) => {
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
    it('test case 2', async () => {
        let account0 = accounts[0]; let account1 = accounts[1];

        let morpherTradeEngine = await MorpherTradeEngine.deployed();
        let morpherToken = await MorpherToken.deployed();
        let morpherState = await MorpherState.deployed();
        let morpherOracle = await MorpherOracle.deployed();

        // Set balance of testing account.
        //(address to, uint256 tokens)
        await morpherToken.transfer(account1, '1000000000000000000000');

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, true, 5, false, 100000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(10), 0, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

        // shortShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._shortShares.toNumber() *
            (await morpherTradeEngine.shortShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), position._liquidationPrice.toNumber(),
                roundToInteger(10), 0, 100000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue, roundToInteger(50));

        assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(10));
        assert.equal(position._longShares.toNumber(), 0);
        assert.equal(position._shortShares.toNumber(), 5);

        assert.equal(userBalance,'999999999995000000000');
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
    it('test case 3', async () => {
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
        await morpherState.setPosition(account1, BTC, 0, 5, 0, roundToInteger(50), 0, 100000000, liquidationPrice, { from: account0 });

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, true, 5, false, 100000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(80), 0, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

        // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._longShares.toNumber() *
            (await morpherTradeEngine.longShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), position._liquidationPrice.toNumber(),
                roundToInteger(80), 0, 100000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue, 0);

        assert.equal(position._meanEntryPrice.toNumber(), 0);
        assert.equal(position._longShares.toNumber(), 0);
        assert.equal(position._shortShares.toNumber(), 0);

        assert.equal(userBalance,'500000000040000000000');
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
    it('test case 4', async () => {
        let account0 = accounts[0]; let account1 = accounts[1];

        let morpherTradeEngine = await MorpherTradeEngine.deployed();
        let morpherToken = await MorpherToken.deployed();
        let morpherState = await MorpherState.deployed();
        let morpherOracle = await MorpherOracle.deployed();

        // Set balance of testing account.
        //(address to, uint256 tokens)
        await morpherToken.transfer(account1, '400000000000000000000');

        //(_newMeanEntryPrice, _newMeanEntryLeverage, _long)
        let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(40), 100000000, false)).toNumber();

        //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
        await morpherState.setPosition(account1, BTC, 0, 0, 5, roundToInteger(40), 0, 100000000, liquidationPrice, { from: account0 });

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, true, 5, true, 100000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(50), 0, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

        // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._longShares.toNumber() *
            (await morpherTradeEngine.longShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), position._liquidationPrice.toNumber(),
                roundToInteger(50), 0, 100000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue, 0);

        assert.equal(position._meanEntryPrice.toNumber(), 0);
        assert.equal(position._longShares.toNumber(), 0);
        assert.equal(position._shortShares.toNumber(), 0);

        assert.equal(userBalance, '400000000015000000000');
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
    it('test case 5', async () => {
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
        await morpherState.setPosition(account1, BTC, 0, 10, 0, roundToInteger(50), 0, 100000000, liquidationPrice, { from: account0 });

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, true, 5, true, 100000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(200), 0, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

        // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._longShares.toNumber() *
            (await morpherTradeEngine.longShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), position._liquidationPrice.toNumber(),
                roundToInteger(200), 0, 100000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        userBalance = new BigNumber(userBalance).toFixed();

        assert.equal(positionValue, roundToInteger(3000));

        assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(200));
        assert.equal(position._longShares.toNumber(), 15);
        assert.equal(position._shortShares.toNumber(), 0);


        assert.equal(userBalance, new BigNumber('1499999999900000000000').toFixed());
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
    it('test case 6', async () => {
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
        await morpherState.setPosition(account1, BTC, 0, 0, roundToInteger(5), 10000000000, 0, 100000000, liquidationPrice, { from: account0 });

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, true, roundToInteger(5), false, 100000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(80), 0, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

        // shortShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._shortShares.toNumber() *
            (await morpherTradeEngine.shortShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), position._liquidationPrice.toNumber(),
                roundToInteger(80), 0, 100000000, true)).toString();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        userBalance = new BigNumber(userBalance).toFixed();


        assert.equal(positionValue, 10000000000000000000);

        assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(80));
        assert.equal(position._longShares.toNumber(), 0);
        assert.equal(position._shortShares.toNumber(), roundToInteger(12.5));

        assert.equal(userBalance, new BigNumber('996000000000000000000').toFixed());
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
    it('test case 7', async () => {
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
        await morpherState.setPosition(account1, BTC, 0, 10, 0, roundToInteger(50), 0, 100000000, liquidationPrice, { from: account0 });

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, true, 15, false, 100000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(40), 0, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

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
    it('test case 8', async () => {
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
        await morpherState.setPosition(account1, BTC, 0, 0, 2, roundToInteger(100), 0, 100000000, liquidationPrice, { from: account0 });

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, true, 3, true, 100000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(80), 0, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

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
    it('test case 9', async () => {
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
        await morpherState.setPosition(account1, BTC, 0, 0, 1, roundToInteger(90), 0, 100000000, liquidationPrice, { from: account0 });

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, true, 1, true, 100000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(200), 0, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

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
    it('test case 10', async () => {
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
        await morpherState.setPosition(account1, BTC, 0, 1, 0, roundToInteger(300), 0, 100000000, liquidationPrice, { from: account0 });

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, true, 1, false, 100000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(400), 0, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

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
