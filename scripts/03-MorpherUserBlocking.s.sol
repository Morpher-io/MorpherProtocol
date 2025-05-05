//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
// --- Import and Inherit from DeployOrUpgradeV5 ---
import {DeployOrUpgradeV5} from "./deployOrUpgradeV5.sol";

// Import the *adapted* v5 contracts
import {MorpherUserBlocking} from "../contracts/MorpherUserBlocking.sol";
import {MorpherState} from "../contracts/MorpherState.sol"; // Keep for setting address in state
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol"; // Keep for role granting

// --- Inherit from DeployOrUpgradeV5 ---
contract DeployMorpherUserBlocking is DeployOrUpgradeV5 {

    string constant CONTRACT_KEY = "MorpherUserBlocking";
    // Use fully qualified name or filename as required by the upgrades plugin
    string constant CONTRACT_NAME = "MorpherUserBlocking.sol";

    function run() public {
        // Load dependencies
        address stateProxyAddress = loadAddress("MorpherState");
        require(stateProxyAddress != address(0), "V5 MorpherState must be deployed first");
        address accessControlAddress = loadAddress("MorpherAccessControl"); // Needed for granting roles
         require(accessControlAddress != address(0), "V5 AccessControl must be deployed first");

        // Check if deploying fresh
        address existingProxy = loadAddress(CONTRACT_KEY);
        bool isNewDeployment = existingProxy == address(0);

        vm.startBroadcast();

        // Deploy or upgrade using the V5 UUPS logic
        address userBlockingProxy = deployOrUpgradeV5(
            CONTRACT_KEY,
            CONTRACT_NAME,
            // Ensure initializer signature matches the adapted v5 contract
            abi.encodeCall(MorpherUserBlocking.initialize, (stateProxyAddress)),
            bytes("") // No upgrade call data needed for this example
        );

        console.log("MorpherUserBlocking V5 Proxy at:", userBlockingProxy);

        // Set UserBlocking address in State and grant roles if this is a new deployment
        if (isNewDeployment) {
            console.log("Setting MorpherUserBlocking address in MorpherState...");
            MorpherState(stateProxyAddress).setMorpherUserBlocking(userBlockingProxy);

            // Grant USERBLOCKINGADMIN_ROLE
            console.log("Granting initial roles on AccessControl for MorpherUserBlocking...");
            MorpherAccessControl accessControl = MorpherAccessControl(accessControlAddress);
            bytes32 userBlockingAdminRole = keccak256("USERBLOCKINGADMIN_ROLE"); // As defined in MorpherUserBlocking

            // Deployer does not need this role on Base, commented out.
            // // Grant role to deployer
            // accessControl.grantRole(userBlockingAdminRole, msg.sender);
            // console.log("Granted USERBLOCKINGADMIN_ROLE to deployer:", msg.sender);

            // Grant role to environment address if specified
            address envUserBlockingAdmin = vm.envOr("USERBLOCKING_ADMIN", address(0));
            if (envUserBlockingAdmin != address(0) && envUserBlockingAdmin != msg.sender) {
                accessControl.grantRole(userBlockingAdminRole, envUserBlockingAdmin);
                 console.log("Granted USERBLOCKINGADMIN_ROLE to env address:", envUserBlockingAdmin);
            }
        }

        vm.stopBroadcast();
    }
}
