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
import {MorpherUserBlocking} from "../contracts/MorpherUserBlocking.sol";
import {MorpherState} from "../contracts/MorpherState.sol";

contract DeployMorpherUserBlocking is DeployOrUpgrade {
    using stdJson for string;

    function run() public {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);

        // Load State address - required for UserBlocking initialization
        address stateAddress = loadAddress("MorpherState");
        require(stateAddress != address(0), "MorpherState must be deployed first");

        // Deploy or upgrade MorpherUserBlocking
        address existingUserBlocking = loadAddress("MorpherUserBlocking");
        MorpherUserBlocking implementation = new MorpherUserBlocking();
        
        address userBlocking = deployOrUpgrade(
            existingUserBlocking,
            address(implementation),
            abi.encodeCall(MorpherUserBlocking.initialize, (stateAddress)),
            "MorpherUserBlocking.sol"
        );
        
        saveAddress("MorpherUserBlocking", userBlocking);
        console.log("MorpherUserBlocking at:", userBlocking);

        // Set UserBlocking in State if this is a new deployment
        if (existingUserBlocking == address(0)) {
            MorpherState state = MorpherState(stateAddress);
            state.setMorpherUserBlocking(userBlocking);
        }
        
        vm.stopBroadcast();
    }
}
