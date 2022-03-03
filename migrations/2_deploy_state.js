const { deployProxy, upgradeProxy } = require("@openzeppelin/truffle-upgrades");
const { deploy } = require("@openzeppelin/truffle-upgrades/dist/utils");
const MorpherState = artifacts.require("MorpherState");

module.exports = async function (deployer, network, accounts) {
  const ownerAddress = process.env.MORPHER_OWNER || accounts[0];
  const treasuryAddress = process.env.MORPHER_TREASURY || accounts[0];
  const sidechainOperatorAddress =
    process.env.SIDECHAIN_OPERATOR || accounts[0];

  let isMainChain = false;
  if (
    network === "mainchain" ||
    network === "kovan" ||
    network == "test" ||
    network == "local" ||
    network == "develop"
  ) {
    isMainChain = true;
  }

  const morpherState = await MorpherState.deployed();

  if (morpherState.address) {
    await upgradeProxy(morpherState.address, MorpherState, { deployer });
  } else {
    await deployProxy(
      MorpherState,
      [isMainChain, sidechainOperatorAddress, treasuryAddress],
      { deployer }
    ); // deployer is changed to owner later
  }

  /**
   * Sidechain relevant settings
   */
  if (!isMainChain) {
    await morpherState.enableTransfers(ownerAddress);
    await morpherState.grantAccess(ownerAddress);
  }

  await morpherState.setSideChainOperator(ownerAddress);
};
