//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Upgrades} from "openzeppelin-foundry-upgrades/LegacyUpgrades.sol";

import {Script} from "forge-std/Script.sol";
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol";

contract UpgradeProxyV4Versions is Script {
    function run() public {
       address proxy = Upgrades.deployTransparentProxy(
    "MyContract.sol",
    INITIAL_OWNER_ADDRESS_FOR_PROXY_ADMIN,
    abi.encodeCall(MyContract.initialize, ("arguments for the initialize function"))
);
    }
}