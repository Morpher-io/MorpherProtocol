const MorpherAdmin = artifacts.require('MorpherAdmin')

module.exports = async function (deployer, network, accounts) {
  
  if (network !== 'mainchain') {
    await deployer.deploy(
      MorpherAdmin,
      process.env.MORPHER_STATE_ADDRESS,
      process.env.MORPHER_TRADE_ENGINE_ADDRESS
    )

  }
}
