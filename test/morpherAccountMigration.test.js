const MorpherToken = artifacts.require("MorpherToken");
const MorpherState = artifacts.require("MorpherState");
const MorpherOracle = artifacts.require("MorpherOracle");
const MorpherMigration = artifacts.require("MorpherAccountMigration");

const markets = require("../markets.json");

const truffleAssert = require("truffle-assertions");

contract("MorpherAccountMigration", (accounts) => {
  // it("test account migration with a single position", async () => {
  //   const [ deployerAddress, testAddress1, testAddress2 ] = accounts;

  //   const morpherToken = await MorpherToken.deployed();
  //   const morpherState = await MorpherState.deployed();
  //   const morpherOracle = await MorpherOracle.deployed();
  //   const morpherMigration = await MorpherMigration.deployed();

  //   // Set balance of testing account.
  //   //(address to, uint256 tokens)
  //   await morpherToken.transfer(testAddress1, web3.utils.toBN(Math.pow(10,18)), {from: deployerAddress});

  //   /**
  //    * Create a new order and then fullfil it so a position is created!
  //    */
  //   //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
  //   //CRYPTO_BTC Market is already active from deploy_oracle.js migration
  //   let orderId = (await morpherOracle.createOrder(web3.utils.sha3("CRYPTO_BTC"), true, 3, true, 100000000, {from: testAddress1,})).logs[0].args._orderId;
  //   //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
  //   await morpherOracle.__callback(orderId, 100, 0, 0, 0, {from: deployerAddress, });

  //   // (address _address, bytes32 _marketId)
  //   //let positionBeforeMigration = await morpherState.getPosition(testAddress1, BTC);

  //   /**
  //    * allowance for token and allowance to migrate
  //    */
  //   await morpherMigration.allowMigrationFor12Hours(testAddress1, {from: testAddress2}); //"to" address needs to approve the merge
  //   await morpherToken.approve(morpherMigration.address, await morpherToken.balanceOf(testAddress1), {from: testAddress1}); //from address needs to allow the migrations smart contract to move the money
  //   let result = await morpherMigration.startMigrate(testAddress2, {from: testAddress1, gas: 8000000});
  //   assert.equal(result.logs.length, 3, "There are more than 3 logs in the array");
  //   assert.equal(result.logs[2].event, "MigrationComplete", "Migration was not completed");

  // });

  it("test account migration with a all positions", async () => {
    const [
      deployerAddress,
      testAddress1,
      testAddress2,
      testAddress3,
      testAddress4,
    ] = accounts;
    let currentBlockGasLimit = (await web3.eth.getBlock("latest")).gasLimit;
    console.log(currentBlockGasLimit);
    const morpherToken = await MorpherToken.deployed();
    const morpherState = await MorpherState.deployed();
    const morpherOracle = await MorpherOracle.deployed();
    const morpherMigration = await MorpherMigration.deployed();

    // Set balance of testing account. Add 2 Ether
    //(address to, uint256 tokens)
    await morpherToken.transfer(
      testAddress3,
      web3.utils.toBN(2 * Math.pow(10, 18)),
      { from: deployerAddress }
    );

    for (let i = 0; i < markets.length; i++) {
      let marketHash = web3.utils.sha3(markets[i]);
      /**
       * Create a new orders and then fullfil it so a position is created!
       */
      //await morpherState.activateMarket(marketHash, {from: deployerAddress});
      console.log("Enabled Market " + markets[i]);
      //(_marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage)
      let orderId = (
        await morpherOracle.createOrder(marketHash, true, 1, true, 100000000, {
          from: testAddress3,
        })
      ).logs[0].args._orderId;
      console.log("Created Order " + orderId);
      //(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp)
      await morpherOracle.__callback(orderId, 1000, 0, 0, 0, {
        from: deployerAddress,
      });
      console.log("Order fulfilled");
      //if(i == 10) { break; }
    }

    

    /**
     * allowance for token and allowance to migrate
     */
    await morpherMigration.allowMigrationFor12Hours(testAddress3, {
      from: testAddress4,
    }); //"to" address needs to approve the merge
    await morpherToken.approve(
      morpherMigration.address,
      await morpherToken.balanceOf(testAddress3),
      { from: testAddress3 }
    ); //from address needs to allow the migrations smart contract to move the money
    currentBlockGasLimit = (await web3.eth.getBlock("latest")).gasLimit;
    console.log("Current Block Gas Limit:" + currentBlockGasLimit);
    let result = await morpherMigration.startMigrate(testAddress4, {
      from: testAddress3,
      gas: currentBlockGasLimit,
    });
    let i = 1;
    while (result.logs[result.logs.length - 1].event == "MigrationIncomplete") {
      console.log("Migration Round No: " + i);
      console.log("Number of events: " + result.logs.length);
      currentBlockGasLimit = (await web3.eth.getBlock("latest")).gasLimit;
      console.log("Current Block Gas Limit:" + currentBlockGasLimit);
      i++;
      result = await morpherMigration.startMigrate(testAddress4, {
        from: testAddress3,
        gas: currentBlockGasLimit,
      });
    }
    console.log("Migration Round No: " + i);
    console.log("Number of events: " + result.logs.length);
  }).timeout(3600000);
});
