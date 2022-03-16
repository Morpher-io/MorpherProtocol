const MorpherState = artifacts.require("MorpherState");
const MorpherOracle = artifacts.require("MorpherOracle");
const MorpherTradeEngine = artifacts.require("MorpherTradeEngine");

module.exports = async function (deployer, network, accounts) {

  try {
    const morpherOracle = await MorpherOracle.deployed();

    await upgradeProxy(morpherOracle.address, MorpherOracle, {
      deployer,
    });
  } catch (e) {
    if (
      e.message !=
      "MorpherOracle has not been deployed to detected network (network/artifact mismatch)"
    ) {
      throw e;
    }
    
    let deployedTimestamp = 1613399217;
    const callbackAddress1 = process.env.CALLBACK_ADDRESS_1 || accounts[0];
    const callbackAddress2 = process.env.CALLBACK_ADDRESS_2;
    const callbackAddress3 = process.env.CALLBACK_ADDRESS_3;
   
    const gasCollectionAddress = process.env.GAS_COLLECTION || accounts[0];
  
    if (network == "test") {
      deployedTimestamp = Math.round(Date.now() / 1000) - 60 * 60 * 24 * 30 * 5; //settings this for testing 5 months back
    }

    const morpherState = await MorpherState.deployed();
    await deployProxy(
      MorpherOracle,
      [morpherState.address, gasCollectionAddress, 0],
      {
        deployer,
      }
    ); // deployer is changed to owner later

    const morpherOracle = await MorpherOracle.deployed();
    const morpherTradeEngine = await MorpherTradeEngine.deployed();
    const morpherAccessControl = await MorpherAccessControl.deployed();

    /**
     * Grant the Oracle the roles so it can do callbacks
     *
     * Minting happens via the Minting Limiter
     */
    await morpherAccessControl.grantRole(
      await morpherOracle.ORACLEOPERATOR_ROLE(),
      callbackAddress1
    );

    if (callbackAddress2) {
      await morpherAccessControl.grantRole(
        await morpherOracle.ORACLEOPERATOR_ROLE(),
        callbackAddress2
      );
    }
    if (callbackAddress3) {
      await morpherAccessControl.grantRole(
        await morpherOracle.ORACLEOPERATOR_ROLE(),
        callbackAddress3
      );
    }

    
    /**
     * Set the oracle as the "Oracle" so it can interact with Tradeengine
     */
    await morpherAccessControl.grantRole(
      await morpherTradeEngine.ORACLE_ROLE(),
      callbackAddress3
    );
    

    /**
     * Set the Trade Engine in State
     */
    morpherState.setMorpherOracle(morpherOracle.address);
  }

};
