
//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Upgrades} from "openzeppelin-foundry-upgrades/LegacyUpgrades.sol";
import "forge-std/console.sol";

import {Script} from "forge-std/Script.sol";

contract Bla is Script {
string memory root = vm.projectRoot();
		string memory path = string.concat(root, "/docs/", String.toString(block.chainid), "_addresses.json");
		bool fileExists = vm.isFile(path);
		if (fileExists) {
			string memory json = vm.readFile(path);
		}
}