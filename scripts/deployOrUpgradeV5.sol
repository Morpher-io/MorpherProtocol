    //SPDX-License-Identifier: MIT
    pragma solidity ^0.8.20;

    import {DeploymentUtils} from "./DeploymentUtils.sol"; // Inherit common utils
    import {console} from "forge-std/console.sol";
    import {Upgrades} from "../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol"; // Use v5 Upgrades
    import {Options} from "../lib/openzeppelin-foundry-upgrades/src/Options.sol";

    // --- Remove v4 proxy imports ---

    abstract contract DeployOrUpgradeV5 is DeploymentUtils { // Inherit utils

        // --- Remove v4 specific helpers (deployProxyAdmin, deployProxy, upgradeProxy) ---

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
                proxyAddress = Upgrades.deployUUPSProxy(
                    implementationContractName,
                    initData,
                    opts
                );
                saveAddress(contractStorageKey, proxyAddress);
                console.log(contractStorageKey, "V5 Proxy deployed at:", proxyAddress);

            } else {
                // Upgrade existing UUPS proxy
                console.log("Upgrading V5 UUPS proxy for", contractStorageKey, "at", proxyAddress);
                console.log("New implementation contract:", implementationContractName);

                // Validate the upgrade (optional but recommended)
                // Set referenceContract in opts if not using @custom:oz-upgrades-from annotation
                opts.referenceContract = string.concat("contracts/prev/contracts/",implementationContractName); // Example
                // You might need to dynamically determine the previous version artifact path
                // For simplicity now, we rely on the @custom:oz-upgrades-from annotation in the contract
                // Upgrades.validateUpgrade(implementationContractName, opts); // Validate against previous version

                // Use upgradeProxy which handles deploying the new implementation and calling upgradeToAndCall
                Upgrades.upgradeProxy(
                    proxyAddress,
                    implementationContractName, // Name of the NEW implementation artifact
                    upgradeCallData, // Optional data for post-upgrade call
                    opts
                );
                console.log(contractStorageKey, "V5 Proxy upgraded.");
                // Proxy address remains the same
            }
            return proxyAddress;
        }
    }
