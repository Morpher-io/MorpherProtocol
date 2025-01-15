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
import {MorpherStaking} from "../contracts/MorpherStaking.sol";
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol";
import {MorpherToken} from "../contracts/MorpherToken.sol";
import {MorpherState} from "../contracts/MorpherState.sol";

contract DeployMorpherStaking is DeployOrUpgrade {
    using stdJson for string;

    function run() public {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);

        // Load State address - required for Staking initialization
        address stateAddress = loadAddress("MorpherState");
        require(stateAddress != address(0), "MorpherState must be deployed first");

        // Deploy or upgrade MorpherStaking
        address existingStaking = loadAddress("MorpherStaking");
        MorpherStaking implementation = new MorpherStaking();
        
        address staking = deployOrUpgrade(
            existingStaking,
            address(implementation),
            abi.encodeCall(MorpherStaking.initialize, (stateAddress)),
            "MorpherStaking.sol"
        );
        
        saveAddress("MorpherStaking", staking);
        console.log("MorpherStaking at:", staking);

        // Only set roles and initial configuration for new deployments
        if (existingStaking == address(0)) {
            MorpherAccessControl accessControl = MorpherAccessControl(loadAddress("MorpherAccessControl"));
            MorpherToken token = MorpherToken(loadAddress("MorpherToken"));
            MorpherState state = MorpherState(stateAddress);
            MorpherStaking stakingContract = MorpherStaking(staking);

            // Grant STAKINGADMIN role to deployer
            accessControl.grantRole(stakingContract.STAKINGADMIN_ROLE(), vm.addr(deployerPrivateKey));

            // Set initial interest rate
            stakingContract.setInterestRate(15000); // 0.015% daily interest rate

            // Grant token roles to staking contract
            accessControl.grantRole(token.BURNER_ROLE(), staking);
            accessControl.grantRole(token.MINTER_ROLE(), staking);

            // Set staking contract in state
            state.setMorpherStaking(staking);
        }
        
        vm.stopBroadcast();
    }
}
