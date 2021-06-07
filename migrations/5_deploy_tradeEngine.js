const MorpherState = artifacts.require("MorpherState");
const MorpherTradeEngine = artifacts.require("MorpherTradeEngine");
const MorpherStaking = artifacts.require("MorpherStaking");
const MorpherMintingLimiter = artifacts.require("MorpherMintingLimiter");

module.exports = async function(deployer, network, accounts) {
    const ownerAddress = process.env.MORPHER_OWNER || accounts[0];
    const mintLimit = process.env.MINTING_LIMIT || 0;
    const timelockPeriodMinting = process.env.MINTING_TIME_LOCK_PERIOD || 0;

    const morpherState = await MorpherState.deployed();
    let deployedTimestamp = 0;
    if(network == "local" || network == "test") {
        deployedTimestamp = Math.round(Date.now() / 1000) - (60*60*24*30); //settings this for testing to 2020-february
    }
    await deployer.deploy(MorpherMintingLimiter, morpherState.address, mintLimit, timelockPeriodMinting);
    const morpherMintingLimiter = await MorpherMintingLimiter.deployed();
    await deployer.deploy(MorpherTradeEngine, morpherState.address, ownerAddress, MorpherStaking.address, true, deployedTimestamp, morpherMintingLimiter.address);

    const tradeEngine = await MorpherTradeEngine.deployed();
    await morpherMintingLimiter.setTradeEngineAddress(tradeEngine.address);

    /**
     * Grant the Token access
     */
    await morpherState.grantAccess(tradeEngine.address);
    await morpherState.grantAccess(morpherMintingLimiter.address);


};

