const MorpherToken = artifacts.require("MorpherToken");
const MorpherTradeEngine = artifacts.require("MorpherTradeEngine");
const MorpherState = artifacts.require("MorpherState");
const MorpherOracle = artifacts.require("MorpherOracle");

let BTC = '0x0bc89e95f9fdaab7e8a11719155f2fd638cb0f665623f3d12aab71d1a125daf9';

function roundToInteger(price) {
    return Math.round(price * Math.pow(10, 8));
}

contract('MorpherTradeEngine', (accounts) => {

    it('margin calculation works correctly', async () => {
        let morpherTradeEngine = await MorpherTradeEngine.deployed();
        let createdTimestamp = Date.now() - 2592000000; //today  - 30 days
        //30 days should yield interest = price * (leverage - 1) * (days + 1) * 0.000015 percent
        //30000000000 * (200000000 - 100000000) * ( (2592000 / 86400) + 1) * (15000 / 100000000) / 100000000 percent = 13950000 is the interest on the exsting position 

        assert('13950000', (await morpherTradeEngine.calculateMarginInterest(roundToInteger(300), 200000000, createdTimestamp)).toString(), 'Margin interest calculation doesnt work');
    })

    // ---- TEST 1 -----
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
    it('test case 1: rollover 10 longshares to 5 short shares with spread 5x', async () => {
        let account0 = accounts[0]; let account1 = accounts[1];

        let morpherTradeEngine = await MorpherTradeEngine.deployed();
        let morpherToken = await MorpherToken.deployed();
        let morpherState = await MorpherState.deployed();
        let morpherOracle = await MorpherOracle.deployed();

        // Set balance of testing account.
        //(address to, uint256 tokens)
        await morpherToken.transfer(account1, '1000000000000000000000');

        //(_newMeanEntryPrice, _newMeanEntryLeverage, _long)
        let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(300), 200000000, true, Math.round(Date.now() / 1000))).toNumber();

        let createdTimestamp = Date.now() - 2592000000 + 100000; //today  - 30 days + 100 seconds buffer for rollover from 1 day to the other
        //30 days should yield interest = price * (leverage - 1) * (days + 1) * 0.000015 percent
        //30000000000 * (200000000 - 100000000) * ( (2592000 / 86400) + 1) * (15000 / 100000000) / 100000000 percent = 13950000 is the interest on the exsting position 

        //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
        await morpherState.setPosition(account1, BTC, createdTimestamp, 10, 0, roundToInteger(300), 2000000, 200000000, liquidationPrice);

        // (address _address, bytes32 _marketId)
        let position1 = await morpherState.getPosition(account1, BTC);

        // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValueOldPosition = position1._longShares.toNumber() *
            (await morpherTradeEngine.longShareValue(position1._meanEntryPrice.toString(),
            position1._meanEntryLeverage.toString(), createdTimestamp, 
                roundToInteger(200), 1000000, 0, true)).toNumber();

        assert.equal(positionValueOldPosition, 98630000000);

        //(_marketId, _closeSharesAmount, _openMPHAmount, _tradeDirection, _orderLeverage, _onlyIfPriceAbove, _onlyIfPriceBelow, _goodUntil, _goodFrom)
        let orderId = (await morpherOracle.createOrder(BTC, 10, roundToInteger(1000), false, 500000000, 0, 0, 0, 0, { from: account1 })).logs[0].args._orderId;


        //(_orderId, _price, _unadjustedPrice, _spread, _liquidationTimestamp, _timeStamp, gasForNextCallback)
        const oracleTimestampForPosition = Date.now() - 60000; //1 minute delay
        await morpherOracle.__callback(orderId, roundToInteger(200), roundToInteger(200), 1000000, 0, oracleTimestampForPosition, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

        // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._shortShares.toNumber() *
            (await morpherTradeEngine.shortShareValue(position._meanEntryPrice.toString(),
                position._meanEntryLeverage.toString(), oracleTimestampForPosition,
                roundToInteger(200), 1000000, 0, true)).toNumber();

        assert.equal(positionValue, 79932000000);
        assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(200));
        assert.equal(position._longShares.toNumber(), 0);
        assert.equal(position._shortShares.toNumber(), 4);
        assert.equal(position._meanEntrySpread.toNumber(), 1000000);
        assert.equal(position._meanEntryLeverage.toNumber(), 500000000);

        let userBalance = (await morpherState.balanceOf(account1)).toString();
        assert.equal(userBalance, '1000000000018610000000');
    });
});

