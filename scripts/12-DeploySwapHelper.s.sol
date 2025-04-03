//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {DeploymentUtils} from "./DeploymentUtils.sol"; // Use DeploymentUtils for address saving/loading
import {MorpherSwapHelper} from "../contracts/MorpherSwapHelper.sol";
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol";
// MorpherState needed for initialization
import {MorpherState} from "../contracts/MorpherState.sol";

// Inherit from DeploymentUtils instead of DeployOrUpgrade
contract DeploySwapHelper is DeploymentUtils {
	string constant CONTRACT_KEY = "MorpherSwapHelper";

	// Chain specific addresses
	address public UNISWAP_V3_ROUTER;
	address public WETH_ADDRESS; // Use variable for clarity, though constant on Base
	address public USDC_ADDRESS;

	// Set up addresses based on the chain we're deploying to
	function setupAddresses() internal {
		uint256 chainId = block.chainid;
		console.log("Configuring addresses for chain ID:", chainId);

		if (chainId == 8453) {
			// Base Mainnet
			UNISWAP_V3_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
			WETH_ADDRESS = 0x4200000000000000000000000000000000000006;
			USDC_ADDRESS = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // Base Mainnet USDC
		} else if (chainId == 84532) {
			// Base Sepolia
			UNISWAP_V3_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481; // Same router address
			WETH_ADDRESS = 0x4200000000000000000000000000000000000006;
			USDC_ADDRESS = 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // Base Sepolia USDC (as requested)
		} else {
			revert("Unsupported chain ID for MorpherSwapHelper deployment");
		}

		console.log("Uniswap V3 Router:", UNISWAP_V3_ROUTER);
		console.log("WETH Address:", WETH_ADDRESS);
		console.log("USDC Address:", USDC_ADDRESS);
	}

	function run() public {
		// Set up the correct addresses based on the chain
		setupAddresses();

		// Load dependencies
		address stateAddress = loadAddress("MorpherState");
		address accessControlAddress = loadAddress("MorpherAccessControl");
		require(stateAddress != address(0), "MorpherState must be deployed first");
		require(accessControlAddress != address(0), "MorpherAccessControl must be deployed first");

		console.log("Deploying MorpherSwapHelper...");
		console.log("Using MorpherState:", stateAddress);
		console.log("Using MorpherAccessControl:", accessControlAddress);

		vm.startBroadcast();

		// Deploy the MorpherSwapHelper implementation contract directly
		// Note: This deploys the implementation, not a proxy.
		// If proxy deployment is needed later, use deployOrUpgradeV5.
		MorpherSwapHelper swapHelper = new MorpherSwapHelper();
		console.log("MorpherSwapHelper implementation deployed at:", address(swapHelper));

		// Initialize the deployed contract
		swapHelper.initialize(stateAddress, UNISWAP_V3_ROUTER, WETH_ADDRESS);
		console.log("MorpherSwapHelper initialized.");

		// Save the address of the deployed (implementation) contract
		saveAddress(CONTRACT_KEY, address(swapHelper));

		// --- Post-Deployment Setup ---

		MorpherAccessControl accessControl = MorpherAccessControl(accessControlAddress);
		address deployer = msg.sender;

		// 1. Whitelist USDC
		// Temporarily grant ADMIN role on AccessControl *for the SwapHelper* to deployer
		console.log("Granting temporary ADMIN role to deployer for whitelisting...");
		accessControl.grantRole(swapHelper.ADMINISTRATOR_ROLE(), deployer);

		// Whitelist USDC on the SwapHelper
		swapHelper.whitelistToken(USDC_ADDRESS);
		console.log("Whitelisted USDC token:", USDC_ADDRESS);

		// Renounce temporary ADMIN role
		accessControl.renounceRole(swapHelper.ADMINISTRATOR_ROLE(), deployer);
		console.log("Renounced temporary ADMIN role from deployer.");

		// 2. Grant Permanent Roles on AccessControl for the SwapHelper contract
		// Define roles needed by SwapHelper
		bytes32 adminRole = swapHelper.ADMINISTRATOR_ROLE();
		bytes32 pauserRole = swapHelper.PAUSER_ROLE();
		bytes32 proxyUpdaterRole = swapHelper.PROXYUPDATER_ROLE(); // Needed for future upgrades

		// Grant roles to deployer initially
		accessControl.grantRole(adminRole, deployer);
		accessControl.grantRole(pauserRole, deployer);
		accessControl.grantRole(proxyUpdaterRole, deployer);
		console.log("Granted ADMIN/PAUSER/PROXYUPDATER roles for SwapHelper to deployer:", deployer);

		// Grant roles to environment addresses if specified
		address envAdmin = vm.envOr("MORPHER_ADMINISTRATOR", address(0));
		if (envAdmin != address(0) && envAdmin != deployer) {
			accessControl.grantRole(adminRole, envAdmin);
			console.log("Granted ADMIN role for SwapHelper to env address:", envAdmin);
		}
		// Assuming Governance can pause and update
		address envGovernance = vm.envOr("MORPHER_GOVERNANCE", address(0));
		if (envGovernance != address(0) && envGovernance != deployer) {
			accessControl.grantRole(pauserRole, envGovernance);
			accessControl.grantRole(proxyUpdaterRole, envGovernance);
			console.log("Granted PAUSER/PROXYUPDATER roles for SwapHelper to env address:", envGovernance);
		}

		// Note: Removed logic interacting with MorpherOracle

		vm.stopBroadcast();

		console.log("MorpherSwapHelper deployment and setup complete.");
		console.log("Deployed MorpherSwapHelper address:", address(swapHelper));
	}
}
