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
        let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(300), 200000000, true)).toNumber();

        //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
        await morpherState.setPosition(account1, BTC, 0, 10, 0, roundToInteger(300), 2000000, 200000000, liquidationPrice);

        //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
        let orderId = (await morpherOracle.createOrder(BTC, false, 220000000000, false, 500000000, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

        // console.log(orderId);
        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(200), 1000000, 0, 0, 0, { from: account0 });

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
    it('test case 2: rollover 100 short shares to 199 long shares, payout rest, 5x leveraged', async () => {
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
        await morpherOracle.__callback(orderId, roundToInteger(200), 1000000, 0, 0, 0, { from: account0 });

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