contract('MorpherTradeEngine', (accounts) => {
    // ---- TEST 2 -----
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
    it('test case 2: rollover 100 short shares to long shares, payout rest', async () => {
        let account0 = accounts[0]; let account1 = accounts[1];

        let morpherTradeEngine = await MorpherTradeEngine.deployed();
        let morpherToken = await MorpherToken.deployed();
        let morpherState = await MorpherState.deployed();
        let morpherOracle = await MorpherOracle.deployed();

        // Set balance of testing account.
        //(address to, uint256 tokens)
        await morpherToken.transfer(account1, '1000000000000000000000');

        //(_newMeanEntryPrice, _newMeanEntryLeverage, _long)
        let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(300), 300000000, false, Math.round(Date.now() / 1000))).toNumber();

        
        let createdTimestamp = Date.now() - 2592000000 + 100000; //today  - 30 days + 100 seconds buffer for rollover from 1 day to the other

        //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
        await morpherState.setPosition(account1, BTC, createdTimestamp, 0, 100, roundToInteger(300), 2000000, 300000000, liquidationPrice);

        //(_marketId, _closeSharesAmount, _openMPHAmount, _tradeDirection, _orderLeverage, _onlyIfPriceAbove, _onlyIfPriceBelow, _goodUntil, _goodFrom)
        let orderId = (await morpherOracle.createOrder(BTC, 100, roundToInteger(100000), true, 500000000, 0, 0, 0, 0, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        // console.log(orderId);
        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        const oracleTimestampForPosition = Date.now() - 60000; //1 minute delay
        await morpherOracle.__callback(orderId, roundToInteger(200), roundToInteger(200), 1000000, 0, oracleTimestampForPosition, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

        // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._longShares.toNumber() *
            (await morpherTradeEngine.longShareValue(position._meanEntryPrice.toNumber(),
                position._meanEntryLeverage.toNumber(), oracleTimestampForPosition, 
                roundToInteger(200), 1000000, 500000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue, 9971517000000);

        assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(200));
        assert.equal(position._longShares.toNumber(), 499);
        assert.equal(position._shortShares.toNumber(), 0);
        assert.equal(position._meanEntrySpread.toNumber(), 1000000);
        assert.equal(position._meanEntryLeverage.toNumber(), 500000000);

        assert.equal(userBalance, '999999995990205000000');
    });
});


contract('MorpherTradeEngine', (accounts) => {
    // ---- TEST 9 -----
    // userBalance               = 80000000000000000000;
    // position.averagePrice     = 9000000000;
    // position.longShares       = 0;
    // position.shortShares      = 1;
    // position.averageSpread    = 500000;
    //
    // market.price              = 20000000000;
    // market.spread             = 200000;
    //
    // trade.amount              = 1;
    // trade.amountGivenInShares = true;
    // trade.direction           = long; //true
    //
    // ---- RESULT 9 -----
    //
    // position.value            = 0;
    // position.averagePrice     = 0;
    // position.longShares       = 0;
    // position.shortShares      = 0;
    // position.averageSpread    = 0;
    //
    // userBalance               = 80000000000000000000;
    it('test case 9: liquidate a short position, price + spread calculation', async () => {
        let account0 = accounts[0]; let account1 = accounts[1];

        let morpherTradeEngine = await MorpherTradeEngine.deployed();
        let morpherToken = await MorpherToken.deployed();
        let morpherState = await MorpherState.deployed();
        let morpherOracle = await MorpherOracle.deployed();

        // Set balance of testing account.
        //(address to, uint256 tokens)
        await morpherToken.transfer(account1, '80000000000000000000');

        //(_newMeanEntryPrice, _newMeanEntryLeverage, _long)
        let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(90), 100000000, false, Math.round(Date.now() / 1000))).toNumber();

        let createdTimestamp = Math.round(Date.now() / 1000) - 2592000 + 100; //today  - 30 days + 100 seconds buffer for rollover from 1 day to the other
        //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
        await morpherState.setPosition(account1, BTC, createdTimestamp, 0, 1, roundToInteger(90), 500000, 100000000, liquidationPrice, { from: account0 });

        //(_marketId, _closeSharesAmount, _openMPHAmount, _tradeDirection, _orderLeverage, _onlyIfPriceAbove, _onlyIfPriceBelow, _goodUntil, _goodFrom)
        let orderId = (await morpherOracle.createOrder(BTC, 1, 0, true, 100000000, 0, 0, 0, 0, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        // console.log(orderId);
        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        const oracleTimestampForPosition = Math.round(Date.now() / 1000) - 60; //1 minute delay
        await morpherOracle.__callback(orderId, roundToInteger(200), 0, 200000, 0, oracleTimestampForPosition, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

        // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._longShares.toNumber() *
            (await morpherTradeEngine.longShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), oracleTimestampForPosition, 
                roundToInteger(200), 200000, 100000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue, 0);

        assert.equal(position._meanEntryPrice.toNumber(), 0);
        assert.equal(position._longShares.toNumber(), 0);
        assert.equal(position._shortShares.toNumber(), 0);
        assert.equal(position._meanEntrySpread.toNumber(), 0);

        assert.equal(userBalance, '80000000000000000000');
    });
});

contract('MorpherTradeEngine', (accounts) => {

    it('position opening is possible with leverage 10 and old deployed timestamp', async () => {
        let account0 = accounts[0]; let account1 = accounts[1];

        let morpherTradeEngine = await MorpherTradeEngine.deployed();
        let morpherToken = await MorpherToken.deployed();
        let morpherState = await MorpherState.deployed();
        let morpherOracle = await MorpherOracle.deployed();

        // Set balance of testing account.
        //(address to, uint256 tokens)
        await morpherToken.transfer(account1, web3.utils.toWei('1','ether'));
        //(_marketId, _closeSharesAmount, _openMPHAmount, _tradeDirection, _orderLeverage, _onlyIfPriceAbove, _onlyIfPriceBelow, _goodUntil, _goodFrom)
        let orderId = (await morpherOracle.createOrder(BTC, 0, web3.utils.toWei('1','ether'), true, 1000000000, 0, 0, 0, 0, { from: account1 })).logs[0].args._orderId;

        // console.log(orderId);
        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        const oracleTimestampForPosition = Math.round(Date.now() / 1000) - 60; //1 minute delay
        await morpherOracle.__callback(orderId, roundToInteger(200), 0, 0, 0, oracleTimestampForPosition, 0, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

        // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._longShares.toNumber() *
            (await morpherTradeEngine.longShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), oracleTimestampForPosition, 
                roundToInteger(200), 200000, 100000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue, 0);

        assert.equal(position._meanEntryPrice.toNumber(), 20000000000);
        assert.equal(position._longShares.toNumber(), 50000000);
        assert.equal(position._shortShares.toNumber(), 0);
        assert.equal(position._meanEntrySpread.toNumber(), 0);

        assert.equal(userBalance, '0');
    });
});
