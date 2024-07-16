//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Upgrades} from "openzeppelin-foundry-upgrades/LegacyUpgrades.sol";
import "forge-std/console.sol";


import {Script} from "forge-std/Script.sol";
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol";
import {ProxyAdmin} from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import { Options } from "openzeppelin-foundry-upgrades/Options.sol";


contract UpgradeProxyV4Versions is Script {
	function run() public {
		uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);
		ProxyAdmin admin = ProxyAdmin(0x3cFa9C5F4238fe6200b73038b1e6daBb5F6b8A0a);
		console.log(admin.owner());
		console.log(address(this));
		console.log(msg.sender);

string[] memory inputs = new string[](2);
inputs[0] = "node";
inputs[1] = "scripts/dl_source.js";

bytes memory res = vm.ffi(inputs);
// assertEq(string(res), "gm");
		//  Options memory opts;
		// Upgrades.validateUpgrade("MorpherAccessControl.sol", opts);
		// Upgrades.validateUpgrade("MorpherState.sol", opts);
	}
}
