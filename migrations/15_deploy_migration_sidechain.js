const MorpherState = artifacts.require("MorpherState");
const MorpherAccountMigration = artifacts.require("MorpherAccountMigration");
MorpherAccountMigration.synchronization_timeout = 300; //timeout in seconds

const markets = require("../docs/markets.json");

module.exports = async function (deployer, network, accounts) {
  const ownerAddress = process.env.MORPHER_OWNER || accounts[0];
  const adminAddress = accounts[1];
  console.log(ownerAddress, adminAddress);


  // const morpherState = await MorpherState.at("0x52F74D95185f11a9A4885bFbDA77072Ff3CaaDCF");
  const morpherState = await MorpherState.deployed(); //MorpherState.at("0xB4881186b9E52F8BD6EC5F19708450cE57b24370"); //production
  // const morpherState = await MorpherState.deployed();

  /**
   * Only setting the Governance on Mainchain
   */
  if (network !== "mainchain") {
   
    await deployer.deploy(
      MorpherAccountMigration,
      morpherState.address,
      {gas: 6721975}
    );

    const morpherAccountMigration = await MorpherAccountMigration.deployed();
    let marketHashesArray = [];
    for (const marketsObj of markets) {
      marketHashesArray.push(web3.utils.sha3(marketsObj.id));
      if(marketHashesArray.length == 100) {
        console.log("Deploying until " + marketsObj.id);
        await morpherAccountMigration.addMarketHashes(marketHashesArray);
        marketHashesArray = [];
      }
    }
    await morpherAccountMigration.addMarketHashes(marketHashesArray);
    await morpherAccountMigration.addMarketHashes(["0x9a31fdde7a3b1444b1befb10735dcc3b72cbd9dd604d2ff45144352bf0f359a6"]); //STAKING_MPH


    // /**
    //  * allow the smart contract to move funds
    //  */
    // console.log("Enabling transfers for " + MorpherAccountMigration.address);
    // await morpherState.enableTransfers(MorpherAccountMigration.address);

    /**
     * Grant the Migration-Contract access to move funds
     */
    // console.log("Grating access to " + MorpherAccountMigration.address);
    // await morpherState.grantAccess(MorpherAccountMigration.address);
    

    
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
