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

        // Deploy MorpherAccessControl if not already deployed
        if (addrs.accessControl == address(0)) {
            // Validate implementation for upgrade compatibility
            validateUpgrade("MorpherAccessControl.sol");
            
            // Deploy implementation
            MorpherAccessControl implementation = new MorpherAccessControl();
            
            // Deploy proxy
            addrs.accessControl = deployProxy(
                address(implementation),
                addrs.proxyAdmin,
                abi.encodeCall(MorpherAccessControl.initialize, ())
            );
            
            console.log("Deployed MorpherAccessControl at:", addrs.accessControl);
        }

        // Save updated addresses
        saveAddresses(addrs);
        
        vm.stopBroadcast();
    }
}
