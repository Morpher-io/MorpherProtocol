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
    // position.averageSpread    = 0;
    // position.averageLeverage  = 100000000;
    //
    // market.price              = 15000000000;
    // market.spread             = 100000;
    //
    // trade.amount              = 3;
    // trade.amountGivenInShares = true;
    // trade.orderLeverage       = 200000000;
    // trade.direction           = long; //true
    //
    // ---- RESULT 1 -----
    //
    // position.value            = 44999400000‬;
    // position.averagePrice     = 15000000000;
    // position.longShares       = 3;
    // position.shortShares      = 0;
    // position.averageSpread    = 100000;
    // position.averageLeverage  = 200000000;
    //
    // userBalance               = 999999999954999400000;
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
        let orderId = (await morpherOracle.createOrder(BTC, true, 3, true, 200000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        // console.log(orderId);
        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(150), 100000, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

        // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._longShares.toNumber() *
            (await morpherTradeEngine.longShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), position._liquidationPrice.toNumber(),
                roundToInteger(150), 100000, 200000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue, 44999400000);

        assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(150));
        assert.equal(position._longShares.toNumber(), 3);
        assert.equal(position._shortShares.toNumber(), 0);
        assert.equal(position._meanEntrySpread.toNumber(), 100000);
        assert.equal(position._meanEntryLeverage.toNumber(), 200000000);

        assert.equal(userBalance, '999999999954999400000');
    });
});

contract('MorpherTradeEngine', (accounts) => {
    // ---- TEST 2 -----
    // userBalance               = 100000000000000000000;
    // position.averagePrice     = 0;
    // position.longShares       = 0;
    // position.shortShares      = 0;
    // position.averageSpread    = 0;
    // position.averageLeverage  = 100000000;
    //
    // market.price              = 1000000000;
    // market.spread             = 200000;
    //
    // trade.amount              = 5;
    // trade.amountGivenInShares = true;
    // trade.orderLeverage       = 500000000;
    // trade.direction           = short; //false
    //
    // ---- RESULT 2 -----
    //
    // position.value            = 999000000‬;
    // position.averagePrice     = 1000000000;
    // position.longShares       = 0;
    // position.shortShares      = 5;
    // position.averageSpread    = 200000;
    // position.averageLeverage  = 500000000;
    //
    // userBalance               = 99999999994995000000‬;
    it('test case 2', async () => {
        let account0 = accounts[0]; let account1 = accounts[1];

        let morpherTradeEngine = await MorpherTradeEngine.deployed();
        let morpherToken = await MorpherToken.deployed();
        let morpherState = await MorpherState.deployed();
        let morpherOracle = await MorpherOracle.deployed();

        // Set balance of testing account.
        //(address to, uint256 tokens)
        await morpherToken.transfer(account1, '100000000000000000000');

        //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
        await morpherState.setPosition(account1, BTC, 0, 0, 0, 0, 0, 100000000, 0);

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, true, 5, false, 500000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        // console.log(orderId);
        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(10), 200000, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

        // shortShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._shortShares.toNumber() *
            (await morpherTradeEngine.shortShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), position._liquidationPrice.toNumber(),
                roundToInteger(10), 200000, 500000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue, 4995000000);

        assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(10));
        assert.equal(position._longShares.toNumber(), 0);
        assert.equal(position._shortShares.toNumber(), 5);
        assert.equal(position._meanEntrySpread.toNumber(), 200000);
        assert.equal(position._meanEntryLeverage.toNumber(), 500000000);

        assert.equal(userBalance, '99999999994995000000');
    });
});

contract('MorpherTradeEngine', (accounts) => {
    // ---- TEST 3 -----
    // userBalance               = 500000000000000000000;
    // position.averagePrice     = 5000000000;
    // position.longShares       = 5;
    // position.shortShares      = 0;
    // position.averageSpread    = 0;
    // position.averageLeverage  = 200000000;
    //
    // market.price              = 8000000000;
    // market.spread             = 100000;
    //
    // trade.amount              = 5;
    // trade.amountGivenInShares = true;
    // trade.orderLeverage       = 500000000;
    // trade.direction           = short; //false
    //
    // ---- RESULT 3 -----
    //
    // position.value            = 0;
    // position.averagePrice     = 0;
    // position.longShares       = 0;
    // position.shortShares      = 0;
    // position.averageSpread    = 0;
    // position.averageLeverage  = 100000000;
    //
    // userBalance               = ‭500000000054999000000‬;
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
        let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(50), 200000000, true)).toNumber();

        //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
        await morpherState.setPosition(account1, BTC, 0, 5, 0, roundToInteger(50), 0, 200000000, liquidationPrice);

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, true, 5, false, 500000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        // console.log(orderId);
        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(80), 100000, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

        // shortShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._shortShares.toNumber() *
            (await morpherTradeEngine.shortShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), position._liquidationPrice.toNumber(),
                roundToInteger(80), 100000, 500000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue, 0);

        assert.equal(position._meanEntryPrice.toNumber(), 0);
        assert.equal(position._longShares.toNumber(), 0);
        assert.equal(position._shortShares.toNumber(), 0);
        assert.equal(position._meanEntrySpread.toNumber(), 0);
        assert.equal(position._meanEntryLeverage.toNumber(), 100000000);

        assert.equal(userBalance, '500000000054999000000');
    });
});

