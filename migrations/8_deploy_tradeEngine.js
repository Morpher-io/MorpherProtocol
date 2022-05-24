const MorpherState = artifacts.require("MorpherState");
const MorpherTradeEngine = artifacts.require("MorpherTradeEngine");
const MorpherToken = artifacts.require("MorpherToken");
const MorpherAccessControl = artifacts.require("MorpherAccessControl");

const { deployProxy, upgradeProxy } = require("@openzeppelin/truffle-upgrades");


module.exports = async function (deployer, network, accounts) {

  try {
    const morpherTradeEngine = await MorpherTradeEngine.deployed();

    await upgradeProxy(morpherTradeEngine.address, MorpherTradeEngine, {
      deployer,
    });
  } catch (e) {
    if (
      e.message !=
      "MorpherTradeEngine has not been deployed to detected network (network/artifact mismatch)"
    ) {
      throw e;
    }
    let deployedTimestamp = 1613399217;
    if (network == "test") {
      deployedTimestamp = Math.round(Date.now() / 1000) - 60 * 60 * 24 * 30 * 5; //settings this for testing 5 months back
    }
    const escrowEnabled = process.env.ESCROW_ENABLED;
    const morpherState = await MorpherState.deployed();
    await deployProxy(
      MorpherTradeEngine,
      [morpherState.address, escrowEnabled, deployedTimestamp],
      {
        deployer,
      }
    ); // deployer is changed to owner later

    const morpherToken = await MorpherToken.deployed();
    const morpherTradeEngine = await MorpherTradeEngine.deployed();
    const morpherAccessControl = await MorpherAccessControl.deployed();

    /**
     * Grant the TradeEngine the Burner role, so it can burn tokens 
     * 
     * Minting happens via the Minting Limiter
     */
    await morpherAccessControl.grantRole(
      await morpherToken.BURNER_ROLE(),
      morpherTradeEngine.address
    );

    /**
     * Allow the trade engine to set its own positions
     */
    await morpherAccessControl.grantRole(
      await morpherTradeEngine.POSITIONADMIN_ROLE(),
      morpherTradeEngine.address
    );
    

    /**
     * Set the Trade Engine in State
     */
    await morpherState.setMorpherTradeEngine(morpherTradeEngine.address);
  }
  
};
