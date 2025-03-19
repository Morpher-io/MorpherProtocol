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
import {MorpherTradeEngine} from "../contracts/MorpherTradeEngine.sol";
import {MorpherState} from "../contracts/MorpherState.sol";
import {MorpherToken} from "../contracts/MorpherToken.sol";
import {MorpherStaking} from "../contracts/MorpherStaking.sol";
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol";

contract DeployMorpherTradeEngine is DeployOrUpgrade {
	using stdJson for string;

	function run() public {
		vm.startBroadcast();

		// Load State address - required for TradeEngine initialization
		address stateAddress = loadAddress("MorpherState");
		require(stateAddress != address(0), "MorpherState must be deployed first");
		MorpherAccessControl accessControl = MorpherAccessControl(loadAddress("MorpherAccessControl"));

		// Deploy or upgrade MorpherTradeEngine
		address existingTradeEngine = loadAddress("MorpherTradeEngine");

		// Configure if this is a new deployment
		if (existingTradeEngine != address(0)) {
			MorpherTradeEngine tradeEngineContract = MorpherTradeEngine(existingTradeEngine);

			// Grant role to environment address if specified
			address envAdmin = vm.envOr("MORPHER_ADMINISTRATOR", address(0));

			if (envAdmin != address(0)) {
				if (!accessControl.hasRole(tradeEngineContract.POSITIONADMIN_ROLE(), envAdmin)) {
					accessControl.grantRole(tradeEngineContract.POSITIONADMIN_ROLE(), envAdmin);
				}
				if (!accessControl.hasRole(MorpherToken(loadAddress("MorpherToken")).BURNER_ROLE(), envAdmin)) {
					accessControl.grantRole(MorpherToken(loadAddress("MorpherToken")).BURNER_ROLE(), envAdmin);
				}
			}
		}

		//allow minting for the admin temporarily

		// Deploy or upgrade MorpherTradeEngine
		address existingAdmin = loadAddress("MorpherAdmin");
		if (existingAdmin != address(0)) {
			if (!accessControl.hasRole(MorpherToken(loadAddress("MorpherToken")).MINTER_ROLE(), existingAdmin)) {
				accessControl.grantRole(MorpherToken(loadAddress("MorpherToken")).MINTER_ROLE(), existingAdmin);
			}
			accessControl.grantRole(MorpherToken(loadAddress("MorpherToken")).BURNER_ROLE(), existingAdmin);
		}

		vm.stopBroadcast();
	}
}
