const MorpherState = artifacts.require("MorpherState");
const MorpherMintingLimiter = artifacts.require("MorpherMintingLimiter");
const MorpherAccessControl = artifacts.require("MorpherAccessControl");
const MorpherToken = artifacts.require("MorpherToken");

module.exports = async function (deployer, network, accounts) {
  const mintLimitPerUser = process.env.MINTING_LIMIT_PER_USER || 0;
  const mintLimitDaily = process.env.MINTING_LIMIT_DAILY || 0;
  const timelockPeriodMinting = process.env.MINTING_TIME_LOCK_PERIOD || 0;

  const morpherState = await MorpherState.deployed();
 
  await deployer.deploy(
    MorpherMintingLimiter,
    morpherState.address,
    mintLimitPerUser,
    mintLimitDaily,
    timelockPeriodMinting
  );
  const morpherMintingLimiter = await MorpherMintingLimiter.deployed();

  await morpherState.setMorpherMintingLimiter(morpherMintingLimiter.address);

  /**
   * Allow the minting limiter to actually mint
   */
  const morpherAccessControl = await MorpherAccessControl.deployed();
  const morpherToken = await MorpherToken.deployed();

  await morpherAccessControl.grantRole(await morpherToken.MINTER_ROLE(),morpherMintingLimiter.address);

};
