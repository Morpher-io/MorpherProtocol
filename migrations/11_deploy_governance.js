const MorpherState = artifacts.require("MorpherState");
const MorpherGovernance = artifacts.require("MorpherGovernance");

module.exports = async function (deployer, network, accounts) {
  const ownerAddress = process.env.MORPHER_OWNER || accounts[0];

  const morpherState = await MorpherState.deployed();

  /**
   * Only setting the Governance on Mainchain
   */
  if (network === "mainchain") {
   
    await deployer.deploy(
      MorpherGovernance,
      morpherState.address,
      ownerAddress
    );

    /**
     * Grant the Token access
     */
    await morpherState.grantAccess(MorpherGovernance.address);

    /**
     * Set it to the State
     */
    await morpherState.setGovernanceContract(MorpherGovernance.address);

   
    // // transferOwnership(ownerAddress)
    // data = await morpherState.methods.transferOwnership(ownerAddress);
    
  } else {
    /**
     * Override access for sidechain
     */
    await morpherState.setGovernanceContract(ownerAddress);
  }
};
