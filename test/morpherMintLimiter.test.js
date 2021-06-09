const truffleAssert = require('truffle-assertions')

const MorpherToken = artifacts.require('MorpherToken')
const MorpherTradeEngine = artifacts.require('MorpherTradeEngine')
const MorpherState = artifacts.require('MorpherState')
const MorpherOracle = artifacts.require('MorpherOracle')
const MorpherMintingLimiter = artifacts.require('MorpherMintingLimiter')

let BTC = '0x0bc89e95f9fdaab7e8a11719155f2fd638cb0f665623f3d12aab71d1a125daf9'

function roundToInteger(price) {
  return Math.round(price * Math.pow(10, 8))
}

const BN = require('bn.js')

contract(
  'MorpherMintingLimiter: Trades with and without minting limiter',
  (accounts) => {
    const [callbackAccount, tradeAccount] = accounts

    it('No Minting Limit Set - No Escrow happens', async () => {
      let morpherTradeEngine = await MorpherTradeEngine.deployed()
      let morpherToken = await MorpherToken.deployed()
      let morpherState = await MorpherState.deployed()
      let morpherOracle = await MorpherOracle.deployed()
      let morpherMintingLimiter = await MorpherMintingLimiter.deployed()

      const startingBalance = web3.utils.toWei(new BN(1), 'ether')
      assert.equal(
        (await morpherMintingLimiter.mintingLimitDaily()).toString(),
        '0',
        'Morpher Minting Limit is not 0',
      )
      assert.equal(
        (await morpherMintingLimiter.mintingLimitPerUser()).toString(),
        '0',
        'Morpher Minting Limit is not 0',
      )

      // Set balance of testing account.
      //(address to, uint256 tokens)
      await morpherToken.transfer(tradeAccount, startingBalance)

      //open an order and make it super successful
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
          { from: tradeAccount },
        )
      ).logs[0].args._orderId
      await morpherOracle.__callback(
        orderId,
        roundToInteger(150),
        roundToInteger(150),
        0,
        0,
        0,
        0,
        { from: callbackAccount },
      )
      let position = await morpherState.getPosition(tradeAccount, BTC)

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

      let userBalance = (await morpherState.balanceOf(tradeAccount)).toString()

      assert.equal(positionValue, roundToInteger(300))
      assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(150))
      assert.equal(position._longShares.toNumber(), 2)
      assert.equal(position._shortShares.toNumber(), 0)
      assert.equal(
        userBalance,
        startingBalance.sub(new BN(roundToInteger(300))).toString(),
      )

      orderId = (
        await morpherOracle.createOrder(
          BTC,
          2,
          0,
          false,
          100000000,
          0,
          0,
          0,
          0,
          { from: tradeAccount },
        )
      ).logs[0].args._orderId
      let txResult = await morpherOracle.__callback(
        orderId,
        roundToInteger(15000),
        roundToInteger(15000),
        0,
        0,
        0,
        0,
        { from: callbackAccount },
      )
      await truffleAssert.eventNotEmitted(txResult, 'MintingEscrowed')

      userBalance = (await morpherState.balanceOf(tradeAccount)).toString()
      assert(userBalance > startingBalance.toString())
      let escrowedAmount = await morpherMintingLimiter.escrowedTokens(
        tradeAccount,
      )
      assert.equal(escrowedAmount.toString(), '0')
    })
    it('Minting Limit Per User Set, self delayed minting', async () => {
      let morpherTradeEngine = await MorpherTradeEngine.deployed()
      let morpherToken = await MorpherToken.deployed()
      let morpherState = await MorpherState.deployed()
      let morpherOracle = await MorpherOracle.deployed()
      let morpherMintingLimiter = await MorpherMintingLimiter.deployed()

      const startingBalance = await morpherState.balanceOf(tradeAccount)

      //set minting limit to 1 MPH
      assert.equal(
        (await morpherMintingLimiter.mintingLimitPerUser()).toString(),
        '0',
        'Morpher Minting Limit is not 0',
      )
      await morpherMintingLimiter.setMintingLimitPerUser(
        web3.utils.toWei('1', 'ether'),
      )
      assert.equal(
        (await morpherMintingLimiter.mintingLimitPerUser()).toString(),
        web3.utils.toWei('1', 'ether'),
        'Morpher Minting Limit is not 1 MPH',
      )

      await morpherMintingLimiter.setTimeLockingPeriod(3) //set the time lock period to 3 seconds

      //open an order and make it super successful
      let orderId = (
        await morpherOracle.createOrder(
          BTC,
          0,
          web3.utils.toWei('1', 'ether'),
          true,
          100000000,
          0,
          0,
          0,
          0,
          { from: tradeAccount },
        )
      ).logs[0].args._orderId
      await morpherOracle.__callback(
        orderId,
        roundToInteger(150),
        roundToInteger(150),
        0,
        0,
        0,
        0,
        { from: callbackAccount },
      )
      let position = await morpherState.getPosition(tradeAccount, BTC)

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

      let userBalanceBeforeCallback = (
        await morpherState.balanceOf(tradeAccount)
      ).toString()

      assert.equal(positionValue, '999999990000000000')
      assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(150))
      assert.equal(position._longShares.toNumber(), 66666666)
      assert.equal(position._shortShares.toNumber(), 0)
      assert.equal(
        userBalanceBeforeCallback,
        startingBalance.sub(new BN('999999990000000000')).toString(),
      )

      orderId = (
        await morpherOracle.createOrder(
          BTC,
          66666666,
          0,
          false,
          100000000,
          0,
          0,
          0,
          0,
          { from: tradeAccount },
        )
      ).logs[0].args._orderId
      let txResult = await morpherOracle.__callback(
        orderId,
        roundToInteger(152),
        roundToInteger(152),
        0,
        0,
        0,
        0,
        { from: callbackAccount },
      )

      let event = txResult.receipt.rawLogs.some((l) => {
        return (
          l.topics[0] == web3.utils.sha3('MintingEscrowed(address,uint256)')
        )
      })
      assert.ok(event, 'MintingEscrowed event not emitted')

      let userBalanceAfterCallback = (
        await morpherState.balanceOf(tradeAccount)
      ).toString()
      assert(
        userBalanceBeforeCallback == userBalanceAfterCallback,
        'amount was not escrowed',
      )
      let escrowedAmount = await morpherMintingLimiter.escrowedTokens(
        tradeAccount,
      )
      assert.equal(
        escrowedAmount.toString(),
        '1013333323200000000',
        'The minted amount should be in escrow',
      )

      await truffleAssert.fails(
        morpherMintingLimiter.delayedMint(tradeAccount, { from: tradeAccount }),
      )

      await new Promise((resolve) => setTimeout(resolve, 4000))
      let txMint = await morpherMintingLimiter.delayedMint(tradeAccount, {
        from: tradeAccount,
      })
      await truffleAssert.eventEmitted(txMint, 'EscrowReleased')
      userBalance = (await morpherState.balanceOf(tradeAccount)).toString()
      assert(
        userBalance > startingBalance.toString(),
        'amount was not escrowed',
      )
      escrowedAmount = await morpherMintingLimiter.escrowedTokens(tradeAccount)
      assert.equal(escrowedAmount.toString(), '0', '0 MPH should be in escrow')
    })

    it('Minting Limit Set, administrator minting', async () => {
      let morpherTradeEngine = await MorpherTradeEngine.deployed()
      let morpherState = await MorpherState.deployed()
      let morpherOracle = await MorpherOracle.deployed()
      let morpherMintingLimiter = await MorpherMintingLimiter.deployed()

      const startingBalance = await morpherState.balanceOf(tradeAccount)

      //open an order and make it super successful
      let orderId = (
        await morpherOracle.createOrder(
          BTC,
          0,
          web3.utils.toWei('1', 'ether'),
          true,
          100000000,
          0,
          0,
          0,
          0,
          { from: tradeAccount },
        )
      ).logs[0].args._orderId
      await morpherOracle.__callback(
        orderId,
        roundToInteger(150),
        roundToInteger(150),
        0,
        0,
        0,
        0,
        { from: callbackAccount },
      )
      let position = await morpherState.getPosition(tradeAccount, BTC)

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

      let userBalanceBeforeCallback = (
        await morpherState.balanceOf(tradeAccount)
      ).toString()

      assert.equal(positionValue, '999999990000000000')
      assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(150))
      assert.equal(position._longShares.toNumber(), 66666666)
      assert.equal(position._shortShares.toNumber(), 0)
      assert.equal(
        userBalanceBeforeCallback,
        startingBalance.sub(new BN('999999990000000000')).toString(),
      )

      orderId = (
        await morpherOracle.createOrder(
          BTC,
          66666666,
          0,
          false,
          100000000,
          0,
          0,
          0,
          0,
          { from: tradeAccount },
        )
      ).logs[0].args._orderId
      let txResult = await morpherOracle.__callback(
        orderId,
        roundToInteger(152),
        roundToInteger(152),
        0,
        0,
        0,
        0,
        { from: callbackAccount },
      )

      let event = txResult.receipt.rawLogs.some((l) => {
        return (
          l.topics[0] == web3.utils.sha3('MintingEscrowed(address,uint256)')
        )
      })
      assert.ok(event, 'MintingEscrowed event not emitted')

      let userBalanceAfterCallback = (
        await morpherState.balanceOf(tradeAccount)
      ).toString()
      assert(
        userBalanceBeforeCallback == userBalanceAfterCallback,
        'amount was not escrowed',
      )
      let escrowedAmount = await morpherMintingLimiter.escrowedTokens(
        tradeAccount,
      )
      assert.equal(
        escrowedAmount.toString(),
        '1013333323200000000',
        'The minted amount should be in escrow',
      )

      let txMint = await morpherMintingLimiter.adminApprovedMint(
        tradeAccount,
        escrowedAmount.toString(),
        { from: callbackAccount },
      )
      await truffleAssert.eventEmitted(txMint, 'EscrowReleased')
      escrowedAmount = await morpherMintingLimiter.escrowedTokens(tradeAccount)
      assert.equal(escrowedAmount.toString(), '0', '0 MPH should be in escrow')
    })

    it('Minting Limit Set, administrator adminDisapproveMint', async () => {
      let morpherTradeEngine = await MorpherTradeEngine.deployed()
      let morpherState = await MorpherState.deployed()
      let morpherOracle = await MorpherOracle.deployed()
      let morpherMintingLimiter = await MorpherMintingLimiter.deployed()

      const startingBalance = await morpherState.balanceOf(tradeAccount)

      //open an order and make it super successful
      let orderId = (
        await morpherOracle.createOrder(
          BTC,
          0,
          web3.utils.toWei('1', 'ether'),
          true,
          100000000,
          0,
          0,
          0,
          0,
          { from: tradeAccount },
        )
      ).logs[0].args._orderId
      await morpherOracle.__callback(
        orderId,
        roundToInteger(150),
        roundToInteger(150),
        0,
        0,
        0,
        0,
        { from: callbackAccount },
      )
      let position = await morpherState.getPosition(tradeAccount, BTC)

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

      let userBalanceBeforeCallback = (
        await morpherState.balanceOf(tradeAccount)
      ).toString()

      assert.equal(positionValue, '999999990000000000')
      assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(150))
      assert.equal(position._longShares.toNumber(), 66666666)
      assert.equal(position._shortShares.toNumber(), 0)
      assert.equal(
        userBalanceBeforeCallback,
        startingBalance.sub(new BN('999999990000000000')).toString(),
      )

      orderId = (
        await morpherOracle.createOrder(
          BTC,
          66666666,
          0,
          false,
          100000000,
          0,
          0,
          0,
          0,
          { from: tradeAccount },
        )
      ).logs[0].args._orderId
      let txResult = await morpherOracle.__callback(
        orderId,
        roundToInteger(152),
        roundToInteger(152),
        0,
        0,
        0,
        0,
        { from: callbackAccount },
      )

      let event = txResult.receipt.rawLogs.some((l) => {
        return (
          l.topics[0] == web3.utils.sha3('MintingEscrowed(address,uint256)')
        )
      })
      assert.ok(event, 'MintingEscrowed event not emitted')

      let userBalanceAfterCallback = (
        await morpherState.balanceOf(tradeAccount)
      ).toString()
      assert(
        userBalanceBeforeCallback == userBalanceAfterCallback,
        'amount was not escrowed',
      )
      let escrowedAmount = await morpherMintingLimiter.escrowedTokens(
        tradeAccount,
      )
      assert.equal(
        escrowedAmount.toString(),
        '1013333323200000000',
        'The minted amount should be in escrow',
      )

      let txMint = await morpherMintingLimiter.adminDisapproveMint(
        tradeAccount,
        escrowedAmount.toString(),
        { from: callbackAccount },
      )
      await truffleAssert.eventEmitted(txMint, 'MintingDenied')
      escrowedAmount = await morpherMintingLimiter.escrowedTokens(tradeAccount)
      assert.equal(escrowedAmount.toString(), '0', '0 MPH should be in escrow')

      assert.equal(
        userBalanceBeforeCallback,
        (await morpherState.balanceOf(tradeAccount)).toString(),
        'The user got Tokens although we denied tokens',
      )
    })

    it('Minting Limit Daily Set, administrator approved', async () => {
      let morpherTradeEngine = await MorpherTradeEngine.deployed()
      let morpherState = await MorpherState.deployed()
      let morpherOracle = await MorpherOracle.deployed()
      let morpherToken = await MorpherToken.deployed()
      let morpherMintingLimiter = await MorpherMintingLimiter.deployed()

      //set minting limit daily to 1 MPH
      assert.equal(
        (await morpherMintingLimiter.mintingLimitDaily()).toString(),
        '0',
        'Morpher Minting Limit is not 0',
      )
      await morpherMintingLimiter.setMintingLimitPerUser(
        web3.utils.toWei('100', 'ether'),
      )
      assert.equal(
        (await morpherMintingLimiter.mintingLimitPerUser()).toString(),
        web3.utils.toWei('100', 'ether'),
        'Morpher Minting Limit is not 100 MPH',
      )
      //set the daily limit
      await morpherMintingLimiter.setMintingLimitDaily(
        web3.utils.toWei('1', 'ether'),
      )
      assert.equal(
        (await morpherMintingLimiter.mintingLimitDaily()).toString(),
        web3.utils.toWei('1', 'ether'),
        'Morpher Minting Limit is not 1 MPH',
      )

      // Set balance of testing account.
      //(address to, uint256 tokens)
      await morpherToken.transfer(tradeAccount, web3.utils.toWei('1', 'ether'))

      const startingBalance = await morpherState.balanceOf(tradeAccount)

      //open an order and make it super successful
      let orderId = (
        await morpherOracle.createOrder(
          BTC,
          0,
          web3.utils.toWei('1', 'ether'),
          true,
          100000000,
          0,
          0,
          0,
          0,
          { from: tradeAccount },
        )
      ).logs[0].args._orderId
      await morpherOracle.__callback(
        orderId,
        roundToInteger(150),
        roundToInteger(150),
        0,
        0,
        0,
        0,
        { from: callbackAccount },
      )
      let position = await morpherState.getPosition(tradeAccount, BTC)

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

      let userBalanceBeforeCallback = (
        await morpherState.balanceOf(tradeAccount)
      ).toString()

      assert.equal(positionValue, '999999990000000000')
      assert.equal(position._meanEntryPrice.toNumber(), roundToInteger(150))
      assert.equal(position._longShares.toNumber(), 66666666)
      assert.equal(position._shortShares.toNumber(), 0)
      assert.equal(
        userBalanceBeforeCallback,
        startingBalance.sub(new BN('999999990000000000')).toString(),
      )

      orderId = (
        await morpherOracle.createOrder(
          BTC,
          66666666,
          0,
          false,
          100000000,
          0,
          0,
          0,
          0,
          { from: tradeAccount },
        )
      ).logs[0].args._orderId
      let txResult = await morpherOracle.__callback(
        orderId,
        roundToInteger(152),
        roundToInteger(152),
        0,
        0,
        0,
        0,
        { from: callbackAccount },
      )

      let event = txResult.receipt.rawLogs.some((l) => {
        return (
          l.topics[0] == web3.utils.sha3('MintingEscrowed(address,uint256)')
        )
      })
      assert.ok(event, 'MintingEscrowed event not emitted')

      let userBalanceAfterCallback = (
        await morpherState.balanceOf(tradeAccount)
      ).toString()
      assert(
        userBalanceBeforeCallback == userBalanceAfterCallback,
        'amount was not escrowed',
      )
      let escrowedAmount = await morpherMintingLimiter.escrowedTokens(
        tradeAccount,
      )
      assert.equal(
        escrowedAmount.toString(),
        '1013333323200000000',
        'The minted amount should be in escrow',
      )

      let txMint = await morpherMintingLimiter.adminApprovedMint(
        tradeAccount,
        escrowedAmount.toString(),
        { from: callbackAccount },
      )
      await truffleAssert.eventEmitted(txMint, 'EscrowReleased')
      escrowedAmount = await morpherMintingLimiter.escrowedTokens(tradeAccount)
      assert.equal(escrowedAmount.toString(), '0', '0 MPH should be in escrow')
    })
    
    it('Minting Limit Daily Reset, administrator approved', async () => {

      let morpherMintingLimiter = await MorpherMintingLimiter.deployed()

      //set minting limit daily to 1 MPH
      assert.equal(
        (await morpherMintingLimiter.mintingLimitDaily()).toString(),
        web3.utils.toWei('1', 'ether'),
        'Morpher Minting Limit is not 1 MPH',
      )

      let mintedTokensToday = await morpherMintingLimiter.getDailyMintedTokens();
      assert(mintedTokensToday.toNumber() > 0);

      let txResult = await morpherMintingLimiter.resetDailyMintedTokens();
      truffleAssert.eventEmitted(txResult, "DailyMintedTokensReset");

      let mintedTokensTodayAfterReset = await morpherMintingLimiter.getDailyMintedTokens();
      assert(mintedTokensTodayAfterReset.toNumber() == 0, "getDailyMintedTokens should be back to 0");

    })
  },
)
