//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
// --- Import and Inherit from DeployOrUpgradeV5 ---
import {DeployOrUpgradeV5} from "./deployOrUpgradeV5.sol";

// Import the *adapted* v5 contract
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol";


// --- Inherit from DeployOrUpgradeV5 ---
contract DeployMorpherAccessControl is DeployOrUpgradeV5 {

    string constant CONTRACT_KEY = "MorpherAccessControl";
    // Use fully qualified name or filename as required by the upgrades plugin
    string constant CONTRACT_NAME = "MorpherAccessControl.sol";

    function run() public {
        // Check if deploying fresh by seeing if the address already exists
        address existingProxy = loadAddress(CONTRACT_KEY);
        bool isNewDeployment = existingProxy == address(0);

        vm.startBroadcast();

        // Deploy or upgrade using the V5 UUPS logic
        address accessControlProxy = deployOrUpgradeV5(
            CONTRACT_KEY,
            CONTRACT_NAME,
            abi.encodeCall(MorpherAccessControl.initialize, ()), // Ensure this matches v5 initializer
            bytes("") // No upgrade call data needed for this example
        );

        console.log("MorpherAccessControl V5 Proxy at:", accessControlProxy);

        // Grant PROXYUPDATER_ROLE to environment address if specified on *first* deployment
        // The deployer already gets the role in the initializer
        if (isNewDeployment) {
            address envProxyUpdater = vm.envOr("PROXY_UPDATER_ADDRESS", address(0));
            if (envProxyUpdater != address(0) && envProxyUpdater != msg.sender) {
                console.log("Granting PROXYUPDATER_ROLE to env address:", envProxyUpdater);
                MorpherAccessControl(accessControlProxy).grantRole(
                    keccak256("PROXYUPDATER_ROLE"), // Access constant via type
                    envProxyUpdater
                );
            }
             // Grant DEFAULT_ADMIN_ROLE to environment address if specified on *first* deployment
            address envAdmin = vm.envOr("DEFAULT_ADMIN_ADDRESS", address(0));
             if (envAdmin != address(0) && envAdmin != msg.sender) {
                console.log("Granting DEFAULT_ADMIN_ROLE to env address:", envAdmin);
                MorpherAccessControl(accessControlProxy).grantRole(
                    MorpherAccessControl(accessControlProxy).DEFAULT_ADMIN_ROLE(), // Access via instance
                    envAdmin
                );
            }
        }

        vm.stopBroadcast();
    }
}
