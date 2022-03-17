const AdminOverrideProxy = artifacts.require('MorpherAdministratorProxy.sol')
const MorpherState = artifacts.require('MorpherState')
const MorpherAccessControl = artifacts.require("MorpherAccessControl");

module.exports = async function (deployer, network, accounts) {
  const morpherState = await MorpherState.deployed();

  if (network !== 'mainchain') {
    await deployer.deploy(
      AdminOverrideProxy,
      accounts[0],
      morpherState.address,
    )
    const morpherAccessControl = await MorpherAccessControl.deployed();
   
    const marketHashObject = require('../docs/markets')

    const marketHashes = Object.keys(marketHashObject)
    const adminOverrideProxy = await AdminOverrideProxy.deployed()
    await morpherAccessControl.grantRole(
      await morpherState.ADMINISTRATOR_ROLE(),
      adminOverrideProxy.address
    );
    let marketsToAdd = []
    for (let i = 0; i < marketHashes.length; i++) {
      marketsToAdd.push(marketHashes[i])
      if (marketsToAdd.length == 20) {
        await adminOverrideProxy.bulkActivateMarkets(marketsToAdd)
        marketsToAdd = []
        console.log('Added 20 Markets')
      }
    }
    if (marketsToAdd.length > 0) {
      await adminOverrideProxy.bulkActivateMarkets(marketsToAdd)
      console.log('Added', marketsToAdd.length, 'Markets')
      marketsToAdd = []
    }

    await morpherAccessControl.revokeRole(
      await morpherState.ADMINISTRATOR_ROLE(),
      adminOverrideProxy.address
    );

  }
}
