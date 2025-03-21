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
import {MorpherState} from "../contracts/MorpherState.sol";
import {MorpherToken} from "../contracts/MorpherToken.sol";
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol";

contract DeployMorpherToken is DeployOrUpgrade {
	using stdJson for string;

	function run() public {
		vm.startBroadcast();

		// Load AccessControl address - required for Token initialization
		address accessControlAddress = loadAddress("MorpherAccessControl");
		address stateAddress = loadAddress("MorpherState");
		require(accessControlAddress != address(0), "AccessControl must be deployed first");
		require(stateAddress != address(0), "MorpherState must be deployed first");

		// Deploy or upgrade MorpherToken
		address existingToken = loadAddress("MorpherToken");
		MorpherToken implementation = new MorpherToken();

		address token = deployOrUpgrade(
			existingToken,
			address(implementation),
			abi.encodeCall(MorpherToken.initialize, (accessControlAddress, stateAddress)),
			"MorpherToken.sol"
		);

		saveAddress("MorpherToken", token);
		console.log("MorpherToken at:", token);

		// Only set roles and mint for new deployments
		if (existingToken == address(0)) {
			MorpherAccessControl accessControl = MorpherAccessControl(accessControlAddress);
			MorpherToken tokenContract = MorpherToken(token);

			// Grant initial roles to deployer
			accessControl.grantRole(implementation.PAUSER_ROLE(), msg.sender);
			accessControl.grantRole(implementation.ADMINISTRATOR_ROLE(), msg.sender);
			accessControl.grantRole(implementation.MINTER_ROLE(), msg.sender);

			// Get treasury address from environment or use deployer
			address treasuryAddress = vm.envOr("MORPHER_TREASURY", msg.sender);

			// Mint tokens and set other chain balance
			// uint256 _sideChainMint = 575_000_000 ether;
			// tokenContract.setTotalTokensOnOtherChain(_sideChainMint);

			uint256 _mainChainMint = 425_000_000 ether;
			tokenContract.mint(treasuryAddress, _mainChainMint);

			// Configure State with token address
			if (stateAddress != address(0)) {
				MorpherState state = MorpherState(stateAddress);
				state.setMorpherToken(token);
			}

			tokenContract.setDailyMintedTransferLimit(200_000 ether);

			// Revoke minter role from deployer
			accessControl.revokeRole(implementation.MINTER_ROLE(), msg.sender);
		} else {
			//update MorpherState if its not set yet
			if (address(MorpherToken(existingToken).morpherState()) == address(0)) {
				MorpherToken(existingToken).setMorpherStateAddress(stateAddress);
			}

			MorpherToken(existingToken).setDailyMintedTransferLimit(200_000 ether);
		}

		vm.stopBroadcast();
	}
}
