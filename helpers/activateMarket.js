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
module.exports = async function (MorpherAdministratorProxy) {
  const marketHashObject = require('../docs/markets')

  const marketHashes = Object.keys(marketHashObject)
  const adminOverrideProxy = await MorpherAdministratorProxy.deployed()
  let marketsToAdd = []
  for (let i = 0; i < marketHashes.length; i++) {
    marketsToAdd.push(marketHashes[i])
    if (marketsToAdd.length == 20) {
      await adminOverrideProxy.bulkActivateMarkets(marketsToAdd, {
        from: accounts[0],
      })
      marketsToAdd = []
      console.log('Added 20 Markets')
    }
  }
  if (marketsToAdd.length > 0) {
    await adminOverrideProxy.bulkActivateMarkets(marketsToAdd, {
      from: accounts[0],
    })
    console.log('Added', marketsToAdd.length, 'Markets')
    marketsToAdd = []
  }
}