contract('MorpherTradeEngine', (accounts) => {
    // ---- TEST 4 -----
    // userBalance               = 400000000000000000000;
    // position.averagePrice     = 4000000000;
    // position.longShares       = 0;
    // position.shortShares      = 5;
    // position.averageSpread    = 0;
    // position.averageLeverage  = 200000000;
    //
    // market.price              = 5000000000;
    // market.spread             = 200000;
    //
    // trade.amount              = 5;
    // trade.amountGivenInShares = true;
    // trade.orderLeverage       = 500000000;
    // trade.direction           = long; //true
    //
    // ---- RESULT 4 -----
    //
    // position.value            = 0;
    // position.averagePrice     = 0;
    // position.longShares       = 0;
    // position.shortShares      = 0;
    // position.averageSpread    = 0;
    // position.averageLeverage  = 100000000;
    //
    // userBalance               = 400000000009998000000‬;
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
        let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(40), 200000000, false)).toNumber();

        //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
        await morpherState.setPosition(account1, BTC, 0, 0, 5, roundToInteger(40), 0, 200000000, liquidationPrice);

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, true, 5, true, 500000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        // console.log(orderId);
        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(50), 200000, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

        // shortShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._shortShares.toNumber() *
            (await morpherTradeEngine.shortShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), position._liquidationPrice.toNumber(),
                roundToInteger(50), 200000, 500000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue, 0);

        assert.equal(position._meanEntryPrice.toNumber(), 0);
        assert.equal(position._longShares.toNumber(), 0);
        assert.equal(position._shortShares.toNumber(), 0);
        assert.equal(position._meanEntrySpread.toNumber(), 0);
        assert.equal(position._meanEntryLeverage.toNumber(), 100000000);

        assert.equal(userBalance, '400000000009998000000');
    });
});

contract('MorpherTradeEngine', (accounts) => {
    // ---- TEST 5 -----
    // userBalance               = 1500000000000000000000;
    // position.averagePrice     = 5000000000;
    // position.longShares       = 10;
    // position.shortShares      = 0;
    // position.averageSpread    = 0;
    // position.averageLeverage  = 100000000;
    //
    // market.price              = 20000000000;
    // market.spread             = 900000;
    //
    // trade.amount              = 5;
    // trade.amountGivenInShares = true;
    // trade.orderLeverage       = 400000000;
    // trade.direction           = long; //true
    //
    // ---- RESULT 5 -----
    //
    // position.value            = ‭299973000000‬;
    // position.averagePrice     = 20000000000;
    // position.longShares       = 15;
    // position.shortShares      = 0;
    // position.averageSpread    = 300000‬;
    // position.averageLeverage  = 200000000‬;
    //
    // userBalance               = 1499999999899982000000;
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
        await morpherState.setPosition(account1, BTC, 0, 10, 0, roundToInteger(50), 0, 100000000, liquidationPrice);

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, true, 5, true, 400000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(200), 900000, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

        // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._longShares.toNumber() *
            (await morpherTradeEngine.longShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), position._liquidationPrice.toNumber(),
                roundToInteger(200), 900000, 400000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue, 299973000000);

        assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(200));
        assert.equal(position._longShares.toNumber(), 15);
        assert.equal(position._shortShares.toNumber(), 0);
        assert.equal(position._meanEntrySpread.toNumber(), 300000);
        assert.equal(position._meanEntryLeverage.toNumber(), 200000000);

        assert.equal(userBalance, '1499999999899982000000');
    });
});

