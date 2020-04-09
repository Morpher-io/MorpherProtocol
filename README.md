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

setGovernanceContract(morpherGovernanceAddress)

transferOwnership(ownerAddress)
