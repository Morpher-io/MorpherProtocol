const truffleAssertions = require("truffle-assertions");

const MorpherToken = artifacts.require("MorpherToken");
const MorpherTradeEngine = artifacts.require("MorpherTradeEngine");
const MorpherState = artifacts.require("MorpherState");
const MorpherOracle = artifacts.require("MorpherOracle");

let BTC = '0x0bc89e95f9fdaab7e8a11719155f2fd638cb0f665623f3d12aab71d1a125daf9';

function roundToInteger(price) {
    return Math.round(price * Math.pow(10, 8));
}

const BN = require("bn.js");


const startingBalance = web3.utils.toWei(new BN(1),'ether');

contract('MorpherTradeEngine: Trade long/short with MPH', (accounts) => {
    
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
    it('test case 1: open long, 300 BNB, each share 150PS = 2 Shares', async () => {
        let account0 = accounts[0]; let account1 = accounts[1];

        let morpherTradeEngine = await MorpherTradeEngine.deployed();
        let morpherState = await MorpherState.deployed();
        let morpherOracle = await MorpherOracle.deployed();

        // Set balance of testing account.
        //(address to, uint256 tokens)
        //await morpherToken.transfer(account1, startingBalance);

        //(_marketId, _closeSharesAmount, _openMPHAmount, _tradeDirection, _orderLeverage, _onlyIfPriceAbove, _onlyIfPriceBelow, _goodUntil, _goodFrom)
        let amount = web3.utils.toWei('1','ether');
        let orderId = (await morpherOracle.createOrder(BTC, 0, true, 100000000, 0 ,0 ,0 ,0, { from: account1, value: amount })).logs[0].args._orderId;

        // console.log(orderId);
        //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
        await morpherOracle.__callback(orderId, roundToInteger(150), roundToInteger(150), 0, 0, 0, 0, 0, 1, { from: account0 });

        // (address _address, bytes32 _marketId)
        let position = await morpherState.getPosition(account1, BTC);

        // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
        let positionValue = position._longShares.toNumber() *
            (await morpherTradeEngine.longShareValue(position._meanEntryPrice.toNumber(),
            position._meanEntryLeverage.toNumber(), 0, 
                roundToInteger(150), 0, 100000000, true)).toNumber();

        let userBalance = (await morpherState.balanceOf(account1)).toString();

        assert.equal(positionValue, 999999990000000000);

        assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(150));
        assert.equal(position._longShares.toNumber(), 66666666);
        assert.equal(position._shortShares.toNumber(), 0);

        assert.equal(userBalance, 0); // the use shouldn't have a balance


        //(_marketId, _closeSharesAmount, _openMPHAmount, _tradeDirection, _orderLeverage, _onlyIfPriceAbove, _onlyIfPriceBelow, _goodUntil, _goodFrom)
        orderId = (await morpherOracle.createOrder(BTC, 999999990000000000, false, 100000000, 0 ,0 ,0 ,0, { from: account1 })).logs[0].args._orderId;

        await morpherOracle.__callback(orderId, roundToInteger(150), roundToInteger(150), 0, 0, 0, 0, 999999990000000000, 2, { from: account0 });
        
        userBalance = (await morpherState.balanceOf(account1)).toString();
        assert.equal(userBalance, startingBalance.toString());

    });

//     // ---- TEST 2 -----
//     // userBalance               = 100000000000000000000;
//     // position.averagePrice     = 0;
//     // position.longShares       = 0;
//     // position.shortShares      = 0;
//     //
//     // market.price              = 1000000000;
//     // market.spread             = 0;
//     //
//     // trade.amount              = 2000000000;
//     // trade.amountGivenInShares = false;
//     // trade.direction           = short; //false
//     //
//     // ---- RESULT 2 -----
//     //
//     // position.value            = 2000000000;
//     // position.averagePrice     = 1000000000;
//     // position.longShares       = 0;
//     // position.shortShares      = 2;
//     //
//     // userBalance               = 99999999998000000000;
//     it('test case 2: Open Short, 200 MPH, each share 100MPH = 2 shares', async () => {
//         let account0 = accounts[0]; let account1 = accounts[1];

//         let morpherTradeEngine = await MorpherTradeEngine.deployed();
//         let morpherToken = await MorpherToken.deployed();
//         let morpherState = await MorpherState.deployed();
//         let morpherOracle = await MorpherOracle.deployed();

//         // Set balance of testing account.
//         //(address to, uint256 tokens)

//         //(_marketId, _closeSharesAmount, _openMPHAmount, _tradeDirection, _orderLeverage, _onlyIfPriceAbove, _onlyIfPriceBelow, _goodUntil, _goodFrom)
//         let orderId = (await morpherOracle.createOrder(BTC, 0, roundToInteger(20), false, 100000000, 0 ,0 ,0 ,0, { from: account1 })).logs[0].args._orderId;

//         //(_orderId, _price, _originalPrice, _spread, _liquidationTimestamp, _timeStamp, _callbackGasNextOrder)
//         await morpherOracle.__callback(orderId, roundToInteger(10), roundToInteger(10), 0, 0, 0, 0, { from: account0 });

//         // (address _address, bytes32 _marketId)
//         let position = await morpherState.getPosition(account1, BTC);

//         // shortShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
//         let positionValue = position._shortShares.toNumber() *
//             (await morpherTradeEngine.shortShareValue(position._meanEntryPrice.toNumber(),
//             position._meanEntryLeverage.toNumber(), 0, 
//                 roundToInteger(10), 0, 100000000, true)).toNumber();

//         let userBalance = (await morpherState.balanceOf(account1)).toString();

//         assert.equal(positionValue, roundToInteger(20));

//         assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(10));
//         assert.equal(position._longShares.toNumber(), 0);
//         assert.equal(position._shortShares.toNumber(), 2);

//         assert.equal(userBalance, startingBalance.sub(new BN(roundToInteger(20))).toString());
//     });
// });

// contract('MorpherTradeEngine cannot close with MPH', (accounts) => {
//     //test closing with MPH will fail, 
//     // 1. positions are not deleted, 
//     // 2. Token amount stays the same, 
//     // 3. no escrow is taken
//     it('test case 3: close long 2 BTC@50 with short 160MPH should fail, can only trade in shares.', async () => {
//         let account0 = accounts[0]; let account1 = accounts[1];

//         let morpherTradeEngine = await MorpherTradeEngine.deployed();
//         let morpherToken = await MorpherToken.deployed();
//         let morpherState = await MorpherState.deployed();
//         let morpherOracle = await MorpherOracle.deployed();

//         // Set balance of testing account.
//         //(address to, uint256 tokens)
//         await morpherToken.transfer(account1, '500000000000000000000');

//         //(_newMeanEntryPrice, _newMeanEntryLeverage, _long)
//         let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(50), 100000000, true, Math.round(Date.now() / 1000))).toNumber();

//         //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
//         await morpherState.setPosition(account1, BTC, 0, 2, 0, roundToInteger(50), 0, 100000000, liquidationPrice, { from: account0 });


//         //(_marketId, _closeSharesAmount, _openMPHAmount, _tradeDirection, _orderLeverage, _onlyIfPriceAbove, _onlyIfPriceBelow, _goodUntil, _goodFrom)
//         truffleAssertions.fails(
//             morpherOracle.createOrder(BTC, 0, roundToInteger(160), false, 100000000, 0, 0, 0, 0, { from: account1 }),
//             truffleAssertions.ErrorType.REVERT,
//             "MorpherTradeEngine: Can't partially close a position and open another one in opposite direction"
//         );

//         // (address _address, bytes32 _marketId)
//         let position = await morpherState.getPosition(account1, BTC);

//         // shortShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
//         let positionValue = position._shortShares.toNumber() *
//             (await morpherTradeEngine.shortShareValue(position._meanEntryPrice.toNumber(),
//                 position._meanEntryLeverage.toNumber(), 0, 
//                 roundToInteger(80), 0, 100000000, true)).toNumber();

//         let userBalance = (await morpherState.balanceOf(account1)).toString();

//         assert.equal(positionValue, 0);

//         assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(50));
//         assert.equal(position._longShares.toNumber(), 2);
//         assert.equal(position._shortShares.toNumber(), 0);

//         assert.equal(userBalance, '500000000000000000000');
//     });

//     it('test case 4: close short with MPH fails (cannot close with MPH)', async () => {
//         let account0 = accounts[0]; let account1 = accounts[1];

//         let morpherTradeEngine = await MorpherTradeEngine.deployed();
//         let morpherToken = await MorpherToken.deployed();
//         let morpherState = await MorpherState.deployed();
//         let morpherOracle = await MorpherOracle.deployed();

//         //(_newMeanEntryPrice, _newMeanEntryLeverage, _long)
//         let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(40), 100000000, false, Math.round(Date.now() / 1000))).toNumber();

//         //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
//         await morpherState.setPosition(account1, BTC, 0, 0, 5, roundToInteger(40), 0, 100000000, liquidationPrice, { from: account0 });

//         //(_marketId, _closeSharesAmount, _openMPHAmount, _tradeDirection, _orderLeverage, _onlyIfPriceAbove, _onlyIfPriceBelow, _goodUntil, _goodFrom)
//         truffleAssertions.fails(
//             morpherOracle.createOrder(BTC, 0, roundToInteger(150), true, 100000000, 0 ,0 ,0 ,0, { from: account1, value: 301000000000000 }),
//             truffleAssertions.ErrorType.REVERT,
//             "MorpherTradeEngine: Can't partially close a position and open another one in opposite direction"
//         );
//         //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
//                 // (address _address, bytes32 _marketId)
//         let position = await morpherState.getPosition(account1, BTC);

//         // shortShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
//         let positionValue = position._shortShares.toNumber() *
//             (await morpherTradeEngine.shortShareValue(position._meanEntryPrice.toNumber(),
//             position._meanEntryLeverage.toNumber(), 0, 
//                 roundToInteger(40), 0, 100000000, true)).toNumber();

//         let userBalance = (await morpherState.balanceOf(account1)).toString();

//         assert.equal(positionValue, roundToInteger(40 * 5)); //5 shares each 40MPH

//         assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(40));
//         assert.equal(position._longShares.toNumber(), 0);
//         assert.equal(position._shortShares.toNumber(), 5);

//         assert.equal(userBalance, '500000000000000000000');
//     });
// });

// contract('MorpherTradeEngine: Double down tests long/short', (accounts) => {


//     // ---- TEST 5 -----
//     // userBalance               = 500000000000000000000;
//     // position.averagePrice     = 5000000000;
//     // position.longShares       = 5;
//     // position.shortShares      = 0;
//     //
//     // market.price              = 10000000000;
//     // market.spread             = 0;
//     //
//     // trade.amount              = 50000000000;
//     // trade.amountGivenInShares = false;
//     // trade.direction           = long; // true
//     //
//     // ---- RESULT 5 -----
//     //
//     // position.value            = 100000000000;
//     // position.averagePrice     = 10000000000;
//     // position.longShares       = 10;
//     // position.shortShares      = 0;
//     //
//     // userBalance               = 499999999950000000000‬;
//     it('test case 5: double down on long position', async () => {
//         let account0 = accounts[0]; let account1 = accounts[1];

//         let morpherTradeEngine = await MorpherTradeEngine.deployed();
//         let morpherToken = await MorpherToken.deployed();
//         let morpherState = await MorpherState.deployed();
//         let morpherOracle = await MorpherOracle.deployed();

//         // Set balance of testing account.
//         //(address to, uint256 tokens)
//         await morpherToken.transfer(account1, startingBalance);

//         //(_newMeanEntryPrice, _newMeanEntryLeverage, _long)
//         let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(50), 100000000, true, Math.round(Date.now() / 1000))).toNumber();

//         //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
//         await morpherState.setPosition(account1, BTC, 0, 5, 0, roundToInteger(50), 0, 100000000, liquidationPrice, { from: account0 });

//         //(_marketId, _closeSharesAmount, _openMPHAmount, _tradeDirection, _orderLeverage, _onlyIfPriceAbove, _onlyIfPriceBelow, _goodUntil, _goodFrom)
//         let orderId = (await morpherOracle.createOrder(BTC, 0, roundToInteger(500), true, 100000000, 0 ,0 ,0 ,0, { from: account1 })).logs[0].args._orderId;

//         //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
//         await morpherOracle.__callback(orderId, roundToInteger(100), roundToInteger(100), 0, 0, 0, 0, { from: account0 });

//         // (address _address, bytes32 _marketId)
//         let position = await morpherState.getPosition(account1, BTC);

//         // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
//         let positionValue = position._longShares.toNumber() *
//             (await morpherTradeEngine.longShareValue(position._meanEntryPrice.toNumber(),
//             position._meanEntryLeverage.toNumber(), 0, 
//                 roundToInteger(100), 0, 100000000, true)).toNumber();

//         let userBalance = (await morpherState.balanceOf(account1)).toString();

//         assert.equal(positionValue, roundToInteger(1000));

//         assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(100));
//         assert.equal(position._longShares.toNumber(), 10);
//         assert.equal(position._shortShares.toNumber(), 0);

//         assert.equal(userBalance, startingBalance.sub(new BN(roundToInteger(500))).toString());

//         orderId = (await morpherOracle.createOrder(BTC, 10, 0, false, 100000000, 0, 0, 0, 0, {from: account1})).logs[0].args._orderId;
//         //sell at 0
//         await morpherOracle.__callback(orderId, roundToInteger(50), roundToInteger(50), 0, 0, 0, 0, { from: account0 }); //back to 500

//         position = await morpherState.getPosition(account1, BTC);
        
//         assert.equal(position._meanEntryPrice.toNumber(), 0);
//         assert.equal(position._longShares.toNumber(), 0);
//         assert.equal(position._shortShares.toNumber(), 0);
        
//         userBalance = (await morpherState.balanceOf(account1)).toString();
        
//         assert.equal(userBalance, startingBalance.toString()); //nothing changed, all sold
//     }); 

//     // ---- TEST 6 -----
//     // userBalance               = 1000000000000000000000;
//     // position.averagePrice     = 10000000000;
//     // position.longShares       = 0;
//     // position.shortShares      = 50;
//     //
//     // market.price              = 8000000000;
//     // market.spread             = 0;
//     //
//     // trade.amount              = 400000000000;
//     // trade.amountGivenInShares = false;
//     // trade.direction           = short; // false
//     //
//     // ---- RESULT 6 -----
//     //
//     // position.value            = 1000000000000‬;
//     // position.averagePrice     = 8000000000;
//     // position.longShares       = 0;
//     // position.shortShares      = 125;
//     //
//     // userBalance               = 999999999600000000000‬;
//     it('test case 6: double down on short position', async () => {
//         let account0 = accounts[0]; let account1 = accounts[1];

//         let morpherTradeEngine = await MorpherTradeEngine.deployed();
//         let morpherToken = await MorpherToken.deployed();
//         let morpherState = await MorpherState.deployed();
//         let morpherOracle = await MorpherOracle.deployed();

//         //(_newMeanEntryPrice, _newMeanEntryLeverage, _long)
//         let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(100), 100000000, false, Math.round(Date.now() / 1000))).toNumber();

//         //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
//         await morpherState.setPosition(account1, BTC, 0, 0, 50, roundToInteger(100), 0, 100000000, liquidationPrice, { from: account0 });

//         //(_marketId, _closeSharesAmount, _openMPHAmount, _tradeDirection, _orderLeverage, _onlyIfPriceAbove, _onlyIfPriceBelow, _goodUntil, _goodFrom)
//         let orderId = (await morpherOracle.createOrder(BTC, 0, roundToInteger(4000), false, 100000000, 0 ,0 ,0 ,0, { from: account1, value: 301000000000000 })).logs[0].args._orderId;

//         //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
//         await morpherOracle.__callback(orderId, roundToInteger(80), roundToInteger(80), 0, 0, 0, 0, { from: account0 });

//         // (address _address, bytes32 _marketId)
//         let position = await morpherState.getPosition(account1, BTC);

//         // shortShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
//         let positionValue = position._shortShares.toNumber() *
//             (await morpherTradeEngine.shortShareValue(position._meanEntryPrice.toNumber(),
//             position._meanEntryLeverage.toNumber(), 0, 
//                 roundToInteger(80), 0, 100000000, true)).toNumber();

//         let userBalance = (await morpherState.balanceOf(account1)).toString();

//         assert.equal(positionValue, roundToInteger(10000));

//         assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(80));
//         assert.equal(position._longShares.toNumber(), 0);
//         assert.equal(position._shortShares.toNumber(), 125);

//         assert.equal(userBalance, startingBalance.sub(new BN(roundToInteger(4000))).toString());

//         orderId = (await morpherOracle.createOrder(BTC, 125, 0, true, 100000000, 0 ,0 ,0 ,0, { from: account1 })).logs[0].args._orderId; //sell everything
//         await morpherOracle.__callback(orderId, roundToInteger(128), roundToInteger(48), 0, 0, 0, 0, { from: account0 }); //4000 / 125 shares = 32
//         userBalance = (await morpherState.balanceOf(account1)).toString();
        
//         assert.equal(userBalance, startingBalance.toString()); //everything is back to start

//     });
// });

// contract('MorpherTradeEngine: rollover tests', (accounts) => {
//     // ---- TEST 7 -----
//     // userBalance               = 500000000000000000000;
//     // position.averagePrice     = 5000000000;
//     // position.longShares       = 100;
//     // position.shortShares      = 0;
//     //
//     // market.price              = 4000000000;
//     // market.spread             = 0;
//     //
//     // trade.amount              = 600000000000;
//     // trade.amountGivenInShares = false;
//     // trade.direction           = short; // false
//     //
//     // ---- RESULT 7 -----
//     //
//     // position.value            = 200000000000‬;
//     // position.averagePrice     = 4000000000;
//     // position.longShares       = 0;
//     // position.shortShares      = 50;
//     //
//     // userBalance               = 500000000200000000000‬;
//     it('test case 7: rollover long to short with payout', async () => {
//         let account0 = accounts[0]; let account1 = accounts[1];

//         let morpherTradeEngine = await MorpherTradeEngine.deployed();
//         let morpherToken = await MorpherToken.deployed();
//         let morpherState = await MorpherState.deployed();
//         let morpherOracle = await MorpherOracle.deployed();

//         // Set balance of testing account.
//         //(address to, uint256 tokens)
//         await morpherToken.transfer(account1, startingBalance);

//         //(_newMeanEntryPrice, _newMeanEntryLeverage, _long)
//         let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(50), 100000000, true, Math.round(Date.now() / 1000))).toNumber();

//         //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
//         await morpherState.setPosition(account1, BTC, 0, 100, 0, roundToInteger(50), 0, 100000000, liquidationPrice, { from: account0 });

//         //(_marketId, _closeSharesAmount, _openMPHAmount, _tradeDirection, _orderLeverage, _onlyIfPriceAbove, _onlyIfPriceBelow, _goodUntil, _goodFrom)
//         let orderId = (await morpherOracle.createOrder(BTC, 100, roundToInteger(6000), false, 100000000, 0 ,0 ,0 ,0, { from: account1 })).logs[0].args._orderId;

//         //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
//         await morpherOracle.__callback(orderId, roundToInteger(40), roundToInteger(40), 0, 0, 0, 0, { from: account0 });

//         // (address _address, bytes32 _marketId)
//         let position = await morpherState.getPosition(account1, BTC);

//         // shortShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
//         let positionValue = position._shortShares.toNumber() *
//             (await morpherTradeEngine.shortShareValue(position._meanEntryPrice.toNumber(),
//             position._meanEntryLeverage.toNumber(), 0, 
//                 roundToInteger(40), 0, 100000000, true)).toNumber();

//         let userBalance = (await morpherState.balanceOf(account1)).toString();

//         assert.equal(positionValue, roundToInteger(6000));

//         assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(40));
//         assert.equal(position._longShares.toNumber(), 0);
//         assert.equal(position._shortShares.toNumber(), 150);

//         assert.equal(userBalance, startingBalance.sub(new BN(roundToInteger(6000))).add(new BN(roundToInteger(40 * 100))));

//         orderId = (await morpherOracle.createOrder(BTC, 150, 0, true, 100000000, 0 ,0 ,0 ,0, { from: account1 })).logs[0].args._orderId; //sell everything
//         await morpherOracle.__callback(orderId, roundToInteger(66.66666667), 13333333, 0, 0, 0, 0, { from: account0 });
//         userBalance = (await morpherState.balanceOf(account1)).toString();
        
//         assert.equal(userBalance, startingBalance.sub(new BN(50)).toString()); //can't calculate the exact results cause of floating point precision error
//     });

//     // ---- TEST 8 -----
//     // userBalance               = 400000000000000000000;
//     // position.averagePrice     = 10000000000;
//     // position.longShares       = 0;
//     // position.shortShares      = 20;
//     //
//     // market.price              = 8000000000;
//     // market.spread             = 0;
//     //
//     // trade.amount              = 256000000000‬;
//     // trade.amountGivenInShares = false;
//     // trade.direction           = long; // true
//     //
//     // ---- RESULT 8 -----
//     //
//     // position.value            = 16000000000;
//     // position.averagePrice     = 8000000000;
//     // position.longShares       = 2;
//     // position.shortShares      = 0;
//     //
//     // userBalance               = 400000000224000000000;
//     it('test case 8: rollover short to long with payout', async () => {
//         let account0 = accounts[0]; let account1 = accounts[1];

//         let morpherTradeEngine = await MorpherTradeEngine.deployed();
//         let morpherToken = await MorpherToken.deployed();
//         let morpherState = await MorpherState.deployed();
//         let morpherOracle = await MorpherOracle.deployed();

//         // Set balance of testing account.
//         //(address to, uint256 tokens)
//         await morpherToken.transfer(account1, '50'); //fill up the account to be at startingBalance
//         assert.equal((await morpherState.balanceOf(account1)).toString(), startingBalance.toString(), "balance is the same again");

//         //(_newMeanEntryPrice, _newMeanEntryLeverage, _long)
//         let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(100), 100000000, false, Math.round(Date.now() / 1000))).toNumber();

//         //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
//         await morpherState.setPosition(account1, BTC, 0, 0, 20, roundToInteger(100), 0, 100000000, liquidationPrice, { from: account0 });

//         //(_marketId, _closeSharesAmount, _openMPHAmount, _tradeDirection, _orderLeverage, _onlyIfPriceAbove, _onlyIfPriceBelow, _goodUntil, _goodFrom)
//         let orderId = (await morpherOracle.createOrder(BTC, 20, roundToInteger(2560), true, 100000000, 0 ,0 ,0 ,0, { from: account1 })).logs[0].args._orderId;

//         //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
//         await morpherOracle.__callback(orderId, roundToInteger(80), roundToInteger(80), 0, 0, 0, 0, { from: account0 });

//         // (address _address, bytes32 _marketId)
//         let position = await morpherState.getPosition(account1, BTC);

//         // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
//         let positionValue = position._longShares.toNumber() *
//             (await morpherTradeEngine.longShareValue(position._meanEntryPrice.toNumber(),
//             position._meanEntryLeverage.toNumber(), 0,
//                 roundToInteger(80), 0, 100000000, true)).toNumber();

//         let userBalance = (await morpherState.balanceOf(account1)).toString();

//         assert.equal(positionValue, roundToInteger(80 * 32));

//         assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(80));
//         assert.equal(position._longShares.toNumber(), 32);
//         assert.equal(position._shortShares.toNumber(), 0);

//         assert.equal(userBalance, startingBalance.add(new BN(roundToInteger(120*20))).sub(new BN(roundToInteger(2560))).toString());
//     });
// });


// contract('MorpherTradeEngine: partial closing tests', (accounts) => {
//     // ---- TEST 7 -----
//     // userBalance               = 500000000000000000000;
//     // position.averagePrice     = 5000000000;
//     // position.longShares       = 100;
//     // position.shortShares      = 0;
//     //
//     // market.price              = 4000000000;
//     // market.spread             = 0;
//     //
//     // trade.amount              = 600000000000;
//     // trade.amountGivenInShares = false;
//     // trade.direction           = short; // false
//     //
//     // ---- RESULT 7 -----
//     //
//     // position.value            = 200000000000‬;
//     // position.averagePrice     = 4000000000;
//     // position.longShares       = 0;
//     // position.shortShares      = 50;
//     //
//     // userBalance               = 500000000200000000000‬;
//     it('test case 7: partial closing long with payout', async () => {
//         let account0 = accounts[0]; let account1 = accounts[1];

//         let morpherTradeEngine = await MorpherTradeEngine.deployed();
//         let morpherToken = await MorpherToken.deployed();
//         let morpherState = await MorpherState.deployed();
//         let morpherOracle = await MorpherOracle.deployed();

//         // Set balance of testing account.
//         //(address to, uint256 tokens)
//         await morpherToken.transfer(account1, startingBalance);

//         //(_newMeanEntryPrice, _newMeanEntryLeverage, _long)
//         let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(50), 100000000, true, Math.round(Date.now() / 1000))).toNumber();

//         //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
//         await morpherState.setPosition(account1, BTC, 0, 100, 0, roundToInteger(50), 0, 100000000, liquidationPrice, { from: account0 });

//         //(_marketId, _closeSharesAmount, _openMPHAmount, _tradeDirection, _orderLeverage, _onlyIfPriceAbove, _onlyIfPriceBelow, _goodUntil, _goodFrom)
//         let orderId = (await morpherOracle.createOrder(BTC, 50, 0, false, 100000000, 0 ,0 ,0 ,0, { from: account1 })).logs[0].args._orderId;

//         //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
//         await morpherOracle.__callback(orderId, roundToInteger(40), roundToInteger(40), 0, 0, 0, 0, { from: account0 });

//         // (address _address, bytes32 _marketId)
//         let position = await morpherState.getPosition(account1, BTC);

//         // shortShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
//         let positionValue = position._longShares.toNumber() *
//             (await morpherTradeEngine.longShareValue(position._meanEntryPrice.toNumber(),
//             position._meanEntryLeverage.toNumber(), 0,
//                 roundToInteger(40), 0, 100000000, true)).toNumber();

//         let userBalance = (await morpherState.balanceOf(account1)).toString();

//         assert.equal(positionValue, roundToInteger(40*50));

//         assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(50));
//         assert.equal(position._longShares.toNumber(), 50);
//         assert.equal(position._shortShares.toNumber(), 0);

//         assert.equal(userBalance, startingBalance.add(new BN(roundToInteger(40 * 50))));

//         morpherState.enableTransfers(account1);
//         morpherToken.transfer(account0, roundToInteger(40*50), {from: account1}); //reset to startingBalance

//     });

//     // ---- TEST 8 -----
//     // userBalance               = 400000000000000000000;
//     // position.averagePrice     = 10000000000;
//     // position.longShares       = 0;
//     // position.shortShares      = 20;
//     //
//     // market.price              = 8000000000;
//     // market.spread             = 0;
//     //
//     // trade.amount              = 256000000000‬;
//     // trade.amountGivenInShares = false;
//     // trade.direction           = long; // true
//     //
//     // ---- RESULT 8 -----
//     //
//     // position.value            = 16000000000;
//     // position.averagePrice     = 8000000000;
//     // position.longShares       = 2;
//     // position.shortShares      = 0;
//     //
//     // userBalance               = 400000000224000000000;
//     it('test case 8: partial close short with payout', async () => {
//         let account0 = accounts[0]; let account1 = accounts[1];

//         let morpherTradeEngine = await MorpherTradeEngine.deployed();
//         let morpherState = await MorpherState.deployed();
//         let morpherOracle = await MorpherOracle.deployed();

//         // Set balance of testing account.
//         //(address to, uint256 tokens)
//         assert.equal((await morpherState.balanceOf(account1)).toString(), startingBalance.toString(), "balance is the same again");

//         //(_newMeanEntryPrice, _newMeanEntryLeverage, _long)
//         let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(100), 100000000, false, Math.round(Date.now() / 1000))).toNumber();

//         //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
//         await morpherState.setPosition(account1, BTC, 0, 0, 20, roundToInteger(100), 0, 100000000, liquidationPrice, { from: account0 });

//         //(_marketId, _closeSharesAmount, _openMPHAmount, _tradeDirection, _orderLeverage, _onlyIfPriceAbove, _onlyIfPriceBelow, _goodUntil, _goodFrom)
//         let orderId = (await morpherOracle.createOrder(BTC, 10, 0, true, 100000000, 0 ,0 ,0 ,0, { from: account1 })).logs[0].args._orderId;

//         //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
//         await morpherOracle.__callback(orderId, roundToInteger(80), roundToInteger(80), 0, 0, 0, 0, { from: account0 });

//         // (address _address, bytes32 _marketId)
//         let position = await morpherState.getPosition(account1, BTC);

//         // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
//         let positionValue = position._shortShares.toNumber() *
//             (await morpherTradeEngine.shortShareValue(position._meanEntryPrice.toNumber(),
//             position._meanEntryLeverage.toNumber(), 0,
//                 roundToInteger(80), 0, 100000000, true)).toNumber();

//         let userBalance = (await morpherState.balanceOf(account1)).toString();

//         assert.equal(positionValue, roundToInteger(120 * 10)); //10 shares * (averagePrice * 2 - marketPrice) = 10 * 120

//         assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(100));
//         assert.equal(position._longShares.toNumber(), 0);
//         assert.equal(position._shortShares.toNumber(), 10);

//         assert.equal(userBalance, startingBalance.add(new BN(roundToInteger(120*10))).toString());
//     });
    

//     it('test case 9: partial close timestamp reset', async () => {
//         let account0 = accounts[0]; let account1 = accounts[1];

//         let morpherTradeEngine = await MorpherTradeEngine.deployed();
//         let morpherState = await MorpherState.deployed();
//         let morpherOracle = await MorpherOracle.deployed();

//         //(_newMeanEntryPrice, _newMeanEntryLeverage, _long)
//         let liquidationPrice = (await morpherTradeEngine.getLiquidationPrice(roundToInteger(100), 100000000, false, Math.round(Date.now() / 1000))).toNumber();

//         //(_address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice)
//         await morpherState.setPosition(account1, BTC, 123, 0, 20, roundToInteger(100), 0, 100000000, liquidationPrice, { from: account0 });

//         //(_marketId, _closeSharesAmount, _openMPHAmount, _tradeDirection, _orderLeverage, _onlyIfPriceAbove, _onlyIfPriceBelow, _goodUntil, _goodFrom)
//         let orderId = (await morpherOracle.createOrder(BTC, 10, 0, true, 100000000, 0 ,0 ,0 ,0, { from: account1 })).logs[0].args._orderId;

//         //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
//         await morpherOracle.__callback(orderId, roundToInteger(80), roundToInteger(80), 0, 0, 234, 0, { from: account0 });

//         let lastUpdated = await morpherState.getLastUpdated(account1, BTC);
//         assert.equal(lastUpdated, 123);
//     });
});
