// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
// Removed: import {DeployOrUpgradeV5} from "./deployOrUpgradeV5.sol";
import {MorpherSidechainToBaseMigration} from "../contracts/MorpherSidechainMigrationSelfcontained.sol";

// Minimal interface for the MorpherState contract to call grantAccess
interface IMorpherStateForAccess {
	function grantAccess(address _address) external;
	function _owner() external view returns (address); // Needed to check if OWNER_ADDRESS is admin
}

interface IMorpherOracle {
	function enableCallbackAddress(address _address) external;
	function _owner() external view returns (address); // Needed to check if OWNER_ADDRESS is admin
}

contract DeployOldSidechainMigration is
	Script // Changed inheritance
{
	// Removed: string constant MIGRATION_CONTRACT_KEY = "MorpherSidechainMigration";
	/**
	
curl -X POST https://sidechain-test.morpher.com \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc":"2.0",
    "method":"anvil_impersonateAccount",
    "params":["0x51c5ce7c4926d5ca74f4824e11a062f1ef491762"],
    "id":1
  }'

forge script scripts/DeployOldSidechainMigration.s.sol --rpc-url anvilfork --slow -vvv --broadcast --legacy
	 */

	function run() external {
		// --- Load Environment Variables ---
		address ownerAddress = vm.envAddress("OLD_SIDECHAIN_OWNER_ADDRESS");
		address stateAddress = vm.envAddress("OLD_SIDECHAIN_STATE_ADDRESS");
		address oracleAddress = vm.envAddress("OLD_SIDECHAIN_ORACLE_ADDRESS");
		address oldSidechainCallbackAddress = vm.envAddress("OLD_SIDECHAIN_CALLBACK_ADDRESS");
		uint256 targetChainId = vm.envUint("TARGET_CHAIN_ID");

		// --- Input Validation ---
		require(ownerAddress != address(0), "OWNER_ADDRESS env var not set");
		require(stateAddress != address(0), "STATE_ADDRESS env var not set");
		require(oracleAddress != address(0), "ORACLE_ADDRESS env var not set");
		require(oldSidechainCallbackAddress != address(0), "OLD_SIDECHAIN_CALLBACK_ADDRESS env var not set");
		require(targetChainId != 0, "TARGET_CHAIN_ID env var not set or is zero");

		// --- Check if OWNER_ADDRESS is the administrator on MorpherState ---
		// This assumes the state contract has a getAdministrator function
		// If the function name is different, adjust the interface and call below
		address currentAdmin = IMorpherStateForAccess(stateAddress)._owner();
		require(currentAdmin == ownerAddress, "OWNER_ADDRESS is not the administrator on MorpherState");
		address currentAdminOracle = IMorpherOracle(oracleAddress)._owner();
		require(currentAdminOracle == ownerAddress, "OWNER_ADDRESS is not the administrator on MorpherState");

		// --- Deploy Migration Contract ---
		console.log("Deploying MorpherSidechainToBaseMigration...");
		console.log("  State Address:", stateAddress);
		console.log("  Oracle Address:", oracleAddress);
		console.log("  Target Chain ID:", targetChainId);
		vm.startBroadcast(ownerAddress);
		MorpherSidechainToBaseMigration migrationContract = new MorpherSidechainToBaseMigration(
			stateAddress,
			oracleAddress,
			targetChainId
		);
		address migrationContractAddress = address(migrationContract);
		console.log("Deployed MorpherSidechainToBaseMigration at:", migrationContractAddress);

		// Removed: saveAddress call

		// --- Grant Access on State Contract ---
		console.log("Granting access for migration contract on MorpherState...");
		console.log("  Pranking as OWNER_ADDRESS:", ownerAddress);
		console.log("  Calling grantAccess on STATE_ADDRESS:", stateAddress);
		console.log("  Granting access to:", migrationContractAddress);
		console.log("  Enabling callback account:", oldSidechainCallbackAddress);

		// vm.prank(ownerAddress);
		IMorpherStateForAccess(stateAddress).grantAccess(migrationContractAddress);
		IMorpherOracle(oracleAddress).enableCallbackAddress(oldSidechainCallbackAddress);

		console.log("Access granted successfully.");

		vm.stopBroadcast();

	}
}
