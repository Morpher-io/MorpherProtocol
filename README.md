# How to run the tests
Before you start:
* Install Ganache https://www.trufflesuite.com/ganache on your system and run it successfully on port 7545.

* Install Node.js, Npm and build-essential (Linux and MacOS package to build Web3 C/C++ files) on your computer. 

In the Linux terminal:

`curl -sL https://deb.nodesource.com/setup_12.x | sudo -E bash -`

`sudo apt-get install nodejs` for node and npm

`sudo apt-get install build-essential`


* Install Truffle by running `sudo npm install truffle@5.0.41 -g`. Be sure to use this exact version in case of compatibility issues.

After the initial setup is done, run the following commands to start the test suite.
* `npm install` to install all the truffle/node dependencies.
* Rename .env.example to .env and input all the required variables. If you're testing locally with Ganache, you only need to input `MORPHER_DEPLOYER` and `MORPHER_DEPLOYER_KEY` which is the first account you see in the Ganache GUI.
* If everything is configured correctly, run the last command: `truffle test --network local`

If you want to see exactly what assertions are being made, you can take a look at the `test` folder.
# SmartContract-Beta
Morpher Smart Contract collection for on chain transactions and trustless state recovery from sidechain

# Deploying instruction

Deploy MorpherState(bool mainChain)

Deploy MorpherToken(address stateAddress, address ownerAddress)

Deploy MorpherTradeEngine(address stateAddress, address ownerAddress)

Deploy MorpherBridge(address stateAddress, address ownerAddress)

Deploy MorpherGovernance(address stateAddress, address ownerAddress)

Deploy MorpherAirdrop(address airdropAdminAddress, address morpherTokenAddress, address ownerAddress)

Deploy MorpherEscrow(address recipientAddress, address morpherTokenAddress, address ownerAddress)

Deploy MorpherOracle(address tradeEngineAddress, address _callBackAddress, address payable gasCollectionAddress, uint256 gasForCallback, address ownerAddress)

------ MorpherStateBeta ------ 

grantAccess(morpherTokenAddress)

grantAccess(morpherTradeEngineAddress)

grantAccess(morpherBridgeAddress)

grantAccess(morpherGovernanceAddress)

setSideChainOperator(sideChainOperatorAddress)

// ------ Only relevant on sidechain ------ 

enableTransfers(addressOfDeployer)

enableTransfers(morpherAirdropAddress)

// ------ to have an Administrator and Oracle until there is a vote in the governance contract ------ 

setGovernanceContract(addressOfDeployer)

setAdministrator(addressOfDeployer)

// ------ set protocol contracts in state ------ 

setTokenContract(morpherTokenAddress)

setMorpherBridge(bridgeAddress)

setOracleContract(oracleAddress)

// ------ Enable "CRYPTO_BTC" and "CRYPTO_ETH" as markets for testing purposes ------ 

activateMarket(0x0bc89e95f9fdaab7e8a11719155f2fd638cb0f665623f3d12aab71d1a125daf9)

activateMarket(0x5376ff169a3705b2003892fe730060ee74ec83e5701da29318221aa782271779)

// ------ MorpherState: set Governance properly ------ 

ONLY MAIN CHAIN: setGovernanceContract(morpherGovernanceAddress)

transferOwnership(ownerAddress)
