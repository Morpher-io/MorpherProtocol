//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
// --- Import and Inherit from DeployOrUpgradeV5 ---
import {DeployOrUpgradeV5} from "./deployOrUpgradeV5.sol";

// Import the *adapted* v5 contracts
import {MorpherState} from "../contracts/MorpherState.sol";
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol"; // Keep for role granting

// --- Inherit from DeployOrUpgradeV5 ---
contract DeployMorpherState is DeployOrUpgradeV5 {
	string constant CONTRACT_KEY = "MorpherState";
	// Use fully qualified name or filename as required by the upgrades plugin
	string constant CONTRACT_NAME = "MorpherState.sol:MorpherState";

	function run() public {
		// Load dependencies
		address accessControlAddress = loadAddress("MorpherAccessControl");
		require(accessControlAddress != address(0), "V5 AccessControl must be deployed first");

		// Check if deploying fresh
		address existingProxy = loadAddress(CONTRACT_KEY);
		bool isNewDeployment = existingProxy == address(0);

		// Determine if deploying on mainchain (example: use chainid or env var)
		// bool isMainChain = block.chainid == 1 || block.chainid == 137; // Example chain IDs
		bool isMainChain = vm.envOr("IS_MAIN_CHAIN", true); // Example using env var

		vm.startBroadcast();

		// Deploy or upgrade using the V5 UUPS logic
		address stateProxy = deployOrUpgradeV5(
			CONTRACT_KEY,
			CONTRACT_NAME,
			// Ensure initializer signature matches the adapted v5 contract
			abi.encodeCall(MorpherState.initialize, (isMainChain, accessControlAddress)),
			bytes("") // No upgrade call data needed for this example
		);

		console.log("MorpherState V5 Proxy at:", stateProxy);

		// Grant roles on AccessControl contract if this is a new deployment
		if (isNewDeployment) {
			console.log("Granting initial roles on AccessControl for MorpherState...");
			MorpherAccessControl accessControl = MorpherAccessControl(accessControlAddress);

			// Define roles using constants from the contract *type* if possible, or hardcode hash
			bytes32 adminRole = keccak256("ADMINISTRATOR_ROLE"); // As defined in MorpherState/UserBlocking etc.
			bytes32 governanceRole = keccak256("GOVERNANCE_ROLE"); // As defined in MorpherState

			// Grant roles to deployer
			accessControl.grantRole(adminRole, msg.sender);
			accessControl.grantRole(governanceRole, msg.sender);
			console.log("Granted ADMIN/GOVERNANCE roles to deployer:", msg.sender);

			// Grant roles to environment address if specified
			address envAdmin = vm.envOr("MORPHER_ADMINISTRATOR", address(0));
			if (envAdmin != address(0) && envAdmin != msg.sender) {
				accessControl.grantRole(adminRole, envAdmin);
				console.log("Granted ADMIN role to env address:", envAdmin);
			}
			address envGovernance = vm.envOr("MORPHER_GOVERNANCE", address(0));
			if (envGovernance != address(0) && envGovernance != msg.sender) {
				accessControl.grantRole(governanceRole, envGovernance);
				console.log("Granted GOVERNANCE role to env address:", envGovernance);
			}
		}

		vm.stopBroadcast();
	}
}
