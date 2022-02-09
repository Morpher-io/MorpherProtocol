const MorpherState = artifacts.require("MorpherState");
const MorpherAccountMigration = artifacts.require("MorpherAccountMigration");
MorpherAccountMigration.synchronization_timeout = 300; //timeout in seconds

const markets = require("../markets.json");

module.exports = async function (deployer, network, accounts) {
  const ownerAddress = process.env.MORPHER_OWNER || accounts[0];
  const adminAddress = accounts[1];
  console.log(ownerAddress, adminAddress);


  //const morpherState = await MorpherState.at("0x52F74D95185f11a9A4885bFbDA77072Ff3CaaDCF");
  const morpherState = await MorpherState.deployed();

  /**
   * Only setting the Governance on Mainchain
   */
  if (network !== "mainchain") {
   
    await deployer.deploy(
      MorpherAccountMigration,
      morpherState.address,
      {gas: 8000000, from: adminAddress}
    );

    /**
     * Grant the Migration-Contract access to move funds
     */
    console.log("Grating access to " + MorpherAccountMigration.address);
    await morpherState.grantAccess(MorpherAccountMigration.address, {from: adminAddress});
    
    /**
     * allow the smart contract to move funds
     */
    console.log("Enabling transfers for " + MorpherAccountMigration.address);
    await morpherState.enableTransfers(MorpherAccountMigration.address, {from: adminAddress});

    const morpherAccountMigration = await MorpherAccountMigration.deployed();
    let marketHashesArray = [];
    for (const marketName in markets) {
      marketHashesArray.push(markets[marketName]);
      if(marketHashesArray.length == 100) {
        console.log("Deploying until " + marketName);
        await morpherAccountMigration.addMarketHashes(marketHashesArray, {from: adminAddress});
        marketHashesArray = [];
      }
    }
    await morpherAccountMigration.addMarketHashes(marketHashesArray, {from: adminAddress});
    await morpherAccountMigration.addMarketHashes(["0x9a31fdde7a3b1444b1befb10735dcc3b72cbd9dd604d2ff45144352bf0f359a6"], {from: adminAddress}); //STAKING_MPH
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
