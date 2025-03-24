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
import {MorpherOracle} from "../contracts/MorpherOracle.sol";
import {MorpherState} from "../contracts/MorpherState.sol";
import {MorpherTradeEngine} from "../contracts/MorpherTradeEngine.sol";
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol";

contract DeployMorpherOracle is DeployOrUpgrade {
	using stdJson for string;

	function run() public {
		vm.startBroadcast();

		// Load State address - required for Oracle initialization
		address stateAddress = loadAddress("MorpherState");
		require(stateAddress != address(0), "MorpherState must be deployed first");

		// Get configuration
		address gasCollectionAddress = vm.envOr("GAS_COLLECTION", msg.sender);

		// Deploy or upgrade MorpherOracle
		address existingOracle = loadAddress("MorpherOracle");
		MorpherOracle implementation = new MorpherOracle();

		address oracle = deployOrUpgrade(
			existingOracle,
			address(implementation),
			abi.encodeCall(MorpherOracle.initialize, (stateAddress, payable(gasCollectionAddress), 0)),
			"MorpherOracle.sol"
		);

		saveAddress("MorpherOracle", oracle);
		console.log("MorpherOracle at:", oracle);

		MorpherOracle oracleContract = MorpherOracle(oracle);

			MorpherAccessControl accessControl = MorpherAccessControl(loadAddress("MorpherAccessControl"));
		// Configure if this is a new deployment
		if (existingOracle == address(0)) {

			// Grant oracle operator roles
			address callbackAddress1 = vm.envOr("CALLBACK_ADDRESS_1", msg.sender);
			accessControl.grantRole(oracleContract.ORACLEOPERATOR_ROLE(), callbackAddress1);

			address callbackAddress2 = vm.envOr("CALLBACK_ADDRESS_2", address(0));
			if (callbackAddress2 != address(0)) {
				accessControl.grantRole(oracleContract.ORACLEOPERATOR_ROLE(), callbackAddress2);
			}

			address callbackAddress3 = vm.envOr("CALLBACK_ADDRESS_3", address(0));
			if (callbackAddress3 != address(0)) {
				accessControl.grantRole(oracleContract.ORACLEOPERATOR_ROLE(), callbackAddress3);
			}

			// Grant Oracle role for TradeEngine interaction
			address tradeEngineAddress = loadAddress("MorpherTradeEngine");
			if (tradeEngineAddress != address(0)) {
				accessControl.grantRole(MorpherTradeEngine(tradeEngineAddress).ORACLE_ROLE(), oracle);
			}

			// Set Oracle in State
			MorpherState(stateAddress).setMorpherOracle(oracle);
		}

		
		accessControl.grantRole(oracleContract.ADMINISTRATOR_ROLE(), msg.sender);
		// Set WETH address based on chain
		if (block.chainid == 84532) {
			// Base Sepolia
			oracleContract.setWmaticAddress(0x4200000000000000000000000000000000000006);
			// Universal Router on Base Sepolia
			oracleContract.setUniversalRouter(0x492E6456D9528771018DeB9E87ef7750EF184104);
			// Permit2 address (same on all networks)
			oracleContract.setPermit2Address(0x000000000022D473030F116dDEE9F6B43aC78BA3);
			
		} else if (block.chainid == 8453) {
			// Base Mainnet
			oracleContract.setWmaticAddress(0x4200000000000000000000000000000000000006);
			// Universal Router on Base Mainnet
			oracleContract.setUniversalRouter(0x6fF5693b99212Da76ad316178A184AB56D299b43);
			// Permit2 address (same on all networks)
			oracleContract.setPermit2Address(0x000000000022D473030F116dDEE9F6B43aC78BA3);
			
		} else {
			// Default to Sepolia
			oracleContract.setWmaticAddress(0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14);
			// Universal Router on Ethereum
			oracleContract.setUniversalRouter(0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD);
			// Permit2 address (same on all networks)
			oracleContract.setPermit2Address(0x000000000022D473030F116dDEE9F6B43aC78BA3);
		}

		vm.stopBroadcast();
	}
}
