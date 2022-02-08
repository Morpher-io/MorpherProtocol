const truffleAssertions = require('truffle-assertions')

const MorpherToken = artifacts.require('MorpherToken')
const MorpherTradeEngine = artifacts.require('MorpherTradeEngine')
const MorpherState = artifacts.require('MorpherState')
const MorpherOracle = artifacts.require('MorpherOracle')
const MorpherStaking = artifacts.require('MorpherStaking')
const MorpherUserBlocking = artifacts.require('MorpherUserBlocking')

let BTC = '0x0bc89e95f9fdaab7e8a11719155f2fd638cb0f665623f3d12aab71d1a125daf9'

function roundToInteger(price) {
  return Math.round(price * Math.pow(10, 8))
}

const BN = require('bn.js')

const startingBalance = web3.utils.toWei(new BN(1), 'ether')

contract('MorpherTradeEngine: Trade long/short with MPH', (accounts) => {
  it('test case 1: unblocked users can trade normally', async () => {
    let account0 = accounts[0]
    let account1 = accounts[1]

    let morpherTradeEngine = await MorpherTradeEngine.deployed()
    let morpherToken = await MorpherToken.deployed()
    let morpherState = await MorpherState.deployed()
    let morpherOracle = await MorpherOracle.deployed()

    // Set balance of testing account.
    //(address to, uint256 tokens)
    await morpherToken.transfer(account1, startingBalance)

    //(_marketId, _closeSharesAmount, _openMPHAmount, _tradeDirection, _orderLeverage, _onlyIfPriceAbove, _onlyIfPriceBelow, _goodUntil, _goodFrom)
    let orderId = (
      await morpherOracle.createOrder(
        BTC,
        0,
        roundToInteger(300),
        true,
        100000000,
        0,
        0,
        0,
        0,
        { from: account1 },
      )
    ).logs[0].args._orderId

    // console.log(orderId);
    //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
    await morpherOracle.__callback(
      orderId,
      roundToInteger(150),
      roundToInteger(150),
      0,
      0,
      0,
      0,
      { from: account0 },
    )

    // (address _address, bytes32 _marketId)
    let position = await morpherState.getPosition(account1, BTC)

    // longShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
    let positionValue =
      position._longShares.toNumber() *
      (
        await morpherTradeEngine.longShareValue(
          position._meanEntryPrice.toNumber(),
          position._meanEntryLeverage.toNumber(),
          0,
          roundToInteger(150),
          0,
          100000000,
          true,
        )
      ).toNumber()

    let userBalance = (await morpherState.balanceOf(account1)).toString()

    assert.equal(positionValue, roundToInteger(300))

    assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(150))
    assert.equal(position._longShares.toNumber(), 2)
    assert.equal(position._shortShares.toNumber(), 0)

    assert.equal(
      userBalance,
      startingBalance.sub(new BN(roundToInteger(300))).toString(),
    )

    //(_marketId, _closeSharesAmount, _openMPHAmount, _tradeDirection, _orderLeverage, _onlyIfPriceAbove, _onlyIfPriceBelow, _goodUntil, _goodFrom)
    orderId = (
      await morpherOracle.createOrder(BTC, 2, 0, false, 100000000, 0, 0, 0, 0, {
        from: account1,
      })
    ).logs[0].args._orderId

    await morpherOracle.__callback(
      orderId,
      roundToInteger(150),
      roundToInteger(150),
      0,
      0,
      0,
      0,
      { from: account0 },
    )

    userBalance = (await morpherState.balanceOf(account1)).toString()
    assert.equal(userBalance, startingBalance.toString())
  })

  it('test case 2: Block User from Opening Positions', async () => {
    let account0 = accounts[0]
    let account1 = accounts[1]

    let morpherTradeEngine = await MorpherTradeEngine.deployed()
    let morpherToken = await MorpherToken.deployed()
    let morpherState = await MorpherState.deployed()
    let morpherOracle = await MorpherOracle.deployed()
    let morpherUserBlocking = await MorpherUserBlocking.deployed()
    truffleAssertions.eventEmitted(
      await morpherUserBlocking.setUserBlocked(account1, true),
      'ChangeUserBlocked',
    )

    //(_marketId, _closeSharesAmount, _openMPHAmount, _tradeDirection, _orderLeverage, _onlyIfPriceAbove, _onlyIfPriceBelow, _goodUntil, _goodFrom)
    let orderId = (await morpherOracle.createOrder(BTC, 0, roundToInteger(20), false, 100000000, 0 ,0 ,0 ,0, { from: account1 })).logs[0].args._orderId;

    // console.log(orderId);
    //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
    truffleAssertions.fails(
      morpherOracle.__callback(
        orderId,
        roundToInteger(150),
        roundToInteger(150),
        0,
        0,
        0,
        0,
        { from: account0 },
      ),
      truffleAssertions.ErrorType.REVERT,
      'MorpherTradeEngine: User is blocked from Trading',
    )
  })

  it('test case 3: Unblocking works for trading', async () => {
    let account0 = accounts[0]
    let account1 = accounts[1]

    let morpherTradeEngine = await MorpherTradeEngine.deployed()
    let morpherToken = await MorpherToken.deployed()
    let morpherState = await MorpherState.deployed()
    let morpherOracle = await MorpherOracle.deployed()
    let morpherUserBlocking = await MorpherUserBlocking.deployed()
    truffleAssertions.eventEmitted(
      await morpherUserBlocking.setUserBlocked(account1, false),
      'ChangeUserBlocked',
    )

    //(_marketId, _closeSharesAmount, _openMPHAmount, _tradeDirection, _orderLeverage, _onlyIfPriceAbove, _onlyIfPriceBelow, _goodUntil, _goodFrom)
    let orderId = (await morpherOracle.createOrder(BTC, 0, roundToInteger(20), false, 100000000, 0 ,0 ,0 ,0, { from: account1 })).logs[0].args._orderId;

    await morpherOracle.__callback(orderId, roundToInteger(10), roundToInteger(10), 0, 0, 0, 0, { from: account0 });

    // (address _address, bytes32 _marketId)
    let position = await morpherState.getPosition(account1, BTC);

    // shortShareValue( _positionAveragePrice, _positionAverageLeverage, _liquidationPrice, _marketPrice, _marketSpread, _orderLeverage, _sell)
    let positionValue = position._shortShares.toNumber() *
        (await morpherTradeEngine.shortShareValue(position._meanEntryPrice.toNumber(),
        position._meanEntryLeverage.toNumber(), 0, 
            roundToInteger(10), 0, 100000000, true)).toNumber();

    let userBalance = (await morpherState.balanceOf(account1)).toString();

    assert.equal(positionValue, roundToInteger(20));

    assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(10));
    assert.equal(position._longShares.toNumber(), 0);
    assert.equal(position._shortShares.toNumber(), 2);

    assert.equal(userBalance, startingBalance.sub(new BN(roundToInteger(40))).toString());
  })
})



