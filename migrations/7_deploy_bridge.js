const MorpherState = artifacts.require("MorpherState");
const MorpherBridge = artifacts.require("MorpherBridge");
const MorpherUserBlocking = artifacts.require("MorpherUserBlocking");

module.exports = async function(deployer, network, accounts) {
    const ownerAddress = process.env.MORPHER_OWNER || accounts[0];

    const morpherState = await MorpherState.deployed();
    const morpherUserBlocking = await MorpherUserBlocking.deployed();
    await deployer.deploy(MorpherBridge, morpherState.address, ownerAddress, '0x0000000000000000000000000000000000000000', morpherUserBlocking.address);

    /**
     * Grant the access
     */
    await morpherState.grantAccess(MorpherBridge.address);

    /**
     * Set it to the State
     */
    await morpherState.setMorpherBridge(MorpherBridge.address);

    
};
