const MorpherState = artifacts.require('MorpherState')
const MorpherOracle = artifacts.require('MorpherOracle')
const MorpherTradeEngine = artifacts.require('MorpherTradeEngine')
const MorpherStaking = artifacts.require('MorpherStaking')

module.exports = async function (callback) {
  const accounts = await web3.eth.getAccounts()
  const [deployer, adminAccount] = accounts
  const ownerAddress = '0x720B9742632566b76B53B60Eee8d5FDC20aC74bE' //must be the same as the account that deploys the contract!
  console.log(deployer, adminAccount)
  const stateAddress = '0x52F74D95185f11a9A4885bFbDA77072Ff3CaaDCF'
  const morpherOracleAddress = '0xEBd036277a37034D77457042c473f9304fAa37fc'
  const oldStakingAddress = '0x2Ec8c0eB62f7191A27658C4E101061cE2a4F1447'
  let morpherStakingNew = await MorpherStaking.new(stateAddress, ownerAddress, {
    from: deployer,
  })
  console.log('New Morpher Staking', morpherStakingNew.address)

  let oldTradeEngineAddress = '0xa8C7039Db427549d3B4CB29cD1E23622dAb99a15'
  let oldTradeEngine = await MorpherTradeEngine.at(oldTradeEngineAddress)
  await oldTradeEngine.setMorpherStaking(morpherStakingNew.address)
  console.log('✅ Set the new Staking in old Trade Engine')

  const morpherMintingLimiterAddress =
    '0x52F74D95185f11a9A4885bFbDA77072Ff3CaaDCF' //set to state on dev

  let deployedTimestamp = 1613399217
  let tradeEngine = await MorpherTradeEngine.new(
    stateAddress,
    ownerAddress,
    morpherStakingNew.address,
    true,
    deployedTimestamp,
    morpherMintingLimiterAddress,
  )
  console.log('New Trade Engine', tradeEngine.address)

  // await morpherMintingLimiter.setTradeEngineAddress(tradeEngine.address); //on dev not necessary

  let morpherState = await MorpherState.at(stateAddress)
  await morpherState.grantAccess(tradeEngine.address, { from: adminAccount })
  console.log('✅ Granted access for new Trade Engine')
  await morpherState.enableTransfers(tradeEngine.address, {
    from: adminAccount,
  })
  console.log('✅ Granted Transfers for new Trade Engine')
  let morpherOracle = await MorpherOracle.at(morpherOracleAddress)
  await morpherOracle.setTradeEngineAddress(tradeEngine.address)
  console.log('✅ Set new Trade Engine in Oracle')

  await morpherState.grantAccess(morpherStakingNew.address, {
    from: adminAccount,
  })
  await morpherState.enableTransfers(morpherStakingNew.address, {
    from: adminAccount,
  })
  console.log('✅ Granted access for new Staking contract')
  //revoke the old staking contract access
  await morpherState.denyAccess(oldStakingAddress, { from: adminAccount })
  console.log('✅ Denied old staking access in stake')
  await morpherStakingNew.setMinimumStake(0)
  console.log('✅ Set minimum stake to 0')
  callback()
}
