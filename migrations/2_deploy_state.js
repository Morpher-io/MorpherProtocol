const MorpherState = artifacts.require('MorpherState')

module.exports = async function (deployer, network, accounts) {
  const ownerAddress = process.env.MORPHER_OWNER || accounts[0]
  const treasuryAddress = process.env.MORPHER_TREASURY || accounts[0]
  const sidechainOperatorAddress = process.env.SIDECHAIN_OPERATOR || accounts[0]

  let isMainChain = false
  if (network === 'mainchain' || network === 'kovan' || network == 'test' || network == "develop") {
    isMainChain = true
  }

  await deployer.deploy(
    MorpherState,
    isMainChain,
    sidechainOperatorAddress,
    treasuryAddress,
  ) // deployer is changed to owner later

  const morpherState = await MorpherState.deployed()

  /**
   * Sidechain relevant settings
   */
  if (!isMainChain) {
    await morpherState.enableTransfers(ownerAddress)
    await morpherState.grantAccess(ownerAddress)
  }

  await morpherState.setSideChainOperator(ownerAddress)
}
