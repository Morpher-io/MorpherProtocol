const MorpherUserBlocking = artifacts.require('MorpherUserBlocking')
const MorpherState = artifacts.require('MorpherState')

module.exports = async function (deployer, network, accounts) {
  let accountUserBlocking = process.env.ACCOUNT_USER_BLOCKING || accounts[0];
  const morpherState = await MorpherState.deployed()
  await deployer.deploy(
    MorpherUserBlocking,
    morpherState.address,
    accountUserBlocking
  ) 
}