contract('MorpherStaking: increase/decrease staked amount', (accounts) => {
    const [deployer, account1] = accounts;

    it('unblocked user: staking is possible', async () => {


        const token = await MorpherToken.deployed();
        const staking = await MorpherStaking.deployed();
        await staking.setLockupPeriodRate(0);
        await token.transfer(account1, web3.utils.toWei('10000000', 'ether'), { from: deployer }); //fill up some tokens
        let result = await staking.stake(web3.utils.toWei('1000000', 'ether'), { from: account1 });
        await truffleAssertions.eventEmitted(result, 'Staked');

    });
    it('blocked user: staking/unstaking is impossible', async () => {
        let morpherUserBlocking = await MorpherUserBlocking.deployed()
        truffleAssertions.eventEmitted(
          await morpherUserBlocking.setUserBlocked(account1, true),
          'ChangeUserBlocked',
        )
        const staking = await MorpherStaking.deployed();
        
        await truffleAssertions.fails(staking.stake(web3.utils.toWei('100000', 'ether'), { from: account1 }), truffleAssertions.ErrorType.REVERT, "MorpherStaking: User is blocked");

        await truffleAssertions.fails(staking.unstake(1, {from: account1}), truffleAssertions.ErrorType.REVERT, "MorpherStaking: User is blocked");
    });
    
    it('unblocked user: unstaking is impossible', async () => {
        let morpherUserBlocking = await MorpherUserBlocking.deployed()
        truffleAssertions.eventEmitted(
          await morpherUserBlocking.setUserBlocked(account1, false),
          'ChangeUserBlocked',
        )
        const staking = await MorpherStaking.deployed();
        
        result = await staking.unstake(1, { from: account1 });
        await truffleAssertions.eventEmitted(result, 'Unstaked', (ev) => {
            return ev.userAddress === account1 && ev.amount.toString() === '100000000' && ev.poolShares.toString() === '1';
        });
    });
});