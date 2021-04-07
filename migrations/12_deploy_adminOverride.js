const AdminOverrideProxy = artifacts.require('MorpherAdministratorProxy.sol')
const MorpherState = artifacts.require('MorpherState')

module.exports = async function (deployer, network, accounts) {
  const administratorAddress = process.env.MORPHER_ADMINISTRATOR || accounts[0]

  const morpherState = await MorpherState.deployed()
  if (network !== 'mainchain' && network !== 'kovan') {
    await deployer.deploy(
      AdminOverrideProxy,
      administratorAddress,
      morpherState.address
    )
    
    await morpherState.setAdministrator(AdminOverrideProxy.address);
  }
}
