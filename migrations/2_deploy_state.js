const { deployProxy, upgradeProxy } = require("@openzeppelin/truffle-upgrades");
const MorpherState = artifacts.require("MorpherState");
const MorpherAccessControl = artifacts.require("MorpherAccessControl");

module.exports = async function (deployer, network, accounts) {
  
  const treasuryAddress = process.env.MORPHER_TREASURY || accounts[0];
  const sidechainOperatorAddress =
    process.env.SIDECHAIN_OPERATOR || accounts[0];

  let isMainChain = !process.env.SIDECHAIN || true;

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

  // const morpherAccessControl = await MorpherAccessControl.deployed();
  // await morpherAccessControl.grantRole(
  //   ADMINISTRATOR_ROLE,
  //   accounts[0]
  // );

  

  try {
    const morpherState = await MorpherState.deployed();

    await upgradeProxy(morpherState.address, MorpherState, { deployer });
  } catch (e) {
    if (
      e.message !=
      "MorpherState has not been deployed to detected network (network/artifact mismatch)"
    ) {
      throw e;
    }
    await deployProxy(
      MorpherState,
      [isMainChain, sidechainOperatorAddress, treasuryAddress],
      { deployer }
    ); // deployer is changed to owner later
  }

  // const morpherState = await MorpherState.deployed();
  // /**
  //  * Sidechain relevant settings
  //  */
  // if (!isMainChain) {
  //   await morpherState.enableTransfers(ownerAddress);
  //   await morpherState.grantAccess(ownerAddress);
  // }

  // await morpherState.setSideChainOperator(ownerAddress);
};
