// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./deployOrUpgrade.sol";
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol";
import {console} from "forge-std/console.sol";

contract DeployV5 is DeployOrUpgrade {
    function run() public {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);

        // Load existing addresses
        Addresses memory addrs = loadAddresses();

        // Deploy ProxyAdmin if not already deployed
        if (addrs.proxyAdmin == address(0)) {
            addrs.proxyAdmin = deployProxyAdmin();
            console.log("Deployed ProxyAdmin at:", addrs.proxyAdmin);
        }

        // Deploy or upgrade MorpherAccessControl
        if (addrs.accessControl == address(0)) {
            // Deploy implementation
            MorpherAccessControl implementation = new MorpherAccessControl();
            
            // Deploy proxy
            addrs.accessControl = deployProxy(
                address(implementation),
                addrs.proxyAdmin,
                abi.encodeCall(MorpherAccessControl.initialize, ())
            );
            
            console.log("Deployed MorpherAccessControl at:", addrs.accessControl);
        } else {
            // For upgrades, validate compatibility
            validateUpgrade("MorpherAccessControl.sol");
            
            // Deploy new implementation
            MorpherAccessControl newImplementation = new MorpherAccessControl();
            
            // Upgrade proxy to new implementation
            upgradeProxy(
                addrs.accessControl,
                address(newImplementation),
                addrs.proxyAdmin
            );
            
            console.log("Upgraded MorpherAccessControl at:", addrs.accessControl);
        }

        // Save updated addresses
        saveAddresses(addrs);
        
        vm.stopBroadcast();
    }
}
