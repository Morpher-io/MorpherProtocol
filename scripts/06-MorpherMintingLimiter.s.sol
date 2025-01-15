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
import {MorpherMintingLimiter} from "../contracts/MorpherMintingLimiter.sol";
import {MorpherState} from "../contracts/MorpherState.sol";
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol";
import {MorpherToken} from "../contracts/MorpherToken.sol";

contract DeployMorpherMintingLimiter is DeployOrUpgrade {
    using stdJson for string;

    function run() public {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);

        // Load State address - required for MintingLimiter initialization
        address stateAddress = loadAddress("MorpherState");
        require(stateAddress != address(0), "MorpherState must be deployed first");

        // Get configuration from environment
        uint256 mintLimitPerUser = vm.envOr("MINTING_LIMIT_PER_USER", uint256(0));
        uint256 mintLimitDaily = vm.envOr("MINTING_LIMIT_DAILY", uint256(0));
        uint256 timelockPeriodMinting = vm.envOr("MINTING_TIME_LOCK_PERIOD", uint256(0));

        // Deploy MorpherMintingLimiter
        MorpherMintingLimiter implementation = new MorpherMintingLimiter(
            stateAddress,
            mintLimitPerUser,
            mintLimitDaily,
            timelockPeriodMinting
        );
        
        address existingMintingLimiter = loadAddress("MorpherMintingLimiter");
        address mintingLimiter = deployOrUpgrade(
            existingMintingLimiter,
            address(implementation),
            "",  // No initialization needed as constructor handles it
            "MorpherMintingLimiter.sol"
        );
        
        saveAddress("MorpherMintingLimiter", mintingLimiter);
        console.log("MorpherMintingLimiter at:", mintingLimiter);

        // Configure State and Token permissions if this is a new deployment
        if (existingMintingLimiter == address(0)) {
            MorpherState state = MorpherState(stateAddress);
            state.setMorpherMintingLimiter(mintingLimiter);

            // Grant minting permissions
            address tokenAddress = loadAddress("MorpherToken");
            if (tokenAddress != address(0)) {
                MorpherToken token = MorpherToken(tokenAddress);
                MorpherAccessControl accessControl = MorpherAccessControl(loadAddress("MorpherAccessControl"));
                accessControl.grantRole(token.MINTER_ROLE(), mintingLimiter);
            }
        }
        
        vm.stopBroadcast();
    }
}
