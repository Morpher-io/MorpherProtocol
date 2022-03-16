const MorpherUserBlocking = artifacts.require("MorpherUserBlocking");
const MorpherState = artifacts.require("MorpherState");
const { deployProxy, upgradeProxy } = require("@openzeppelin/truffle-upgrades");

module.exports = async function (deployer, network, accounts) {

  try {
    const morpherUserBlocking = await MorpherUserBlocking.deployed();

    await upgradeProxy(morpherUserBlocking.address, MorpherUserBlocking, {
      deployer,
    });
  } catch (e) {
    const morpherState = await MorpherState.deployed();

    if (
      e.message !=
      "MorpherUserBlocking has not been deployed to detected network (network/artifact mismatch)"
    ) {
      throw e;
    }
    await deployProxy(
      MorpherUserBlocking,
      [morpherState.address],
      { deployer }
    ); // deployer is changed to owner later

    const morpherUserBlocking = await MorpherUserBlocking.deployed();
    await morpherState.setMorpherUserBlocking(morpherUserBlocking.address);

  }
};
