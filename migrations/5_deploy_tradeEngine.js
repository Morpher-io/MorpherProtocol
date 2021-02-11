const MorpherState = artifacts.require("MorpherState");
const MorpherTradeEngine = artifacts.require("MorpherTradeEngine");
const MorpherStaking = artifacts.require("MorpherStaking");

module.exports = async function(deployer, network, accounts) {
    const ownerAddress = process.env.MORPHER_OWNER || accounts[0];

    const morpherState = await MorpherState.deployed();
    let deployedTimestamp = 0;
    if(network == "local" || network == "test") {
        deployedTimestamp = Math.round(Date.now() / 1000) - (60*60*24*30); //settings this for testing to 2020-february
    }
    await deployer.deploy(MorpherTradeEngine, morpherState.address, ownerAddress, MorpherStaking.address, true, deployedTimestamp);

    /**
     * Grant the Token access
     */
    await morpherState.grantAccess(MorpherTradeEngine.address);


};

