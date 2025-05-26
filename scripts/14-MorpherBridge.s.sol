//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {DeployOrUpgradeV5} from "./deployOrUpgradeV5.sol";

// Morpher contracts
import {MorpherBridge} from "../contracts/MorpherBridge.sol";
import {MorpherState} from "../contracts/MorpherState.sol";
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol"; // For roles

// Interfaces
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract DeployMorpherBridge is DeployOrUpgradeV5 {
    string constant CONTRACT_KEY = "MorpherBridge";
    string constant CONTRACT_NAME = "MorpherBridge.sol"; // Adjust if filename differs

    function run() public {
        // Load dependencies
        address stateAddress = loadAddress("MorpherState");
        require(stateAddress != address(0), "V5 MorpherState must be deployed first");
        address accessControlAddress = loadAddress("MorpherAccessControl");
        require(accessControlAddress != address(0), "V5 MorpherAccessControl must be deployed first");

        // Get configuration
        bool recoveryEnabled = vm.envOr("BRIDGE_RECOVERY_ENABLED", false);

        address swapRouterAddress;
        if (block.chainid == 8453) { // Base Mainnet
            swapRouterAddress = 0x2626664c2603336E57B271c5C0b26F421741e481; // Uniswap V3 SwapRouter on Base Mainnet
        } else if (block.chainid == 84532) { // Base Sepolia
            swapRouterAddress = 0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4; // Uniswap V3 SwapRouter on Base Sepolia
        } else if (block.chainid == 11155111) { // Sepolia (common testnet)
            swapRouterAddress = 0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E; // Uniswap V3 SwapRouter on Sepolia
        } else if (block.chainid == 1337 || block.chainid == 31337) { // Local anvil/hardhat
             // For local testing, you might deploy a mock or use a known testnet deployment
            console.log("Using default/mock SwapRouter address for local chain:", address(0xDEADBEEF));
            swapRouterAddress = address(0xDEADBEEF); // Placeholder - replace with actual mock if needed for local deploy script
        }
        else {
            revert("Unsupported chainId for SwapRouter address");
        }
        require(swapRouterAddress != address(0), "SwapRouter address not set for this chainId");


        // Check if deploying fresh
        address existingProxy = loadAddress(CONTRACT_KEY);
        bool isNewDeployment = existingProxy == address(0);

        vm.startBroadcast();

        // Deploy or upgrade using the V5 UUPS logic
        address bridgeProxy = deployOrUpgradeV5(
            CONTRACT_KEY,
            CONTRACT_NAME,
            abi.encodeCall(MorpherBridge.initialize, (stateAddress, recoveryEnabled, ISwapRouter(swapRouterAddress))),
            bytes("") // No upgrade call data needed for this example
        );

        saveAddress(CONTRACT_KEY, bridgeProxy);
        console.log("MorpherBridge V5 Proxy at:", bridgeProxy);

        MorpherAccessControl accessControl = MorpherAccessControl(accessControlAddress);

        // Configure if this is a new deployment or if addresses need updating
        if (isNewDeployment) {
            console.log("Performing initial configuration for MorpherBridge...");

            // Set MorpherBridge address in MorpherState
            MorpherState(stateAddress).setMorpherBridgeAddress(bridgeProxy);
            console.log("Set MorpherBridge address in MorpherState.");

            // Grant ADMINISTRATOR_ROLE on the bridge
            address bridgeAdmin = vm.envOr("BRIDGE_ADMIN_ADDRESS", msg.sender);
            accessControl.grantRole(MorpherBridge(bridgeProxy).ADMINISTRATOR_ROLE(), bridgeAdmin);
            console.log("Granted ADMINISTRATOR_ROLE on MorpherBridge to:", bridgeAdmin);

            // Grant SIDECHAINOPERATOR_ROLE on the bridge
            address sidechainOperator = vm.envOr("SIDECHAIN_OPERATOR_ADDRESS", msg.sender); // Default to deployer
            accessControl.grantRole(MorpherBridge(bridgeProxy).SIDECHAINOPERATOR_ROLE(), sidechainOperator);
            console.log("Granted SIDECHAINOPERATOR_ROLE on MorpherBridge to:", sidechainOperator);
        }

        vm.stopBroadcast();
    }
}
