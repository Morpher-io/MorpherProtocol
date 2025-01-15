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
import {MorpherAirdrop} from "../contracts/MorpherAirdrop.sol";
import {MorpherToken} from "../contracts/MorpherToken.sol";

contract DeployMorpherAirdrop is DeployOrUpgrade {
    using stdJson for string;

    function run() public {
        vm.startBroadcast();

        // Load Token address - required for Airdrop initialization
        address tokenAddress = loadAddress("MorpherToken");
        require(tokenAddress != address(0), "MorpherToken must be deployed first");

        // Get configuration from environment
        address airdropAdmin = vm.envOr("AIRDROP_ADMIN", msg.sender);
        address coldStorageOwner = vm.envOr("MORPHER_OWNER", msg.sender);

        // Deploy or upgrade MorpherAirdrop
        address existingAirdrop = loadAddress("MorpherAirdrop");
        MorpherAirdrop implementation = new MorpherAirdrop();
        
        address airdrop = deployOrUpgrade(
            existingAirdrop,
            address(implementation),
            abi.encodeCall(
                MorpherAirdrop.initialize,
                (airdropAdmin, tokenAddress, coldStorageOwner)
            ),
            "MorpherAirdrop.sol"
        );
        
        saveAddress("MorpherAirdrop", airdrop);
        console.log("MorpherAirdrop at:", airdrop);
        
        vm.stopBroadcast();
    }
}
