const MorpherUserBlocking = artifacts.require('MorpherUserBlocking')
const MorpherState = artifacts.require('MorpherState')

module.exports = async function (deployer, network, accounts) {
  const morpherState = await MorpherState.deployed()
  await deployer.deploy(
    MorpherUserBlocking,
    morpherState.address
  ) 
}
