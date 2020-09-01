const MorpherEscrow = artifacts.require("MorpherEscrow");
const MorpherToken = artifacts.require("MorpherToken");

module.exports = async function (deployer, network, accounts) {
  const ownerAddress = process.env.MORPHER_OWNER || accounts[0];
  const treasuryAddress = process.env.MORPHER_TREASURY || accounts[0];

  const morpherToken = await MorpherToken.deployed();
  await deployer.deploy(MorpherEscrow, treasuryAddress, morpherToken.address, ownerAddress);
};
