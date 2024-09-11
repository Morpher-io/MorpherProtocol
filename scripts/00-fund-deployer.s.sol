//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Upgrades} from "openzeppelin-foundry-upgrades/LegacyUpgrades.sol";
import "forge-std/console.sol";

import {Script} from "forge-std/Script.sol";


contract UpgradeProxyV4Versions is Script {
	function run() public {
        vm.startBroadcast();

        address deployer = 0x720B9742632566b76B53B60Eee8d5FDC20aC74bE;
        console.log(deployer.balance);
		vm.deal(deployer, 1 ether);
        console.log(deployer.balance);
        vm.stopBroadcast();
	}
}
