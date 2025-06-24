//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// --- Import and Inherit from DeployOrUpgradeV5 ---
import {DeployOrUpgradeV5} from "./deployOrUpgradeV5.sol";

//morpher contracts
import {MorpherState} from "../contracts/MorpherState.sol"; // Use adapted v5 contract
import {MorpherTradeEngine} from "../contracts/MorpherTradeEngine.sol"; // Use adapted v5 contract
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol"; // Use adapted v5 contract
import {MorpherAdminFunctions} from "../contracts/MorpherAdminFunctions.sol"; // Use adapted v5 contract

// --- Inherit from DeployOrUpgradeV5 ---
contract DeployMorpherAdminFunctions is DeployOrUpgradeV5 {

	string constant CONTRACT_KEY = "MorpherAdminFunctions";
	// Use fully qualified name or filename as required by the upgrades plugin
	string constant CONTRACT_NAME = "MorpherAdminFunctions.sol";
	function run() public {
		// Load dependencies
		address stateAddress = loadAddress("MorpherState");
		require(stateAddress != address(0), "V5 MorpherState must be deployed first");
		address accessControlAddress = loadAddress("MorpherAccessControl");
		require(accessControlAddress != address(0), "V5 AccessControl must be deployed first");
		address tradeEngineAddress = loadAddress("MorpherTradeEngine");
		require(tradeEngineAddress != address(0), "V5 MorpherTradeEngine must be deployed first");

		// Check if deploying fresh
		address existingProxy = loadAddress(CONTRACT_KEY);
		bool isNewDeployment = existingProxy == address(0);

		vm.startBroadcast();

		// Deploy or upgrade using the V5 UUPS logic
		address adminFunctionsProxy = deployOrUpgradeV5(
			CONTRACT_KEY,
			CONTRACT_NAME,
			// Ensure initializer signature matches the adapted v5 contract, including EIP712 params
			abi.encodeCall(MorpherAdminFunctions.initialize, (stateAddress)),
			bytes("") // No upgrade call data needed for this example
		);

		saveAddress("MorpherAdminFunctions", adminFunctionsProxy);
		console.log("MorpherAdminFunctions V5 Proxy at:", adminFunctionsProxy);

		MorpherAdminFunctions adminFunctions = MorpherAdminFunctions(adminFunctionsProxy); // Use proxy address
		MorpherAccessControl accessControl = MorpherAccessControl(accessControlAddress);

		// Configure if this is a new deployment
		if (isNewDeployment) {
			console.log("Performing initial configuration for MorpherOracle...");

			// Grant Oracle role for TradeEngine interaction
			bytes32 tradeEngineOracleRole = MorpherTradeEngine(tradeEngineAddress).ORACLE_ROLE();
			accessControl.grantRole(tradeEngineOracleRole, adminFunctionsProxy);
			console.log("Granted ORACLE_ROLE (for TradeEngine) to Oracle contract.");
		}


		vm.stopBroadcast();
	}
}
