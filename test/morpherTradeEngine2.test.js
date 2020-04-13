const MorpherToken = artifacts.require("MorpherToken");
const MorpherTradeEngine = artifacts.require("MorpherTradeEngine");
const MorpherState = artifacts.require("MorpherState");
const MorpherOracle = artifacts.require("MorpherOracle");

let BTC = '0x0bc89e95f9fdaab7e8a11719155f2fd638cb0f665623f3d12aab71d1a125daf9';

function roundToInteger(price){
    return Math.round(price * Math.pow(10, 8));
}

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
    // trade.amount              = 30000000000;
    // trade.amountGivenInShares = false;
    // trade.direction           = long; //true
    //
    // ---- RESULT 1 -----
    //
    // position.value            = 30000000000;
    // position.averagePrice     = 15000000000;
    // position.longShares       = 2;
    // position.shortShares      = 0;
    //
    // userBalance               = 999999999970000000000‬;
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
        let orderId = (await morpherOracle.createOrder(BTC, false, roundToInteger(300), true, 100000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        // console.log(orderId);
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

        assert.equal(positionValue, roundToInteger(300));

        assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(150));
        assert.equal(position._longShares.toNumber(), 2);
        assert.equal(position._shortShares.toNumber(), 0);

        assert.equal(userBalance, '999999999970000000000');
    });
});

contract('MorpherTradeEngine', (accounts) => {
    // ---- TEST 2 -----
    // userBalance               = 100000000000000000000;
    // position.averagePrice     = 0;
    // position.longShares       = 0;
    // position.shortShares      = 0;
    //
    // market.price              = 1000000000;
    // market.spread             = 0;
    //
    // trade.amount              = 2000000000;
    // trade.amountGivenInShares = false;
    // trade.direction           = short; //false
    //
    // ---- RESULT 2 -----
    //
    // position.value            = 2000000000;
    // position.averagePrice     = 1000000000;
    // position.longShares       = 0;
    // position.shortShares      = 2;
    //
    // userBalance               = 99999999998000000000;
    it('test case 2', async () => {
        let account0 = accounts[0]; let account1 = accounts[1];

        let morpherTradeEngine = await MorpherTradeEngine.deployed();
        let morpherToken = await MorpherToken.deployed();
        let morpherState = await MorpherState.deployed();
        let morpherOracle = await MorpherOracle.deployed();

        // Set balance of testing account.
        //(address to, uint256 tokens)
        await morpherToken.transfer(account1, '100000000000000000000');

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, false, roundToInteger(20), false, 100000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

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

        assert.equal(positionValue, roundToInteger(20));

        assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(10));
        assert.equal(position._longShares.toNumber(), 0);
        assert.equal(position._shortShares.toNumber(), 2);

        assert.equal(userBalance, '99999999998000000000');
    });
});

contract('MorpherTradeEngine', (accounts) => {
    // ---- TEST 3 -----
    // userBalance               = 500000000000000000000;
    // position.averagePrice     = 5000000000;
    // position.longShares       = 2;
    // position.shortShares      = 0;
    //
    // market.price              = 8000000000;
    // market.spread             = 0;
    //
    // trade.amount              = 16000000000;
    // trade.amountGivenInShares = false;
    // trade.direction           = short; // false
    //
    // ---- RESULT 3 -----
    //
    // position.value            = 0;
    // position.averagePrice     = 0;
    // position.longShares       = 0;
    // position.shortShares      = 0;
    //
    // userBalance               = 500000000016000000000‬;
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
        await morpherState.setPosition(account1, BTC, 0, 2, 0, roundToInteger(50), 0, 100000000, liquidationPrice, { from: account0 });

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, false, roundToInteger(160), false, 100000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(80), 0, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

        // shortShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._shortShares.toNumber() *
            (await morpherTradeEngine.shortShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), position._liquidationPrice.toNumber(),
                roundToInteger(80), 0, 100000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue, 0);

        assert.equal(position._meanEntryPrice.toNumber(), 0);
        assert.equal(position._longShares.toNumber(), 0);
        assert.equal(position._shortShares.toNumber(), 0);

        assert.equal(userBalance, '500000000016000000000');
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
    // trade.amount              = 15000000000;
    // trade.amountGivenInShares = false;
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
        let orderId = (await morpherOracle.createOrder(BTC, false, roundToInteger(150), true, 100000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(50), 0, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

        // shortShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._shortShares.toNumber() *
            (await morpherTradeEngine.shortShareValue(position._meanEntryPrice.toNumber(),
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
    // userBalance               = 500000000000000000000;
    // position.averagePrice     = 5000000000;
    // position.longShares       = 5;
    // position.shortShares      = 0;
    //
    // market.price              = 10000000000;
    // market.spread             = 0;
    //
    // trade.amount              = 50000000000;
    // trade.amountGivenInShares = false;
    // trade.direction           = long; // true
    //
    // ---- RESULT 5 -----
    //
    // position.value            = 100000000000;
    // position.averagePrice     = 10000000000;
    // position.longShares       = 10;
    // position.shortShares      = 0;
    //
    // userBalance               = 499999999950000000000‬;
    it('test case 5', async () => {
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
        let orderId = (await morpherOracle.createOrder(BTC, false, roundToInteger(500), true, 100000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(100), 0, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

        // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._longShares.toNumber() *
            (await morpherTradeEngine.longShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), position._liquidationPrice.toNumber(),
                roundToInteger(100), 0, 100000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue, roundToInteger(1000));

        assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(100));
        assert.equal(position._longShares.toNumber(), 10);
        assert.equal(position._shortShares.toNumber(), 0);

        assert.equal(userBalance, '499999999950000000000');
    });
});

contract('MorpherTradeEngine', (accounts) => {
    // ---- TEST 6 -----
    // userBalance               = 1000000000000000000000;
    // position.averagePrice     = 10000000000;
    // position.longShares       = 0;
    // position.shortShares      = 50;
    //
    // market.price              = 8000000000;
    // market.spread             = 0;
    //
    // trade.amount              = 400000000000;
    // trade.amountGivenInShares = false;
    // trade.direction           = short; // false
    //
    // ---- RESULT 6 -----
    //
    // position.value            = 1000000000000‬;
    // position.averagePrice     = 8000000000;
    // position.longShares       = 0;
    // position.shortShares      = 125;
    //
    // userBalance               = 999999999600000000000‬;
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
        let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(100), 100000000, false)).toNumber();

        //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
        await morpherState.setPosition(account1, BTC, 0, 0, 50, roundToInteger(100), 0, 100000000, liquidationPrice, { from: account0 });

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, false, roundToInteger(4000), false, 100000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(80), 0, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

        // shortShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._shortShares.toNumber() *
            (await morpherTradeEngine.shortShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), position._liquidationPrice.toNumber(),
                roundToInteger(80), 0, 100000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue, roundToInteger(10000));

        assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(80));
        assert.equal(position._longShares.toNumber(), 0);
        assert.equal(position._shortShares.toNumber(), 125);

        assert.equal(userBalance, '999999999600000000000');
    });
});

