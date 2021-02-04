const MorpherState = artifacts.require("MorpherState");
const MorpherTradeEngine = artifacts.require("MorpherTradeEngine");

module.exports = async function(deployer, network, accounts) {
    const ownerAddress = process.env.MORPHER_OWNER || accounts[0];

    const morpherState = await MorpherState.deployed();
    await deployer.deploy(MorpherTradeEngine, morpherState.address, ownerAddress, true);

    /**
     * Grant the Token access
     */
    await morpherState.grantAccess(MorpherTradeEngine.address);


};