contract('MorpherTradeEngine', (accounts) => {
    // ---- TEST 6 -----
    // userBalance               = 1000000000000000000000;
    // position.averagePrice     = 10000000000;
    // position.longShares       = 0;
    // position.shortShares      = 50;
    // position.averageSpread    = 100000;
    // position.averageLeverage  = 100000000;
    //
    // market.price              = 8000000000;
    // market.spread             = 100000;
    //
    // trade.amount              = 50;
    // trade.amountGivenInShares = true;
    // trade.orderLeverage       = 300000000;
    // trade.direction           = short; //false
    //
    // ---- RESULT 6 -----
    //
    // position.value            = 999975000000;
    // position.averagePrice     = 8000000000;
    // position.longShares       = 0;
    // position.shortShares      = 125;
    // position.averageSpread    = 80000;
    // position.averageLeverage  = 200000000;
    //
    // userBalance               = 999999999599985000000‬;
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
        await morpherState.setPosition(account1, BTC, 0, 0, 50, roundToInteger(100), 100000, 100000000, liquidationPrice);

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, true, 50, false, 300000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        // console.log(orderId);
        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(80), 100000, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

        // shortShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._shortShares.toNumber() *
            (await morpherTradeEngine.shortShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), position._liquidationPrice.toNumber(),
                roundToInteger(80), 100000, 300000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue,999977500000);

        assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(80));
        assert.equal(position._longShares.toNumber(), 0);
        assert.equal(position._shortShares.toNumber(), 125);
        assert.equal(position._meanEntrySpread.toNumber(), 80000);
        assert.equal(position._meanEntryLeverage.toNumber(), 180000000);

        assert.equal(userBalance,'999999999599985000000');
    });
});

contract('MorpherTradeEngine', (accounts) => {
    // ---- TEST 7 -----
    // userBalance               = 500000000000000000000;
    // position.averagePrice     = 5000000000;
    // position.longShares       = 100;
    // position.shortShares      = 0;
    // position.averageSpread    = 100000;
    // position.averageLeverage  = 200000000;
    //
    // market.price              = 4000000000;
    // market.spread             = 200000;
    //
    // trade.amount              = 150;
    // trade.amountGivenInShares = true;
    // trade.orderLeverage       = 300000000;
    // trade.direction           = short; //false
    //
    // ---- RESULT 7 -----
    //
    // position.value            = 199970000000‬;
    // position.averagePrice     = 4000000000;
    // position.longShares       = 0;
    // position.shortShares      = 50;
    // position.averageSpread    = 200000‬;
    // position.averageLeverage  = 300000000;
    //
    // userBalance               = 500000000099930000000‬‬;
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
        let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(50), 200000000, true)).toNumber();

        //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
        await morpherState.setPosition(account1, BTC, 0, 100, 0, roundToInteger(50), 200000, 200000000, liquidationPrice);

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, true, 150, false, 300000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        // console.log(orderId);
        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(40), 200000, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

        // shortShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._shortShares.toNumber() *
            (await morpherTradeEngine.shortShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), position._liquidationPrice.toNumber(),
                roundToInteger(40), 200000, 300000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue, 199970000000);

        assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(40));
        assert.equal(position._longShares.toNumber(), 0);
        assert.equal(position._shortShares.toNumber(), 50);
        assert.equal(position._meanEntrySpread.toNumber(), 200000);
        assert.equal(position._meanEntryLeverage.toNumber(), 300000000);

        assert.equal(userBalance, '500000000099930000000');
    });
});

contract('MorpherTradeEngine', (accounts) => {
    // ---- TEST 8 -----
    // userBalance               = 400000000000000000000;
    // position.averagePrice     = 10000000000;
    // position.longShares       = 0;
    // position.shortShares      = 20;
    // position.averageSpread    = 300000;
    // position.averageLeverage  = 200000000;
    //279,988,000,000
    // market.price              = 8000000000;
    // market.spread             = 300000;
    //
    // trade.amount              = 30;
    // trade.amountGivenInShares = true;
    // trade.orderLeverage       = 500000000;
    // trade.direction           = long; //true
    //
    // ---- RESULT 8 -----
    //
    // position.value            = 7998500000‬0;
    // position.averagePrice     = 8000000000;
    // position.longShares       = 10;
    // position.shortShares      = 0;
    // position.averageSpread    = 300000;
    // position.averageLeverage  = 500000000;
    //
    // userBalance               = 400000000199973000000;
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
        let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(100), 200000000, false)).toNumber();

        //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
        await morpherState.setPosition(account1, BTC, 0, 0, 20, roundToInteger(100), 300000, 200000000, liquidationPrice);

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, true, 30, true, 500000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        // console.log(orderId);
        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(80), 300000, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

        // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._longShares.toNumber() *
            (await morpherTradeEngine.longShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), position._liquidationPrice.toNumber(),
                roundToInteger(80), 300000, 500000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue, 79985000000);

        assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(80));
        assert.equal(position._longShares.toNumber(), 10);
        assert.equal(position._shortShares.toNumber(), 0);
        assert.equal(position._meanEntrySpread.toNumber(), 300000);
        assert.equal(position._meanEntryLeverage.toNumber(), 500000000);

        assert.equal(userBalance, '400000000199973000000');
    });
});

