const MorpherState = artifacts.require("MorpherState");
const MorpherBridge = artifacts.require("MorpherBridge");

module.exports = async function(deployer, network, accounts) {
    const ownerAddress = process.env.MORPHER_OWNER;
    const stateAddress = '0x1f426C51F0Ef7655A6f4c3Eb58017d2F1c381bfF';

    
    await deployer.deploy(MorpherBridge, stateAddress, ownerAddress);

    /**
     * Grant the access
     */
    //await morpherState.grantAccess(MorpherBridge.address);

    /**
     * Set it to the State
     */
    //await morpherState.setMorpherBridge(MorpherBridge.address);

    
};
