//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";

// --- Import and Inherit from DeployOrUpgradeV5 ---
import {DeployOrUpgradeV5} from "./deployOrUpgradeV5.sol";

//morpher contracts
import {MorpherInterestRateManager} from "../contracts/MorpherInterestRateManager.sol"; // Use adapted v5 contract
import {MorpherState} from "../contracts/MorpherState.sol"; // Use adapted v5 contract

// --- Inherit from DeployOrUpgradeV5 ---
contract DeployMorpherInterestRateManager is DeployOrUpgradeV5 {

    string constant CONTRACT_KEY = "MorpherInterestRateManager";
    // Use fully qualified name or filename as required by the upgrades plugin
    string constant CONTRACT_NAME = "MorpherInterestRateManager.sol";

    function run() public {
        // Load dependencies
        address stateAddress = loadAddress("MorpherState");
        require(stateAddress != address(0), "V5 MorpherState must be deployed first");

        // Check if deploying fresh
        address existingProxy = loadAddress(CONTRACT_KEY);
        bool isNewDeployment = existingProxy == address(0);

        vm.startBroadcast();

        // Deploy or upgrade using the V5 UUPS logic
        address interestRateManagerProxy = deployOrUpgradeV5(
            CONTRACT_KEY,
            CONTRACT_NAME,
            // Ensure initializer signature matches the adapted v5 contract
            abi.encodeCall(MorpherInterestRateManager.initialize, (stateAddress)),
            bytes("") // No upgrade call data needed for this example
        );

        console.log("MorpherInterestRateManager V5 Proxy at:", interestRateManagerProxy);

        // Configure if this is a new deployment
        if (isNewDeployment) {
            console.log("Performing initial configuration for MorpherInterestRateManager...");
            MorpherInterestRateManager manager = MorpherInterestRateManager(interestRateManagerProxy); // Use proxy address

            // Set initial interest rates as per BaseSetup
            uint256 initialTimestamp = 1617094819; // FIRST_RATE_TS from test
            manager.addInterestRate(15000, initialTimestamp);
            console.log("Added initial interest rate (15000).");
            manager.addInterestRate(30000, 1644491427); // SECOND_RATE_TS from test
            console.log("Added second interest rate (30000).");

            // Set InterestRateManager address in State
            MorpherState(stateAddress).setMorpherInterestRateManager(interestRateManagerProxy);
            console.log("Set MorpherInterestRateManager address in MorpherState.");
        }

        vm.stopBroadcast();
    }
}
