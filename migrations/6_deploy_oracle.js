const MorpherState = artifacts.require("MorpherState");
const MorpherOracle = artifacts.require("MorpherOracle");
const MorpherTradeEngine = artifacts.require("MorpherTradeEngine");

const CRYPTO_BTC = '0x0bc89e95f9fdaab7e8a11719155f2fd638cb0f665623f3d12aab71d1a125daf9';
const CRYPTO_ETH = '0x5376ff169a3705b2003892fe730060ee74ec83e5701da29318221aa782271779';

module.exports = async function (deployer, network, accounts) {
  const ownerAddress = process.env.MORPHER_OWNER || accounts[0];
  const callbackAddress = process.env.CALLBACK_ADDRESS || accounts[0];
  const coldStorageOwnerAddress = process.env.CALLBACK_ADDRESS || accounts[0];
  const gasCollectionAddress = process.env.GAS_COLLECTION || accounts[0];


  const morpherState = await MorpherState.deployed();
  /**
   * override governance first
   */
  await morpherState.setGovernanceContract(ownerAddress);


  let isMainChain = false;
  if (network === "mainchain") {
    isMainChain = true;
  }


  const morpherTradeEngine = await MorpherTradeEngine.deployed();
  
  await deployer.deploy(MorpherOracle, morpherTradeEngine.address, morpherState.address, callbackAddress, gasCollectionAddress, 0, coldStorageOwnerAddress); // deployer is changed to owner later

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
