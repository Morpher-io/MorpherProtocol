//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Upgrades} from "../lib/openzeppelin-foundry-upgrades/src/LegacyUpgrades.sol";
import {Options} from "../lib/openzeppelin-foundry-upgrades/src/Options.sol"; // Keep Options if used by V5 helper

// --- Import and Inherit from DeployOrUpgradeV5 ---
import {DeployOrUpgradeV5} from "./deployOrUpgradeV5.sol";

//morpher contracts
import {MorpherMintingLimiter} from "../contracts/MorpherMintingLimiter.sol"; // Use adapted v5 contract
import {MorpherState} from "../contracts/MorpherState.sol"; // Use adapted v5 contract
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol"; // Use adapted v5 contract
import {MorpherToken} from "../contracts/MorpherToken.sol"; // Use adapted v5 contract

// --- Inherit from DeployOrUpgradeV5 ---
contract DeployMorpherMintingLimiter is DeployOrUpgradeV5 {

    string constant CONTRACT_KEY = "MorpherMintingLimiter";
    // Use fully qualified name or filename as required by the upgrades plugin
    string constant CONTRACT_NAME = "contracts/MorpherMintingLimiter.sol:MorpherMintingLimiter";

    function run() public {
        // Load dependencies
        address stateAddress = loadAddress("MorpherState");
        require(stateAddress != address(0), "V5 MorpherState must be deployed first");
        address accessControlAddress = loadAddress("MorpherAccessControl");
        require(accessControlAddress != address(0), "V5 AccessControl must be deployed first");
        address tokenAddress = loadAddress("MorpherToken");
        require(tokenAddress != address(0), "V5 MorpherToken must be deployed first");

        // Get configuration from environment
        uint256 mintLimitPerUser = vm.envOr("MINTING_LIMIT_PER_USER", uint256(0));
        uint256 mintLimitDaily = vm.envOr("MINTING_LIMIT_DAILY", uint256(0));
        uint256 timelockPeriodMinting = vm.envOr("MINTING_TIME_LOCK_PERIOD", uint256(0));

        // Check if deploying fresh
        address existingProxy = loadAddress(CONTRACT_KEY);
        bool isNewDeployment = existingProxy == address(0);

        vm.startBroadcast();

        // Deploy or upgrade using the V5 UUPS logic
        address mintingLimiterProxy = deployOrUpgradeV5(
            CONTRACT_KEY,
            CONTRACT_NAME,
            // Ensure initializer signature matches the adapted v5 contract
            abi.encodeCall(
                MorpherMintingLimiter.initialize,
                (stateAddress, mintLimitPerUser, mintLimitDaily, timelockPeriodMinting)
            ),
            bytes("") // No upgrade call data needed for this example
        );

        console.log("MorpherMintingLimiter V5 Proxy at:", mintingLimiterProxy);

        // Configure State and Token permissions if this is a new deployment
        if (isNewDeployment) {
            console.log("Performing initial configuration for MorpherMintingLimiter...");
            MorpherState state = MorpherState(stateAddress);
            state.setMorpherMintingLimiter(mintingLimiterProxy);
            console.log("Set MorpherMintingLimiter address in MorpherState.");

            // Grant minting permissions to the limiter proxy
            MorpherToken token = MorpherToken(tokenAddress);
            MorpherAccessControl accessControl = MorpherAccessControl(accessControlAddress);
            accessControl.grantRole(token.MINTER_ROLE(), mintingLimiterProxy);
            console.log("Granted MINTER_ROLE to MintingLimiter contract.");
        }

        vm.stopBroadcast();
    }
}
