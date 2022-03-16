const { deployProxy, upgradeProxy } = require("@openzeppelin/truffle-upgrades");
const MorpherAccessControl = artifacts.require("MorpherAccessControl");

module.exports = async function (deployer, network, accounts) {

  try {
    const morpherAccessControl = await MorpherAccessControl.deployed();
    await upgradeProxy(morpherAccessControl.address, MorpherAccessControl, {
      deployer,
    });
  } catch (e) {
    if (
      e.message !=
      "MorpherAccessControl has not been deployed to detected network (network/artifact mismatch)"
    ) {
      throw e;
    }
    await deployProxy(MorpherAccessControl, [], { deployer }); // deployer is changed to owner later
  }

};
