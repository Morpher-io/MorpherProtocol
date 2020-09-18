const MorpherState = artifacts.require("MorpherState");
const MorpherToken = artifacts.require("MorpherToken");
const MorpherAccountMigration = artifacts.require("MorpherAccountMigration");

module.exports = async function (deployer, network, accounts) {
  const ownerAddress = process.env.MORPHER_OWNER || accounts[0];

  const morpherState = await MorpherState.deployed();
  const morpherToken = await MorpherToken.deployed();

  /**
   * Only setting the Governance on Mainchain
   */
  if (network !== "mainchain") {
   
    await deployer.deploy(
      MorpherAccountMigration,
      morpherToken.address,
      morpherState.address,
      {gas: 8000000}
    );

    /**
     * Grant the Migration-Contract access to move funds
     */
    await morpherState.grantAccess(MorpherAccountMigration.address);


   
    // // transferOwnership(ownerAddress)
    // data = await morpherState.methods.transferOwnership(ownerAddress);
    
  } else {
    /**
     * We don't deploy this to the main-chain
     */
  }
};
