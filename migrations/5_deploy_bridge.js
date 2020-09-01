const MorpherState = artifacts.require("MorpherState");
const MorpherBridge = artifacts.require("MorpherBridge");

module.exports = async function(deployer, network, accounts) {
    const ownerAddress = process.env.MORPHER_OWNER || accounts[0];

    const morpherState = await MorpherState.deployed();
    await deployer.deploy(MorpherBridge, morpherState.address, ownerAddress);

    /**
     * Grant the access
     */
    await morpherState.grantAccess(MorpherBridge.address);

    /**
     * Set it to the State
     */
    await morpherState.setMorpherBridge(MorpherBridge.address);

    
};
