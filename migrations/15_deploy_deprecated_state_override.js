const MorpherAccessControl = artifacts.require("MorpherAccessControl");
const MorpherDeprecatedTokenMapper = artifacts.require("MorpherDeprecatedTokenMapper");
const MorpherState = artifacts.require("MorpherState");
const MorpherBridge = artifacts.require("MorpherBridge");

const { deployProxy, upgradeProxy } = require("@openzeppelin/truffle-upgrades");

module.exports = async function (deployer, network, accounts) {
  
  const morpherAccessControl = await MorpherAccessControl.deployed();
  const morpherState = await MorpherState.deployed();
  try {
    const morpherDeprecatedTokenMapper = await MorpherDeprecatedTokenMapper.deployed();

    await upgradeProxy(morpherDeprecatedTokenMapper.address, MorpherDeprecatedTokenMapper, {
      deployer,
    });
  } catch (e) {
    if (
      e.message !=
      "MorpherDeprecatedTokenMapper has not been deployed to detected network (network/artifact mismatch)"
    ) {
      throw e;
    }
    await deployProxy(MorpherDeprecatedTokenMapper, [morpherState.address], {
      deployer,
    }); // deployer is changed to owner later

   
    const morpherDeprecatedTokenMapper = await MorpherDeprecatedTokenMapper.deployed();
    const morpherBridge = await MorpherBridge.deployed();
    const oldState = "0x1f426C51F0Ef7655A6f4c3Eb58017d2F1c381bfF";

    await morpherAccessControl.grantRole(
      await morpherDeprecatedTokenMapper.MINTER_ROLE(),
      morpherBridge.address
    );
    await morpherAccessControl.grantRole(
      await morpherDeprecatedTokenMapper.BURNER_ROLE(),
      morpherBridge.address
    );

    await morpherDeprecatedTokenMapper.updateDeprecatedMorpherStateAddress(oldState);

    // /**
    //  * configure State
    //  */
    await morpherState.setMorpherToken(morpherDeprecatedTokenMapper.address);
  }
};
