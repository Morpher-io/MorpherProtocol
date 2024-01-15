/**
 * how to use this?
 * 
 * truffle console --network YOURNETWORK
 * 
 * let activateMarket = require("./helpers/activateMarket");
 * activateMarket(MorpherAdministratorProxy);
 * 
 * that will fetch the markets from docs/markets.js and start bulk activating them, given the private key is in the .env file etc...
 */
module.exports = async function (callback) {
  const MorpherAdministratorProxy = artifacts.require("MorpherAdministratorProxy");
  const MorpherState = artifacts.require("MorpherState");
  const MorpherAccessControl = artifacts.require("MorpherAccessControl");

  const morpherAccessControl = await MorpherAccessControl.deployed();  
  const morpherState = await MorpherState.deployed();

  const adminOverrideProxy = await MorpherAdministratorProxy.deployed()
  await morpherAccessControl.grantRole(
    await morpherState.ADMINISTRATOR_ROLE(),
    adminOverrideProxy.address
  );
  const accounts = await web3.eth.getAccounts();
  console.log(accounts);
  const marketHashObject = require('../docs/markets.json')

  const marketHashes = Object.keys(marketHashObject)
  let marketsToAdd = []
  for (let i = 480; i < marketHashObject.length; i++) {
    marketsToAdd.push(web3.utils.sha3(marketHashObject[i].id))
    if (marketsToAdd.length == 40) {
      await adminOverrideProxy.bulkActivateMarkets(marketsToAdd, {
        from: accounts[0],
      })
      marketsToAdd = []
      console.log('Added 40 Markets')
    }
  }
  if (marketsToAdd.length > 0) {
    await adminOverrideProxy.bulkActivateMarkets(marketsToAdd, {
      from: accounts[0],
    })
    console.log('Added', marketsToAdd.length, 'Markets')
    marketsToAdd = []
  }
  await morpherAccessControl.revokeRole(
    await morpherState.ADMINISTRATOR_ROLE(),
    adminOverrideProxy.address
  );
}
