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
import {MorpherAdmin} from "../contracts/MorpherAdmin.sol";
import {MorpherState} from "../contracts/MorpherState.sol";

contract DeployMorpherAdmin is DeployOrUpgrade {
    using stdJson for string;

    function run() public {
        vm.startBroadcast();

        // Load State address - required for Admin initialization
        address stateAddress = loadAddress("MorpherState");
        require(stateAddress != address(0), "MorpherState must be deployed first");

        // Deploy or upgrade MorpherAdmin
        address existingAdmin = loadAddress("MorpherAdmin");
        MorpherAdmin implementation = new MorpherAdmin();
        
        address admin = deployOrUpgrade(
            existingAdmin,
            address(implementation),
            abi.encodeCall(
                MorpherAdmin.initialize,
                (stateAddress)
            ),
            "MorpherAdmin.sol"
        );
        
        saveAddress("MorpherAdmin", admin);
        console.log("MorpherAdmin at:", admin);
        
        vm.stopBroadcast();
    }
}
