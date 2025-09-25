//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// --- Import and Inherit from DeployOrUpgradeV5 ---
import {DeployOrUpgradeV5} from "./deployOrUpgradeV5.sol";

//morpher contracts
import {MorpherOracle} from "../contracts/MorpherOracle.sol"; // Use adapted v5 contract
import {MorpherState} from "../contracts/MorpherState.sol"; // Use adapted v5 contract
import {MorpherTradeEngine} from "../contracts/MorpherTradeEngine.sol"; // Use adapted v5 contract
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol"; // Use adapted v5 contract

// --- Inherit from DeployOrUpgradeV5 ---
contract DeployMorpherOracle is DeployOrUpgradeV5 {

	string constant CONTRACT_KEY = "MorpherOracle";
	// Use fully qualified name or filename as required by the upgrades plugin
	string constant CONTRACT_NAME = "contracts/MorpherOracle.sol:MorpherOracle";                                                                                    
	// Define EIP712 domain parameters
	string constant EIP712_NAME = "MorpherOracle";
	string constant EIP712_VERSION = "1";

	function run() public {
		// Load dependencies
		address stateAddress = loadAddress("MorpherState");
		require(stateAddress != address(0), "V5 MorpherState must be deployed first");
		address accessControlAddress = loadAddress("MorpherAccessControl");
		require(accessControlAddress != address(0), "V5 AccessControl must be deployed first");
		address tradeEngineAddress = loadAddress("MorpherTradeEngine");
		require(tradeEngineAddress != address(0), "V5 MorpherTradeEngine must be deployed first");

		// Get configuration
		address gasCollectionAddress = vm.envOr("GAS_COLLECTION", msg.sender);
		uint256 initialGasCallback = vm.envOr("GAS_FOR_CALLBACK", uint256(0)); // Default to 0 if not set

		// Check if deploying fresh
		address existingProxy = loadAddress(CONTRACT_KEY);
		bool isNewDeployment = existingProxy == address(0);

		vm.startBroadcast();

		// Deploy or upgrade using the V5 UUPS logic
		address oracleProxy = deployOrUpgradeV5(
			CONTRACT_KEY,
			CONTRACT_NAME,
			// Ensure initializer signature matches the adapted v5 contract, including EIP712 params
			abi.encodeCall(MorpherOracle.initialize, (stateAddress, payable(gasCollectionAddress), initialGasCallback, EIP712_NAME, EIP712_VERSION)),
			bytes("") // No upgrade call data needed for this example
		);

		saveAddress("MorpherOracle", oracleProxy);
		console.log("MorpherOracle V5 Proxy at:", oracleProxy);

		MorpherOracle oracleContract = MorpherOracle(oracleProxy); // Use proxy address
		MorpherAccessControl accessControl = MorpherAccessControl(accessControlAddress);

		// Configure if this is a new deployment
		if (isNewDeployment) {
			console.log("Performing initial configuration for MorpherOracle...");

			// Grant oracle operator roles
			bytes32 oracleOperatorRole = oracleContract.ORACLEOPERATOR_ROLE();
			address callbackAddress1 = vm.envOr("CALLBACK_ADDRESS_1", msg.sender); // Grant to deployer by default
			accessControl.grantRole(oracleOperatorRole, callbackAddress1);
			console.log("Granted ORACLEOPERATOR_ROLE to:", callbackAddress1);

			address callbackAddress2 = vm.envOr("CALLBACK_ADDRESS_2", address(0));
			if (callbackAddress2 != address(0)) {
				accessControl.grantRole(oracleOperatorRole, callbackAddress2);
				console.log("Granted ORACLEOPERATOR_ROLE to:", callbackAddress2);
			}

			address callbackAddress3 = vm.envOr("CALLBACK_ADDRESS_3", address(0));
			if (callbackAddress3 != address(0)) {
				accessControl.grantRole(oracleOperatorRole, callbackAddress3);
				console.log("Granted ORACLEOPERATOR_ROLE to:", callbackAddress3);
			}

			// Grant Oracle role for TradeEngine interaction
			bytes32 tradeEngineOracleRole = MorpherTradeEngine(tradeEngineAddress).ORACLE_ROLE();
			accessControl.grantRole(tradeEngineOracleRole, oracleProxy);
			console.log("Granted ORACLE_ROLE (for TradeEngine) to Oracle contract.");

			// Set Oracle address in State
			MorpherState(stateAddress).setMorpherOracle(oracleProxy);
			console.log("Set MorpherOracle address in MorpherState.");
		}

		// Grant ADMINISTRATOR_ROLE to deployer (or designated admin) - potentially needed for setting addresses
		address envAdmin = vm.envOr("ORACLE_ADMIN_ADDRESS", msg.sender);
		accessControl.grantRole(oracleContract.ADMINISTRATOR_ROLE(), envAdmin);
		console.log("Granted ADMINISTRATOR_ROLE to:", envAdmin);

		// Set WETH and Uniswap Router addresses based on chain
		// Note: Removed Universal Router, Permit2, Pool Manager settings as they weren't used in the v4 script's logic
		address wethAddress;
		address uniswapRouterAddress;

		if (block.chainid == 84532) { // Base Sepolia
			wethAddress = 0x4200000000000000000000000000000000000006;
			uniswapRouterAddress = 0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4; // V3 SwapRouter on Base Sepolia (check this address)
		} else if (block.chainid == 8453) { // Base Mainnet
			wethAddress = 0x4200000000000000000000000000000000000006;
			uniswapRouterAddress = 0x2626664c2603336E57B271c5C0b26F421741e481; // V3 SwapRouter on Base Mainnet
		} else { // Default to Sepolia
			wethAddress = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
			uniswapRouterAddress = 0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E; // V3 SwapRouter on Sepolia
		}

		if (oracleContract.wMaticAddress() != wethAddress) {
			oracleContract.setWmaticAddress(wethAddress);
			console.log("Set WETH address to:", wethAddress);
		}
		if (oracleContract.uniswapRouter() != uniswapRouterAddress) {
			oracleContract.setUniswapRouter(uniswapRouterAddress);
			console.log("Set Uniswap Router address to:", uniswapRouterAddress);
		}

		vm.stopBroadcast();
	}
}
