//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Upgrades} from "../lib/openzeppelin-foundry-upgrades/src/LegacyUpgrades.sol";
import {Options} from "../lib/openzeppelin-foundry-upgrades/src/Options.sol"; // Keep Options if used by V5 helper

// --- Import and Inherit from DeployOrUpgradeV5 ---
import {DeployOrUpgradeV5} from "./deployOrUpgradeV5.sol";

//morpher contracts
import {MorpherState} from "../contracts/MorpherState.sol"; // Use adapted v5 contract
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol"; // Use adapted v5 contract
import {MorpherSidechainToBaseMigration} from "../contracts/MorpherSidechainToBaseMigration.sol"; // Use adapted v5 contract

// --- Inherit from DeployOrUpgradeV5 ---
contract DeployMorpherSidechainToBaseMigration is DeployOrUpgradeV5 {

	string constant CONTRACT_KEY = "MorpherSidechainToBaseMigration";
	// Use fully qualified name or filename as required by the upgrades plugin
	string constant CONTRACT_NAME = "contracts/MorpherSidechainToBaseMigration.sol:MorpherSidechainToBaseMigration";

	function run() public {
		vm.startBroadcast();

		// Load required addresses
		address accessControlAddress = loadAddress("MorpherAccessControl");
		address stateAddress = loadAddress("MorpherState");
		require(accessControlAddress != address(0), "AccessControl must be deployed first");
		require(stateAddress != address(0), "MorpherState must be deployed first");

		// Get initial plasma state root from environment or use a default
		bytes32 initialPlasmaStateRoot = vm.envOr("INITIAL_PLASMA_STATE_ROOT", bytes32(0));
		
		// Get migration bonus in basis points (default 500 = 5%)
		uint256 migrationBonus = vm.envOr("MIGRATION_BONUS_BPS", uint256(0));

		// Check if deploying fresh
		address existingProxy = loadAddress(CONTRACT_KEY);
		bool isNewDeployment = existingProxy == address(0);

		vm.startBroadcast();

		// Deploy or upgrade using the V5 UUPS logic
		address migrationProxy = deployOrUpgradeV5(
			CONTRACT_KEY,
			CONTRACT_NAME,
			// Ensure initializer signature matches the adapted v5 contract
			abi.encodeCall(MorpherSidechainToBaseMigration.initialize, (stateAddress, initialPlasmaStateRoot, migrationBonus)),
			bytes("") // No upgrade call data needed for this example
		);

		saveAddress(CONTRACT_KEY, migrationProxy);
		console.log("MorpherSidechainToBaseMigration V5 Proxy at:", migrationProxy);

		// Only set roles for new deployments
		if (isNewDeployment) {
			MorpherAccessControl accessControl = MorpherAccessControl(accessControlAddress);
			MorpherSidechainToBaseMigration migrationContract = MorpherSidechainToBaseMigration(migrationProxy); // Use proxy address

			// Define roles using constants from the contract *type* or keccak256
			bytes32 adminRole = migrationContract.ADMINISTRATOR_ROLE();
			bytes32 migrationOperatorRole = migrationContract.MIGRATION_OPERATOR_ROLE();

			// Grant ADMINISTRATOR_ROLE to the migration contract proxy itself? Or to an external admin?
			// Assuming external admin for now.
			address envAdmin = vm.envOr("MIGRATION_ADMIN_ADDRESS", msg.sender);
			accessControl.grantRole(adminRole, envAdmin);
			console.log("Granted ADMINISTRATOR_ROLE to:", envAdmin);

			// Grant migration operator role to deployer (or designated operator)
			address envOperator = vm.envOr("MIGRATION_OPERATOR_ADDRESS", msg.sender);
			accessControl.grantRole(migrationOperatorRole, envOperator);
			console.log("Granted MIGRATION_OPERATOR_ROLE to:", envOperator);

			// Configure State with migration address if needed (assuming a setter exists)
			// MorpherState(stateAddress).setMorpherSidechainToBaseMigrationAddress(migrationProxy);
			// console.log("Set migration address in MorpherState.");
		}

		vm.stopBroadcast(); // Move outside the if block
	}
}
