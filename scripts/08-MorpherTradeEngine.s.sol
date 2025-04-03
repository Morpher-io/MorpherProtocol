//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// --- Import and Inherit from DeployOrUpgradeV5 ---
import {DeployOrUpgradeV5} from "./deployOrUpgradeV5.sol";

//morpher contracts
import {MorpherTradeEngine} from "../contracts/MorpherTradeEngine.sol"; // Use adapted v5 contract
import {MorpherState} from "../contracts/MorpherState.sol";
import {MorpherToken} from "../contracts/MorpherToken.sol"; // Use adapted v5 contract
import {MorpherStaking} from "../contracts/MorpherStaking.sol"; // Use adapted v5 contract
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol"; // Use adapted v5 contract

contract DeployMorpherTradeEngine is DeployOrUpgradeV5 {

    string constant CONTRACT_KEY = "MorpherTradeEngine";
    // Use fully qualified name or filename as required by the upgrades plugin
    string constant CONTRACT_NAME = "MorpherTradeEngine.sol:MorpherTradeEngine";

    function run() public {
        // Load dependencies
        address stateAddress = loadAddress("MorpherState");
        require(stateAddress != address(0), "V5 MorpherState must be deployed first");
        address accessControlAddress = loadAddress("MorpherAccessControl");
        require(accessControlAddress != address(0), "V5 AccessControl must be deployed first");
        address tokenAddress = loadAddress("MorpherToken");
        require(tokenAddress != address(0), "V5 MorpherToken must be deployed first");

        // Get configuration
        bool escrowEnabled = vm.envBool("ESCROW_ENABLED");
        uint256 deployedTimestamp = vm.envOr("DEPLOYED_TIMESTAMP", uint256(1613399217)); // Keep default or update

        // Check if deploying fresh
        address existingProxy = loadAddress(CONTRACT_KEY);
        bool isNewDeployment = existingProxy == address(0);

        vm.startBroadcast();

        // Deploy or upgrade using the V5 UUPS logic
        address tradeEngineProxy = deployOrUpgradeV5(
            CONTRACT_KEY,
            CONTRACT_NAME,
            // Ensure initializer signature matches the adapted v5 contract
            abi.encodeCall(MorpherTradeEngine.initialize, (stateAddress, escrowEnabled, deployedTimestamp)),
            bytes("") // No upgrade call data needed for this example
        );

        console.log("MorpherTradeEngine V5 Proxy at:", tradeEngineProxy);

        // Configure if this is a new deployment
        if (isNewDeployment) {
            console.log("Performing initial configuration for MorpherTradeEngine...");
            MorpherAccessControl accessControl = MorpherAccessControl(accessControlAddress);
            MorpherToken token = MorpherToken(tokenAddress);

            // Define roles using constants from the contract *type* or keccak256
            bytes32 burnerRole = token.BURNER_ROLE();
            bytes32 minterRole = token.MINTER_ROLE();
            bytes32 positionAdminRole = keccak256("POSITIONADMIN_ROLE"); // As defined in TradeEngine

            // Grant token roles to trade engine proxy
            accessControl.grantRole(burnerRole, tradeEngineProxy);
            accessControl.grantRole(minterRole, tradeEngineProxy);
            console.log("Granted MINTER/BURNER roles to TradeEngine.");

            // Grant position admin role to trade engine proxy (so it can call setPosition on itself?) - Check if this is correct logic
            // Or should an external admin have this role? Assuming external admin for now.
            address envPositionAdmin = vm.envOr("POSITION_ADMIN_ADDRESS", msg.sender);
            accessControl.grantRole(positionAdminRole, envPositionAdmin);
            console.log("Granted POSITIONADMIN_ROLE to:", envPositionAdmin);

            // Set TradeEngine address in State
            MorpherState(stateAddress).setMorpherTradeEngine(tradeEngineProxy);
            console.log("Set MorpherTradeEngine address in MorpherState.");
        }

        vm.stopBroadcast();
    }
}
