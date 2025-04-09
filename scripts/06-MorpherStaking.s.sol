//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";


// --- Import and Inherit from DeployOrUpgradeV5 ---
import {DeployOrUpgradeV5} from "./deployOrUpgradeV5.sol";

//morpher contracts
import {MorpherStaking} from "../contracts/MorpherStaking.sol"; // Use adapted v5 contract
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol";
import {MorpherToken} from "../contracts/MorpherToken.sol"; // Use adapted v5 contract
import {MorpherState} from "../contracts/MorpherState.sol"; // Use adapted v5 contract

// --- Inherit from DeployOrUpgradeV5 ---
contract DeployMorpherStaking is DeployOrUpgradeV5 {

    string constant CONTRACT_KEY = "MorpherStaking";
    // Use fully qualified name or filename as required by the upgrades plugin
    string constant CONTRACT_NAME = "MorpherStaking.sol";

    function run() public {
        // Load dependencies
        address stateAddress = loadAddress("MorpherState");
        require(stateAddress != address(0), "V5 MorpherState must be deployed first");
        address accessControlAddress = loadAddress("MorpherAccessControl");
        require(accessControlAddress != address(0), "V5 AccessControl must be deployed first");
        address tokenAddress = loadAddress("MorpherToken");
        require(tokenAddress != address(0), "V5 MorpherToken must be deployed first");

        // Check if deploying fresh
        address existingProxy = loadAddress(CONTRACT_KEY);
        bool isNewDeployment = existingProxy == address(0);

        vm.startBroadcast();

        // Deploy or upgrade using the V5 UUPS logic
        address stakingProxy = deployOrUpgradeV5(
            CONTRACT_KEY,
            CONTRACT_NAME,
            // Ensure initializer signature matches the adapted v5 contract
            // Pass initial poolShareValue (134590000) and lastReward (1744036313) for migration
            abi.encodeCall(MorpherStaking.initialize, (stateAddress, uint256(134590000), uint256(1744036313))),
            bytes("") // No upgrade call data needed for this example
        );
 
        console.log("MorpherStaking V5 Proxy at:", stakingProxy);

        // Only set roles and initial configuration for new deployments
        if (isNewDeployment) {
            console.log("Performing initial configuration for MorpherStaking...");
            MorpherAccessControl accessControl = MorpherAccessControl(accessControlAddress);
            MorpherToken token = MorpherToken(tokenAddress);
            MorpherState state = MorpherState(stateAddress);
            MorpherStaking stakingContract = MorpherStaking(stakingProxy); // Use proxy address

            // Grant STAKINGADMIN role to deployer (or designated admin)
            address envStakingAdmin = vm.envOr("STAKING_ADMIN_ADDRESS", msg.sender);
            accessControl.grantRole(stakingContract.STAKINGADMIN_ROLE(), envStakingAdmin);
            console.log("Granted STAKINGADMIN_ROLE to:", envStakingAdmin);

            // Set initial interest rate (fetch from InterestRateManager instead?)
            // For now, keeping the direct setting as in v4 script
            stakingContract.setInterestRate(15000); // 0.015% daily interest rate
            console.log("Set initial interest rate.");

            // Grant token roles (MINTER/BURNER) to staking contract proxy
            accessControl.grantRole(token.BURNER_ROLE(), stakingProxy);
            accessControl.grantRole(token.MINTER_ROLE(), stakingProxy);
            console.log("Granted MINTER/BURNER roles to Staking contract.");

            // Set staking contract address in state
            state.setMorpherStakingAddress(payable(stakingProxy)); // Ensure setMorpherStaking takes payable if needed
            console.log("Set MorpherStaking address in MorpherState.");
        }

        vm.stopBroadcast();
    }
}
