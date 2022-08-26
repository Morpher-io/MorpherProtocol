const MorpherState = artifacts.require("MorpherState");
const MorpherOracle = artifacts.require("MorpherOracle");
const MorpherTradeEngine = artifacts.require("MorpherTradeEngine");

const MorpherPoolShareManager = artifacts.require("MorpherPoolShareManager");

const CRYPTO_BTC = '0x0bc89e95f9fdaab7e8a11719155f2fd638cb0f665623f3d12aab71d1a125daf9';
const CRYPTO_ETH = '0x5376ff169a3705b2003892fe730060ee74ec83e5701da29318221aa782271779';

module.exports = async function (deployer, network, accounts) {
  const ownerAddress = process.env.MORPHER_OWNER || accounts[0];
  const callbackAddress1 = process.env.CALLBACK_ADDRESS_1 || accounts[0];
  const callbackAddress2 = process.env.CALLBACK_ADDRESS_2 || accounts[0];
  const callbackAddress3 = process.env.CALLBACK_ADDRESS_3 || accounts[0];
  const coldStorageOwnerAddress = process.env.COLDSTORAGE_OWNER_ADDRESS || accounts[0];
  const gasCollectionAddress = process.env.GAS_COLLECTION || accounts[0];


  const morpherState = await MorpherState.deployed();
  /**
   * override governance first
   */
  await morpherState.setGovernanceContract(ownerAddress);


  let isMainChain = false;
  if (network === "mainchain" || network === 'kovan') {
    isMainChain = true;
  }


  const morpherTradeEngine = await MorpherTradeEngine.deployed();
  
  
  await deployer.deploy(MorpherPoolShareManager, morpherState.address);
  await morpherState.grantAccess(MorpherPoolShareManager.address);

  await deployer.deploy(MorpherOracle, morpherTradeEngine.address, morpherState.address, callbackAddress1, gasCollectionAddress, 0, coldStorageOwnerAddress, MorpherPoolShareManager.address); // deployer is changed to owner later
  let morpherOracle = await MorpherOracle.deployed();
  await morpherOracle.enableCallbackAddress(callbackAddress2);
  await morpherOracle.enableCallbackAddress(callbackAddress3);
  await morpherState.setGovernanceContract(ownerAddress); //will be set on 9_deploy_governance again
  await morpherState.setOracleContract(MorpherOracle.address);

  if (!isMainChain) {
    await morpherState.setAdministrator(ownerAddress);
    await morpherState.activateMarket(CRYPTO_BTC);
    await morpherState.activateMarket(CRYPTO_ETH);
  }
 
    /*
    if(network === 'local'){
        let data;
        
        // ------ To have an Administrator and Oracle until there is a vote in the governance contract ------
        // setAdministrator(addressOfDeployer)
        
        data = await morpherState.methods.setAdministrator(deployerAddress);
        await sendTransactionFrom(deployerAddress, data, deployerKey, MorpherState.address);
        console.log('Administrator set.');
        
    }   
    */
};
