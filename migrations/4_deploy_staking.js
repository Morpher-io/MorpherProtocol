const MorpherState = artifacts.require("MorpherState");
const MorpherStaking = artifacts.require("MorpherStaking");

module.exports = async function(deployer, network, accounts) {
    const ownerAddress = process.env.MORPHER_OWNER || accounts[0];

    const morpherState = await MorpherState.deployed();

    await deployer.deploy(MorpherStaking, morpherState.address, ownerAddress);

    /**
     * Grant the Token access
     */
    await morpherState.grantAccess(MorpherStaking.address);
    await morpherState.grantAccess(ownerAddress);


};

