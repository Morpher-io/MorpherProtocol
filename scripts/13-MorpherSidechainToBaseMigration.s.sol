//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

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
	string constant CONTRACT_NAME = "MorpherSidechainToBaseMigration.sol:MorpherSidechainToBaseMigration";

	function run() public {
		vm.startBroadcast();

		// Load required addresses
		address accessControlAddress = loadAddress("MorpherAccessControl");
		address stateAddress = loadAddress("MorpherState");
        address stakingAddress = loadAddress("MorpherStaking"); // Added load
		require(accessControlAddress != address(0), "AccessControl must be deployed first");
		require(stateAddress != address(0), "MorpherState must be deployed first");
        require(stakingAddress != address(0), "MorpherStaking must be deployed first"); // Added require

		// Get initial plasma state root from environment or use a default
		bytes32 initialPlasmaStateRoot = vm.envOr("INITIAL_PLASMA_STATE_ROOT", bytes32(0));
		
		// Get migration bonus in basis points (default 500 = 5%)
		uint256 migrationBonus = vm.envOr("MIGRATION_BONUS_BPS", uint256(0));

		// Check if deploying fresh
		address existingProxy = loadAddress(CONTRACT_KEY);
		bool isNewDeployment = existingProxy == address(0);

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
            bytes32 stakingAdminRole = keccak256("STAKINGADMIN_ROLE"); // Role defined in MorpherStaking

			// Grant ADMINISTRATOR_ROLE to the migration contract proxy itself? Or to an external admin?
			// Assuming external admin for now.
			address envAdmin = vm.envOr("MIGRATION_ADMIN_ADDRESS", msg.sender);
			accessControl.grantRole(adminRole, envAdmin);
			console.log("Granted ADMINISTRATOR_ROLE to:", envAdmin);

			// Grant migration operator role to deployer (or designated operator)
			address envOperator = vm.envOr("MIGRATION_OPERATOR_ADDRESS", msg.sender);
			accessControl.grantRole(migrationOperatorRole, envOperator);
			console.log("Granted MIGRATION_OPERATOR_ROLE to:", envOperator);

            // Grant STAKINGADMIN_ROLE to the migration contract proxy
            accessControl.grantRole(stakingAdminRole, migrationProxy);
            console.log("Granted STAKINGADMIN_ROLE to Migration Contract:", migrationProxy);

			// Configure State with migration address and staking address
            MorpherState stateContract = MorpherState(stateAddress);
			stateContract.setMorpherSidechainToBaseMigrationAddress(migrationProxy);
            stateContract.setMorpherStakingAddress(stakingAddress); // Set staking address in state
			console.log("Set migration and staking addresses in MorpherState.");
		}

		vm.stopBroadcast(); // Move outside the if block
	}
}
