const MorpherState = artifacts.require("MorpherState");
const MorpherToken = artifacts.require("MorpherToken");
const MorpherAccountMigration = artifacts.require("MorpherAccountMigration");

const markets = require("../markets.json");

module.exports = async function (deployer, network, accounts) {
  const ownerAddress = process.env.MORPHER_OWNER || accounts[0];

  const morpherState = await MorpherState.deployed();
  const morpherToken = await MorpherToken.deployed();

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
    for(let i = 0; i < markets.length; i++) {
      marketHashesArray.push(web3.utils.sha3(markets[i]));
      if(marketHashesArray.length == 100) {
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
