const MorpherState = artifacts.require("MorpherState");
const MorpherToken = artifacts.require("MorpherToken");
const MorpherAccountMigration = artifacts.require("MorpherAccountMigration");
MorpherAccountMigration.synchronization_timeout = 300; //timeout in seconds

const markets = require("../markets.json");

module.exports = async function (deployer, network, accounts) {
  const ownerAddress = process.env.MORPHER_OWNER || accounts[0];

  const morpherState = await MorpherState.at("0xb07E7bEC3be6782F2f43bd3F4AbCCAA9B544B934");
  const morpherToken = await MorpherToken.at("0xe9D5afBae107A92A92cb57397C77154Dbc58CA9d");

  /**
   * Only setting the Governance on Mainchain
   */
  if (network !== "mainchain") {
   
    await deployer.deploy(
      MorpherAccountMigration,
      morpherToken.address,
      morpherState.address,
      {gas: 8000000}
    );

    /**
     * Grant the Migration-Contract access to move funds
     */
    await morpherState.grantAccess(MorpherAccountMigration.address);
    
    /**
     * allow the smart contract to move funds
     */
    await morpherState.enableTransfers(MorpherAccountMigration.address);

    const morpherAccountMigration = await MorpherAccountMigration.deployed();
    let marketHashesArray = [];
    for (const marketName in markets) {
      marketHashesArray.push(markets[marketName]);
      if(marketHashesArray.length == 100) {
        console.log("Deploying until " + marketName);
        await morpherAccountMigration.addMarketHashes(marketHashesArray);
        marketHashesArray = [];
      }
    }
    await morpherAccountMigration.addMarketHashes(marketHashesArray);
    //test with a single market below:
    //await morpherAccountMigration.addMarketHashes([web3.utils.sha3('CRYPTO_BTC')]);
    //let migrations = 


   
    // // transferOwnership(ownerAddress)
    // data = await morpherState.methods.transferOwnership(ownerAddress);
    
  } else {
    /**
     * We don't deploy this to the main-chain
     */
  }
};
