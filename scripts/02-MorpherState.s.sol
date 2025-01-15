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

contract DeployMorpherState is DeployOrUpgrade {
	using stdJson for string;

	function run() public {
		vm.startBroadcast();

		// Load AccessControl address - required for State initialization
		address accessControlAddress = loadAddress("MorpherAccessControl");
		require(accessControlAddress != address(0), "AccessControl must be deployed first");

		// Deploy or upgrade MorpherState
		address existingState = loadAddress("MorpherState");
		MorpherState implementation = new MorpherState();

		address state = deployOrUpgrade(
			existingState,
			address(implementation),
			abi.encodeCall(MorpherState.initialize, (true, accessControlAddress)),
			"MorpherState.sol"
		);

		saveAddress("MorpherState", state);
		console.log("MorpherState at:", state);

		// Only set admin rights for new deployments
		if (existingState == address(0)) {
			MorpherAccessControl accessControl = MorpherAccessControl(accessControlAddress);
			accessControl.grantRole(implementation.ADMINISTRATOR_ROLE(), msg.sender);
			accessControl.grantRole(implementation.GOVERNANCE_ROLE(), msg.sender);

			// Grant role to environment address if specified
			address envAdmin = vm.envOr("MORPHER_ADMINISTRATOR", address(0));
			if (envAdmin != address(0)) {
				accessControl.grantRole(implementation.ADMINISTRATOR_ROLE(), envAdmin);
			}
		}

		vm.stopBroadcast();
	}
}
