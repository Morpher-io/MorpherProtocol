const MorpherToken = artifacts.require("MorpherToken");
const MorpherState = artifacts.require("MorpherState");
const MorpherOracle = artifacts.require("MorpherOracle");
const MorpherMigration = artifacts.require("MorpherAccountMigration");

let BTC = "0x0bc89e95f9fdaab7e8a11719155f2fd638cb0f665623f3d12aab71d1a125daf9";

const truffleAssert = require("truffle-assertions");

contract("MorpherAccountMigration", (accounts) => {
  it("test account migration with a single position", async () => {
    const [ deployerAddress, testAddress1, testAddress2 ] = accounts;

    const morpherToken = await MorpherToken.deployed();
    const morpherState = await MorpherState.deployed();
    const morpherOracle = await MorpherOracle.deployed();
    const morpherMigration = await MorpherMigration.deployed();

    // Set balance of testing account.
    //(address to, uint256 tokens)
    await morpherToken.transfer(testAddress1, web3.utils.toBN(Math.pow(10,18)), {from: deployerAddress});

    /**
     * Create a new order and then fullfil it so a position is created!
     */
    //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
    let orderId = (await morpherOracle.createOrder(BTC, true, 3, true, 100000000, {from: testAddress1, value: 301000000000000,})).logs[0].args._orderId;
    //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
    await morpherOracle.__callback(orderId, 150 * Math.pow(10,8), 0, 0, 0, {from: deployerAddress, });

    // (address _address, bytes32 _marketId)
    let positionBeforeMigration = await morpherState.getPosition(testAddress1, BTC);

    /**
     * allowance for token and allowance to migrate
     */
    await morpherMigration.allowMigrationFor12Hours(testAddress1, {from: testAddress2}); //"to" address needs to approve the merge
    await morpherToken.approve(morpherMigration.address, await morpherToken.balanceOf(testAddress1), {from: testAddress1}); //from address needs to allow the migrations smart contract to move the money
    let result = await morpherMigration.startMigrate(testAddress2, {from: testAddress1, gas: 8000000});
    console.log(result);

  });
});
