const MorpherState = artifacts.require("MorpherState");
const MorpherAirdrop = artifacts.require("MorpherAirdrop");
const MorpherToken = artifacts.require("MorpherToken");

module.exports = async function (deployer, network, accounts) {
  const ownerAddress = process.env.MORPHER_OWNER || accounts[0];
  const airdropAdminAddress = process.env.AIRDROP_ADMIN || accounts[0];

  /**
   * only on sidechain
   */
  if (network !== "mainchain" && network !== 'kovan') {
    const morpherToken = await MorpherToken.deployed();
    const morpherState = await MorpherState.deployed();
    
    await deployer.deploy(MorpherAirdrop, airdropAdminAddress, morpherToken.address, ownerAddress);

    await morpherState.enableTransfers(MorpherAirdrop.address);
  }
};
