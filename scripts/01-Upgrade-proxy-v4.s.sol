//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Upgrades} from "openzeppelin-foundry-upgrades/LegacyUpgrades.sol";
import "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";



import {Script} from "forge-std/Script.sol";
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol";
import {ProxyAdmin} from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import { Options } from "openzeppelin-foundry-upgrades/Options.sol";

import {MorpherOracle} from "../contracts/MorpherOracle.sol";
import {ITransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";


contract UpgradeProxyV4Versions is Script {
    // address constant CHEATCODE_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

	function run() public {
		// uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
        // vm.startBroadcast(deployerPrivateKey);
		// _tryUpBalance(msg.sender);
		vm.startBroadcast();
		ProxyAdmin admin = ProxyAdmin(0x3cFa9C5F4238fe6200b73038b1e6daBb5F6b8A0a);
		console.log(admin.owner());
		console.log(address(this));
		console.log(msg.sender);
		console.log(address(msg.sender).balance);


		 Options memory opts;
		Upgrades.validateUpgrade("MorpherAccessControl.sol", opts);
		Upgrades.validateUpgrade("MorpherState.sol", opts);
		Upgrades.validateUpgrade("MorpherToken.sol", opts);
		Upgrades.validateUpgrade("MorpherTradeEngine.sol", opts);
		Upgrades.validateUpgrade("MorpherOracle.sol", opts);

		address oracleProxyAddress = 0x21Fd95b46FC655BfF75a8E74267Cfdc7efEBdb6A;
		MorpherOracle newOracle = new MorpherOracle();
		admin.upgrade(ITransparentUpgradeableProxy(oracleProxyAddress), address(newOracle));

	}
}
