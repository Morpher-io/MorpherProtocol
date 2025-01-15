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
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol";


contract DeployMorpherAccessControl is DeployOrUpgrade {
    using stdJson for string;

    function run() public {
        vm.startBroadcast();

        // Deploy or upgrade MorpherAccessControl
        address existingAccessControl = loadAddress("MorpherAccessControl");
        MorpherAccessControl implementation = new MorpherAccessControl();
        
        address accessControl = deployOrUpgrade(
            existingAccessControl,
            address(implementation),
            abi.encodeCall(MorpherAccessControl.initialize, ()),
            "MorpherAccessControl.sol"
        );
        
        saveAddress("MorpherAccessControl", accessControl);
        console.log("MorpherAccessControl at:", accessControl);
        
        vm.stopBroadcast();
    }
}
