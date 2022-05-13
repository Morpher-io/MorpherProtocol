const { deployProxy, upgradeProxy } = require("@openzeppelin/truffle-upgrades");
const MorpherState = artifacts.require("MorpherState");
const MorpherAccessControl = artifacts.require("MorpherAccessControl");

module.exports = async function (deployer, network, accounts) {
  //const treasuryAddress = process.env.MORPHER_TREASURY || accounts[0];
  // const sidechainOperatorAddress =
  //   process.env.SIDECHAIN_OPERATOR || accounts[0];

  let isMainChain = !process.env.SIDECHAIN || true;

  try {
    const morpherState = await MorpherState.deployed();

    await upgradeProxy(morpherState.address, MorpherState, { deployer });
  } catch (e) {
    const morpherAccessControl = await MorpherAccessControl.deployed();
    await morpherAccessControl.grantRole(
      web3.utils.sha3("ADMINISTRATOR_ROLE"),
      accounts[0]
    );
    await morpherAccessControl.grantRole(
      web3.utils.sha3("GOVERNANCE_ROLE"),
      accounts[0]
    );
    if (
      e.message !=
      "MorpherState has not been deployed to detected network (network/artifact mismatch)"
    ) {
      throw e;
    }
    await deployProxy(
      MorpherState,
      [isMainChain, morpherAccessControl.address],
      { deployer }
    ); // deployer is changed to owner later
    
  }
};