contract('MorpherTradeEngine', (accounts) => {
    // ---- TEST 7 -----
    // userBalance               = 500000000000000000000;
    // position.averagePrice     = 5000000000;
    // position.longShares       = 100;
    // position.shortShares      = 0;
    //
    // market.price              = 4000000000;
    // market.spread             = 0;
    //
    // trade.amount              = 600000000000;
    // trade.amountGivenInShares = false;
    // trade.direction           = short; // false
    //
    // ---- RESULT 7 -----
    //
    // position.value            = 200000000000‬;
    // position.averagePrice     = 4000000000;
    // position.longShares       = 0;
    // position.shortShares      = 50;
    //
    // userBalance               = 500000000200000000000‬;
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
        await morpherState.setPosition(account1, BTC, 0, 100, 0, roundToInteger(50), 0, 100000000, liquidationPrice, { from: account0 });

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, false, roundToInteger(6000), false, 100000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

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

        assert.equal(positionValue, roundToInteger(2000));

        assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(40));
        assert.equal(position._longShares.toNumber(), 0);
        assert.equal(position._shortShares.toNumber(), 50);

        assert.equal(userBalance, '500000000200000000000');
    });
});

contract('MorpherTradeEngine', (accounts) => {
    // ---- TEST 8 -----
    // userBalance               = 400000000000000000000;
    // position.averagePrice     = 10000000000;
    // position.longShares       = 0;
    // position.shortShares      = 20;
    //
    // market.price              = 8000000000;
    // market.spread             = 0;
    //
    // trade.amount              = 256000000000‬;
    // trade.amountGivenInShares = false;
    // trade.direction           = long; // true
    //
    // ---- RESULT 8 -----
    //
    // position.value            = 16000000000;
    // position.averagePrice     = 8000000000;
    // position.longShares       = 2;
    // position.shortShares      = 0;
    //
    // userBalance               = 400000000224000000000;
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
        await morpherState.setPosition(account1, BTC, 0, 0, 20, roundToInteger(100), 0, 100000000, liquidationPrice, { from: account0 });

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, false, roundToInteger(2560), true, 100000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

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

        assert.equal(positionValue, roundToInteger(160));

        assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(80));
        assert.equal(position._longShares.toNumber(), 2);
        assert.equal(position._shortShares.toNumber(), 0);

        assert.equal(userBalance, '400000000224000000000');
    });
});

contract('MorpherTradeEngine', (accounts) => {
    // ---- TEST 9 -----
    // userBalance               = 280000000000000000000;
    // position.averagePrice     = 9000000000;
    // position.longShares       = 0;
    // position.shortShares      = 10;
    //
    // market.price              = 20000000000;
    // market.spread             = 0;
    //
    // trade.amount              = 20000000000;
    // trade.amountGivenInShares = false;
    // trade.direction           = long;
    //
    // ---- RESULT 9 -----
    //
    // position.value            = 20000000000;
    // position.averagePrice     = 20000000000;
    // position.longShares       = 1;
    // position.shortShares      = 0;
    //
    // userBalance               = 279999999980000000000;
    it('test case 9', async () => {
        let account0 = accounts[0]; let account1 = accounts[1];

        let morpherTradeEngine = await MorpherTradeEngine.deployed();
        let morpherToken = await MorpherToken.deployed();
        let morpherState = await MorpherState.deployed();
        let morpherOracle = await MorpherOracle.deployed();

        // Set balance of testing account.
        //(address to, uint256 tokens)
        await morpherToken.transfer(account1, '280000000000000000000');

        //(_newMeanEntryPrice, _newMeanEntryLeverage, _long)
        let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(90), 100000000, false)).toNumber();

        //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
        await morpherState.setPosition(account1, BTC, 0, 0, 10, roundToInteger(90), 0, 100000000, liquidationPrice, { from: account0 });

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, false, roundToInteger(200), true, 100000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

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

        assert.equal(positionValue, roundToInteger(200));

        assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(200));
        assert.equal(position._longShares.toNumber(), 1);
        assert.equal(position._shortShares.toNumber(), 0);

        assert.equal(userBalance, '279999999980000000000');
    });
});