contract('MorpherTradeEngine', (accounts) => {
    // ---- TEST 9 -----
    // userBalance               = 80000000000000000000;
    // position.averagePrice     = 9000000000;
    // position.longShares       = 0;
    // position.shortShares      = 10;
    // position.averageSpread    = 500000;
    // position.averageLeverage  = 200000000;
    //
    // market.price              = 20000000000;
    // market.spread             = 200000;
    //
    // trade.amount              = 11;
    // trade.amountGivenInShares = true;
    // trade.orderLeverage       = 500000000;
    // trade.direction           = long; //true
    //
    // ---- RESULT 9 -----
    //
    // position.value            = 19999000000‬;
    // position.averagePrice     = 20000000000;
    // position.longShares       = 1;
    // position.shortShares      = 0;
    // position.averageSpread    = 200000;
    // position.averageLeverage  = 500000000;
    //
    // userBalance               = 79999999979999000000‬;
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
        let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(90), 200000000, false)).toNumber();

        //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
        await morpherState.setPosition(account1, BTC, 0, 0, 10, roundToInteger(90), 500000, 200000000, liquidationPrice);

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, true, 11, true, 500000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        // console.log(orderId);
        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(200), 200000, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

        // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._longShares.toNumber() *
            (await morpherTradeEngine.longShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), position._liquidationPrice.toNumber(),
                roundToInteger(200), 200000, 500000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue, 19999000000);

        assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(200));
        assert.equal(position._longShares.toNumber(), 1);
        assert.equal(position._shortShares.toNumber(), 0);
        assert.equal(position._meanEntrySpread.toNumber(), 200000);
        assert.equal(position._meanEntryLeverage.toNumber(), 500000000);

        assert.equal(userBalance, '79999999979999000000');
    });
});

contract('MorpherTradeEngine', (accounts) => {
    // ---- TEST 10 -----
    // userBalance               = 1000000000000000000000;
    // position.averagePrice     = 30000000000;
    // position.longShares       = 1;
    // position.shortShares      = 0;
    // position.averageSpread    = 2000000;
    // position.averageLeverage  = 300000000;
    //
    // market.price              = 40000000000;
    // market.spread             = 1000000;
    //
    // trade.amount              = 1;
    // trade.amountGivenInShares = true;
    // trade.orderLeverage       = 500000000;
    // trade.direction           = short; //false
    //
    // ---- RESULT 10 -----
    //
    // position.value            = 0;
    // position.averagePrice     = 0;
    // position.longShares       = 0;
    // position.shortShares      = 0;
    // position.averageSpread    = 0;
    // position.averageLeverage  = 100000000;
    //
    // userBalance               = 1000000000059997000000;
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
        let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(300), 300000000, true)).toNumber();

        //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
        await morpherState.setPosition(account1, BTC, 0, 1, 0, roundToInteger(300), 200000, 300000000, liquidationPrice);

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, true, 1, false, 500000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        // console.log(orderId);
        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(400), 1000000, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

        // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._longShares.toNumber() *
            (await morpherTradeEngine.longShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), position._liquidationPrice.toNumber(),
                roundToInteger(400), 1000000, 500000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue, 0);

        assert.equal(position._meanEntryPrice.toNumber(), 0);
        assert.equal(position._longShares.toNumber(), 0);
        assert.equal(position._shortShares.toNumber(), 0);
        assert.equal(position._meanEntrySpread.toNumber(), 0);
        assert.equal(position._meanEntryLeverage.toNumber(), 100000000);

        assert.equal(userBalance, '1000000000059997000000');
    });
});

