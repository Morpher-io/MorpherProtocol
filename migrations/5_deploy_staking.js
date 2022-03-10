const MorpherState = artifacts.require("MorpherState");
const MorpherStaking = artifacts.require("MorpherStaking");
const MorpherUserBlocking = artifacts.require("MorpherUserBlocking");
const MorpherToken = artifacts.require("MorpherToken");
const MorpherAccessControl = artifacts.require("MorpherAccessControl");

module.exports = async function (deployer, network, accounts) {
  

  try {
    const morpherStaking = await MorpherStaking.deployed();

    await upgradeProxy(morpherStaking.address, MorpherStaking, {
      deployer,
    });
  } catch (e) {
    if (
      e.message !=
      "MorpherToken has not been deployed to detected network (network/artifact mismatch)"
    ) {
      throw e;
    }
    
    const ownerAddress = process.env.MORPHER_OWNER || accounts[0];

    const morpherUserBlocking = await MorpherUserBlocking.deployed();
    const morpherState = await MorpherState.deployed();
    await deployProxy(
      MorpherStaking,
      [morpherState.address, ownerAddress, morpherUserBlocking.address],
      {
        deployer,
      }
    ); // deployer is changed to owner later

    const morpherStaking = await MorpherStaking.deployed();
    
    const morpherAccessControl = await MorpherAccessControl.deployed();

    /**
     * Grant the Token access
     */
    await morpherState.grantAccess(MorpherStaking.address);
    await morpherState.grantAccess(ownerAddress);

    await morpherAccessControl.grantRole(
      await morpherToken.BURNER_ROLE(),
      morpherStaking.address
    );
    await morpherAccessControl.grantRole(
      await morpherToken.MINTER_ROLE(),
      morpherStaking.address
    );
  }
};
