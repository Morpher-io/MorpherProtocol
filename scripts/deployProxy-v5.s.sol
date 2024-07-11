//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-foundry-upgrades/Upgrades.sol";

import {Script} from "forge-std/Script.sol";
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol";

contract UpgradeProxyV4Versions is Script {
	function run() public {
		address proxy = Upgrades.deployTransparentProxy("MorpherAccessControl.sol", 0x720B9742632566b76B53B60Eee8d5FDC20aC74bE,     abi.encodeCall(MorpherAccessControl.initialize));
         
	}
}
