//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Upgrades} from "../lib/openzeppelin-foundry-upgrades/src/LegacyUpgrades.sol";
import {Options} from "../lib/openzeppelin-foundry-upgrades/src/Options.sol";

import {DeployOrUpgrade} from "./deployOrUpgrade.sol";

//morpher contracts
import {MorpherState} from "../contracts/MorpherState.sol";
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol";
import {MorpherSidechainToBaseMigration} from "../contracts/MorpherSidechainToBaseMigration.sol";

contract DeployMorpherSidechainToBaseMigration is DeployOrUpgrade {
	using stdJson for string;

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

		// Deploy or upgrade MorpherSidechainToBaseMigration
		address existingMigration = loadAddress("MorpherSidechainToBaseMigration");
		MorpherSidechainToBaseMigration implementation = new MorpherSidechainToBaseMigration();

		address migration = deployOrUpgrade(
			existingMigration,
			address(implementation),
			abi.encodeCall(MorpherSidechainToBaseMigration.initialize, (stateAddress, initialPlasmaStateRoot, migrationBonus)),
			"MorpherSidechainToBaseMigration.sol"
		);

		saveAddress("MorpherSidechainToBaseMigration", migration);
		console.log("MorpherSidechainToBaseMigration at:", migration);

		// Only set roles for new deployments
		if (existingMigration == address(0)) {
			MorpherAccessControl accessControl = MorpherAccessControl(accessControlAddress);
			
			// Grant roles to the migration contract
			accessControl.grantRole(keccak256("ADMINISTRATOR_ROLE"), migration);
			
			// Grant migration operator role to deployer
			accessControl.grantRole(keccak256("MIGRATION_OPERATOR_ROLE"), msg.sender);
			
			// // Configure State with migration address if needed
			// MorpherState state = MorpherState(stateAddress);
			// state.setMorpherSidechainToBaseMigrationAddress(migration);
			
			console.log("Granted ADMINISTRATOR_ROLE to migration contract");
			console.log("Granted MIGRATION_OPERATOR_ROLE to deployer");
			console.log("Set migration address in MorpherState");
		}

		vm.stopBroadcast();
	}
}
