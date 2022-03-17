const MorpherState = artifacts.require("MorpherState");
const MorpherStaking = artifacts.require("MorpherStaking");
const MorpherAccessControl = artifacts.require("MorpherAccessControl");
const MorpherToken = artifacts.require("MorpherToken");

const { deployProxy, upgradeProxy } = require("@openzeppelin/truffle-upgrades");


module.exports = async function (deployer, network, accounts) {
  

  try {
    const morpherStaking = await MorpherStaking.deployed();

    await upgradeProxy(morpherStaking.address, MorpherStaking, {
      deployer,
    });
  } catch (e) {
    if (
      e.message !=
      "MorpherStaking has not been deployed to detected network (network/artifact mismatch)"
    ) {
      throw e;
    }
    
    const morpherState = await MorpherState.deployed();
    await deployProxy(
      MorpherStaking,
      [morpherState.address],
      {
        deployer,
      }
    ); // deployer is changed to owner later

    const morpherStaking = await MorpherStaking.deployed();
    
    const morpherAccessControl = await MorpherAccessControl.deployed();
    const morpherToken = await MorpherToken.deployed();

    /**
     * Grant the Token access
     */

    await morpherAccessControl.grantRole(
      await morpherStaking.STAKINGADMIN_ROLE(),
      accounts[0]
    );
    await morpherStaking.addInterestRate(15000,1617094819); //setting the initial interest rate to the trade engine deployed timestamp

    await morpherAccessControl.grantRole(
      await morpherToken.BURNER_ROLE(),
      morpherStaking.address
    );
    await morpherAccessControl.grantRole(
      await morpherToken.MINTER_ROLE(),
      morpherStaking.address
    );

    morpherState.setMorpherStaking(morpherStaking.address);
  }
};
