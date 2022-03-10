const MorpherState = artifacts.require("MorpherState");
const MorpherTradeEngine = artifacts.require("MorpherTradeEngine");
const MorpherStaking = artifacts.require("MorpherStaking");
const MorpherMintingLimiter = artifacts.require("MorpherMintingLimiter");
const MorpherUserBlocking = artifacts.require("MorpherUserBlocking");
const MorpherToken = artifacts.require("MorpherToken");
const MorpherAccessControl = artifacts.require("MorpherAccessControl");

module.exports = async function (deployer, network, accounts) {
  const ownerAddress = process.env.MORPHER_OWNER || accounts[0];
  const mintLimitPerUser = process.env.MINTING_LIMIT_PER_USER || 0;
  const mintLimitDaily = process.env.MINTING_LIMIT_DAILY || 0;
  const timelockPeriodMinting = process.env.MINTING_TIME_LOCK_PERIOD || 0;

  const morpherState = await MorpherState.deployed();
  const morpherUserBlocking = await MorpherUserBlocking.deployed();
  let deployedTimestamp = 1613399217;
  if (network == "local" || network == "test") {
    deployedTimestamp = Math.round(Date.now() / 1000) - 60 * 60 * 24 * 30 * 5; //settings this for testing 5 months back
  }
  await deployer.deploy(
    MorpherMintingLimiter,
    morpherState.address,
    mintLimitPerUser,
    mintLimitDaily,
    timelockPeriodMinting
  );
  const morpherMintingLimiter = await MorpherMintingLimiter.deployed();
  await deployer.deploy(
    MorpherTradeEngine,
    morpherState.address,
    ownerAddress,
    MorpherStaking.address,
    true,
    deployedTimestamp,
    morpherMintingLimiter.address,
    morpherUserBlocking.address
  );

  const tradeEngine = await MorpherTradeEngine.deployed();
  await morpherMintingLimiter.setTradeEngineAddress(tradeEngine.address);
  const morpherToken = await MorpherToken.deployed();

  /**
   * Grant the Token access
   */
  await morpherState.grantAccess(tradeEngine.address);
  await morpherState.grantAccess(morpherMintingLimiter.address);
  // await morpherState.enableTransfers(tradeEngine.address);
  // await morpherState.enableTransfers(morpherMintingLimiter.address);

  const morpherAccessControl = await MorpherAccessControl.deployed();
  await morpherAccessControl.grantRole(
    await morpherToken.BURNER_ROLE(),
    tradeEngine.address
  );
  await morpherAccessControl.grantRole(
    await morpherToken.MINTER_ROLE(),
    morpherMintingLimiter.address
  );
};
