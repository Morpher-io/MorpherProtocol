// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {DeployOrUpgradeV5} from "./deployOrUpgradeV5.sol"; // Assuming this is the correct base
import {MorpherSidechainToBaseMigration} from "../contracts/MorpherSidechainMigrationSelfcontained.sol";

// Minimal interface for the MorpherState contract to call grantAccess
interface IMorpherStateForAccess {
    function grantAccess(address _address) external;
    function getAdministrator() external view returns(address); // Needed to check if OWNER_ADDRESS is admin
}

contract DeploySidechainMigration is DeployOrUpgradeV5 {

    string constant MIGRATION_CONTRACT_KEY = "MorpherSidechainMigration";

    function run() external {
        // --- Load Environment Variables ---
        address ownerAddress = vm.envAddress("OWNER_ADDRESS");
        address stateAddress = vm.envAddress("STATE_ADDRESS");
        address oracleAddress = vm.envAddress("ORACLE_ADDRESS");
        uint256 targetChainId = vm.envUint("TARGET_CHAIN_ID");

        // --- Input Validation ---
        require(ownerAddress != address(0), "OWNER_ADDRESS env var not set");
        require(stateAddress != address(0), "STATE_ADDRESS env var not set");
        require(oracleAddress != address(0), "ORACLE_ADDRESS env var not set");
        require(targetChainId != 0, "TARGET_CHAIN_ID env var not set or is zero");

        // --- Check if OWNER_ADDRESS is the administrator on MorpherState ---
        // This assumes the state contract has a getAdministrator function
        // If the function name is different, adjust the interface and call below
        address currentAdmin = IMorpherStateForAccess(stateAddress).getAdministrator();
        require(currentAdmin == ownerAddress, "OWNER_ADDRESS is not the administrator on MorpherState");

        vm.startBroadcast();

        // --- Deploy Migration Contract ---
        console.log("Deploying MorpherSidechainToBaseMigration...");
        console.log("  State Address:", stateAddress);
        console.log("  Oracle Address:", oracleAddress);
        console.log("  Target Chain ID:", targetChainId);

        MorpherSidechainToBaseMigration migrationContract = new MorpherSidechainToBaseMigration(
            stateAddress,
            oracleAddress,
            targetChainId
        );
        address migrationContractAddress = address(migrationContract);
        console.log("Deployed MorpherSidechainToBaseMigration at:", migrationContractAddress);

        // --- Save Address ---
        saveAddress(MIGRATION_CONTRACT_KEY, migrationContractAddress);
        console.log("Saved contract address with key:", MIGRATION_CONTRACT_KEY);

        // --- Grant Access on State Contract ---
        console.log("Granting access for migration contract on MorpherState...");
        console.log("  Pranking as OWNER_ADDRESS:", ownerAddress);
        console.log("  Calling grantAccess on STATE_ADDRESS:", stateAddress);
        console.log("  Granting access to:", migrationContractAddress);

        vm.prank(ownerAddress);
        IMorpherStateForAccess(stateAddress).grantAccess(migrationContractAddress);

        console.log("Access granted successfully.");

        vm.stopBroadcast();
    }
}