contract('MorpherTradeEngine', (accounts) => {
    // ---- TEST 11 -----
    // userBalance               = 1000000000000000000000;
    // position.averagePrice     = 30000000000;
    // position.longShares       = 10;
    // position.shortShares      = 0;
    // position.averageSpread    = 2000000;
    // position.averageLeverage  = 200000000;

    // market.price              = 20000000000;
    // market.spread             = 1000000;
    //
    // trade.amount              = 220000000000;
    // trade.amountGivenInShares = false;
    // trade.orderLeverage       = 500000000;
    // trade.direction           = short; //false
    //
    // ---- RESULT 11 -----
    //
    // position.value            = 99975000000;
    // position.averagePrice     = 20000000000;
    // position.longShares       = 0;
    // position.shortShares      = 5;
    // position.averageSpread    = 1000000;
    // position.averageLeverage  = 500000000;
    //
    // userBalance               = 999999999999955000000;
    it('test case 11', async () => {
        let account0 = accounts[0]; let account1 = accounts[1];

        let morpherTradeEngine = await MorpherTradeEngine.deployed();
        let morpherToken = await MorpherToken.deployed();
        let morpherState = await MorpherState.deployed();
        let morpherOracle = await MorpherOracle.deployed();

        // Set balance of testing account.
        //(address to, uint256 tokens)
        await morpherToken.transfer(account1, '1000000000000000000000');

        //(_newMeanEntryPrice, _newMeanEntryLeverage, _long)
        let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(300), 200000000, true)).toNumber();

        //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
        await morpherState.setPosition(account1, BTC, 0, 10, 0, roundToInteger(300), 2000000, 200000000, liquidationPrice);

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, false, 220000000000, false, 500000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        // console.log(orderId);
        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(200), 1000000, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

        // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._shortShares.toNumber() *
            (await morpherTradeEngine.shortShareValue(position._meanEntryPrice.toNumber(),
                position._meanEntryLeverage.toNumber(), position._liquidationPrice.toNumber(),
                roundToInteger(200), 1000000, 500000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue, 99975000000);

        assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(200));
        assert.equal(position._longShares.toNumber(), 0);
        assert.equal(position._shortShares.toNumber(), 5);
        assert.equal(position._meanEntrySpread.toNumber(), 1000000);
        assert.equal(position._meanEntryLeverage.toNumber(), 500000000);

        assert.equal(userBalance, '999999999999955000000');
    });
});

contract('MorpherTradeEngine', (accounts) => {
    // ---- TEST 12 -----
    // userBalance               = 1000000000000000000000;
    // position.averagePrice     = 30000000000;
    // position.longShares       = 0;
    // position.shortShares      = 100;
    // position.averageSpread    = 2000000;
    // position.averageLeverage  = 300000000;

    // market.price              = 20000000000; 20,005,000,000‬
    // market.spread             = 1000000;
    //
    // trade.amount              = 10000000000000;
    // trade.amountGivenInShares = false;
    // trade.orderLeverage       = 500000000;
    // trade.direction           = true; //false
    //
    // ---- RESULT 12 -----
    //
    // position.value            = 3979005000000;
    // position.averagePrice     = 20000000000;
    // position.longShares       = 199;
    // position.shortShares      = 0;
    // position.averageSpread    = 1000000;
    // position.averageLeverage  = 500000000;
    //
    // userBalance               = 1000000002018705000000‬;
    it('test case 12', async () => {
        let account0 = accounts[0]; let account1 = accounts[1];

        let morpherTradeEngine = await MorpherTradeEngine.deployed();
        let morpherToken = await MorpherToken.deployed();
        let morpherState = await MorpherState.deployed();
        let morpherOracle = await MorpherOracle.deployed();

        // Set balance of testing account.
        //(address to, uint256 tokens)
        await morpherToken.transfer(account1, '1000000000000000000000');

        //(_newMeanEntryPrice, _newMeanEntryLeverage, _long)
        let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(300), 300000000, false)).toNumber();

        //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
        await morpherState.setPosition(account1, BTC, 0, 0, 100, roundToInteger(300), 2000000, 300000000, liquidationPrice);

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, false, 10000000000000, true, 500000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        // console.log(orderId);
        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(200), 1000000, 0, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

        // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._longShares.toNumber() *
            (await morpherTradeEngine.longShareValue(position._meanEntryPrice.toNumber(),
                position._meanEntryLeverage.toNumber(), position._liquidationPrice.toNumber(),
                roundToInteger(200), 1000000, 500000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue, 3979005000000);

        assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(200));
        assert.equal(position._longShares.toNumber(), 199);
        assert.equal(position._shortShares.toNumber(), 0);
        assert.equal(position._meanEntrySpread.toNumber(), 1000000);
        assert.equal(position._meanEntryLeverage.toNumber(), 500000000);

        assert.equal(userBalance, '1000000002018705000000');
    });
});
