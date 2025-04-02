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

// --- Inherit from DeploymentUtils ---
import {DeploymentUtils} from "./DeploymentUtils.sol";

// --- Remove Morpher contract imports if not directly used ---

// --- Inherit from DeploymentUtils ---
abstract contract DeployOrUpgrade is DeploymentUtils {
	// --- Remove address management functions (now in DeploymentUtils) ---
	// --- Remove Addresses struct (now in DeploymentUtils) ---

	// --- Keep v4 specific helpers ---
	function deployProxyAdmin() internal returns (address proxyAdminAddr) {
		// Load the *v4* ProxyAdmin address
		proxyAdminAddr = loadAddress("proxyAdmin"); // Assumes "proxyAdmin" key exists for v4 deployments
		if (proxyAdminAddr == address(0)) {
			console.log("Deploying new V4 ProxyAdmin...");
			ProxyAdmin admin = new ProxyAdmin();
			proxyAdminAddr = address(admin);
			// Save the v4 proxy admin address using the specific key "proxyAdmin"
			saveAddress("proxyAdmin", proxyAdminAddr);
			console.log("Deployed V4 ProxyAdmin at:", proxyAdminAddr);
		}
		return proxyAdminAddr;
	}

	function deployProxy(address implementation, address admin, bytes memory data) internal returns (address) {
		TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(implementation, admin, data);
		return address(proxy);
	}

	// Keep v4 validateUpgrade using LegacyUpgrades
	function validateUpgrade(string memory contractName) internal {
		Options memory opts;
		// Ensure this uses LegacyUpgrades
		Upgrades.validateUpgrade(contractName, opts);
	}

	// Keep v4 deployOrUpgrade logic
	function deployOrUpgrade(
		address existingProxy,
		address implementation, // This is the *new* v4 implementation address
		bytes memory initData,
		string memory contractStorageKey // e.g., "MorpherState" - used for saving address
	)
		internal
		returns (
			// string memory contractName // Name of the *new* v4 implementation (optional if only used for validation)
			address proxyAddress
		)
	{
		address proxyAdmin = deployProxyAdmin(); // Get or deploy the v4 admin

		if (existingProxy == address(0)) {
			// Deploy new v4 proxy
			console.log("Deploying new V4 Transparent proxy for", contractStorageKey);
			proxyAddress = deployProxy(implementation, proxyAdmin, initData);
			// Save the new proxy address using DeploymentUtils function
			saveAddress(contractStorageKey, proxyAddress);
			console.log(contractStorageKey, "V4 Proxy deployed at:", proxyAddress);
		} else {
			// Upgrade existing v4 proxy
			console.log("Upgrading V4 Transparent proxy for", contractStorageKey, "at", existingProxy);
			// validateUpgrade(contractName); // Optional: Validate v4 -> v4 upgrade
			upgradeProxy(existingProxy, implementation, proxyAdmin);
			proxyAddress = existingProxy; // Address doesn't change on upgrade
			console.log(contractStorageKey, "V4 Proxy upgraded.");
		}
		return proxyAddress;
	}

	// Keep v4 upgradeProxy logic
	function upgradeProxy(address proxy, address implementation, address admin) internal {
		ProxyAdmin(admin).upgrade(ITransparentUpgradeableProxy(proxy), implementation);
	}
}
