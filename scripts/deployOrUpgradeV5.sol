//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeploymentUtils} from "./DeploymentUtils.sol"; // Inherit common utils
import {console} from "forge-std/console.sol";
import {Upgrades, UnsafeUpgrades} from "../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol"; // Use v5 Upgrades
import {Options} from "../lib/openzeppelin-foundry-upgrades/src/Options.sol";
import {strings} from "solidity-stringutils/src/strings.sol";

// --- Remove v4 proxy imports ---

abstract contract DeployOrUpgradeV5 is
	DeploymentUtils // Inherit utils
    
{
	// --- Remove v4 specific helpers (deployProxyAdmin, deployProxy, upgradeProxy) ---
    using strings for *;

    function deployImplementation() internal virtual returns (address);

	// --- V5 deploy/upgrade function ---
	function deployOrUpgradeV5(
		string memory contractStorageKey, // e.g., "MorpherState" - used for loading/saving address
		string memory implementationContractName, // e.g., "MorpherState.sol:MorpherState" or "MorpherState.sol"
		bytes memory initData, // Data for initializer call ONLY on first deployment
		bytes memory upgradeCallData // Data for upgrade call ONLY on subsequent upgrades (often "")
	) internal returns (address proxyAddress) {
		Options memory opts; // Configure options if needed (e.g., unsafe flags, Defender)

		// Load existing proxy address using the specific key
		proxyAddress = loadAddress(contractStorageKey);

		if (proxyAddress == address(0)) {
			// Deploy new UUPS proxy
			console.log("Deploying new V5 UUPS proxy for", implementationContractName);
			// The Upgrades library handles deploying the implementation and proxy
			proxyAddress = Upgrades.deployUUPSProxy(implementationContractName, initData, opts);
			saveAddress(contractStorageKey, proxyAddress);
			console.log(contractStorageKey, "V5 Proxy deployed at:", proxyAddress);
		} else {
			// Upgrade existing UUPS proxy
			console.log("Upgrading V5 UUPS proxy for", contractStorageKey, "at", proxyAddress);
			console.log("New implementation contract:", implementationContractName);

			// Validate the upgrade by pointing to the previous contract version artifact.
			opts.referenceContract = _getPrevArtifactPath(implementationContractName);
			opts.unsafeAllow = "external-library-linking";

			Upgrades.validateUpgrade(implementationContractName, opts);

			// Deploy the new implementation via the overridden function, which handles library linking.
			address newImplementationAddress = deployImplementation();

			// Manually upgrade the proxy to point to the new implementation
			UnsafeUpgrades.upgradeProxy(
				proxyAddress,
				newImplementationAddress,
				upgradeCallData
			);
			console.log(contractStorageKey, "V5 Proxy upgraded.");
		}
		return proxyAddress;
	}

	/**
	* Despite contracts are in the prev folder, upon building, 
	* they will land in the build/contracts/... folder. 
	* The contracts not in the contracts/prev folder will land in the build folder
	* It looks counter intuitive, but the path is correct to get the reference contract artifact.
	*/
	function _getPrevArtifactPath(string memory fileName) private pure returns (string memory) {
		strings.slice memory name = fileName.toSlice();
		string memory contractName = name.until(".sol".toSlice()).toString();
		return string.concat("contracts/", fileName, ":", contractName);
	}

}
