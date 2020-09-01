const MorpherState = artifacts.require("MorpherState");
const MorpherToken = artifacts.require("MorpherToken");

module.exports = async function(deployer, network, accounts) {
    const ownerAddress = process.env.MORPHER_OWNER || accounts[0];

    const morpherState = await MorpherState.deployed();
    await deployer.deploy(MorpherToken, morpherState.address, ownerAddress); // deployer is changed to owner later

    /**
     * Grant the Token access
     */
    await morpherState.grantAccess(MorpherToken.address);

    /**
     * configure State
     */
    await morpherState.setTokenContract(MorpherToken.address);

   
};

