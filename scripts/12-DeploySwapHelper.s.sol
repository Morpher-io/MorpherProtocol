//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
// --- Inherit from DeployOrUpgradeV5 ---
import {DeployOrUpgradeV5} from "./deployOrUpgradeV5.sol";
import {MorpherSwapHelper} from "../contracts/MorpherSwapHelper.sol";
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol";
// MorpherState needed for initialization
import {MorpherState} from "../contracts/MorpherState.sol";

// --- Inherit from DeployOrUpgradeV5 ---
contract DeploySwapHelper is DeployOrUpgradeV5 {
	string constant CONTRACT_KEY = "MorpherSwapHelper";
	// Use fully qualified name or filename as required by the upgrades plugin
	string constant CONTRACT_NAME = "contracts/MorpherSwapHelper.sol:MorpherSwapHelper";

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

		// Check if deploying fresh
		address existingProxy = loadAddress(CONTRACT_KEY);
		bool isNewDeployment = existingProxy == address(0);

		vm.startBroadcast();

		// Prepare initializer data
		bytes memory initData = abi.encodeCall(
			MorpherSwapHelper.initialize,
			(stateAddress, UNISWAP_V3_ROUTER, WETH_ADDRESS)
		);

		// Deploy or upgrade using the V5 UUPS logic
		address swapHelperProxy = deployOrUpgradeV5(
			CONTRACT_KEY,
			CONTRACT_NAME,
			initData,
			bytes("") // No upgrade call data needed for this example
		);

		console.log("MorpherSwapHelper V5 Proxy at:", swapHelperProxy);

		// --- Post-Deployment/Upgrade Setup ---

		MorpherAccessControl accessControl = MorpherAccessControl(accessControlAddress);
		MorpherSwapHelper swapHelper = MorpherSwapHelper(swapHelperProxy); // Interact via proxy address
		address deployer = msg.sender;

		// Define roles needed by SwapHelper (using the contract type for constants)
		bytes32 adminRole = MorpherSwapHelper.ADMINISTRATOR_ROLE;
		bytes32 pauserRole = MorpherSwapHelper.PAUSER_ROLE;
		bytes32 proxyUpdaterRole = MorpherSwapHelper.PROXYUPDATER_ROLE; // Needed for future upgrades

		if (isNewDeployment) {
			console.log("Performing initial setup for new deployment...");

			// 1. Whitelist USDC
			// Temporarily grant ADMIN role on AccessControl *for the SwapHelper* to deployer
			console.log("Granting temporary ADMIN role to deployer for whitelisting...");
			accessControl.grantRole(adminRole, deployer);

			// Whitelist USDC on the SwapHelper (via proxy)
			swapHelper.whitelistToken(USDC_ADDRESS);
			console.log("Whitelisted USDC token:", USDC_ADDRESS);

			// Renounce temporary ADMIN role
			accessControl.renounceRole(adminRole, deployer);
			console.log("Renounced temporary ADMIN role from deployer.");

			// 2. Grant Permanent Roles on AccessControl for the SwapHelper contract
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
		} else {
			// --- Post-upgrade configuration (if needed) ---
			console.log("Performing post-upgrade checks/setup...");
			// Example: Ensure router address is up-to-date if it changed
			if (swapHelper.uniswapRouter() != UNISWAP_V3_ROUTER) {
				console.log("Updating Uniswap Router address in SwapHelper...");
				// Temporarily grant ADMIN role if deployer doesn't have it
				bool hadAdminRole = accessControl.hasRole(adminRole, deployer);
				if (!hadAdminRole) accessControl.grantRole(adminRole, deployer);

				swapHelper.setUniswapRouter(UNISWAP_V3_ROUTER);

				// Renounce if temporarily granted
				if (!hadAdminRole) accessControl.renounceRole(adminRole, deployer);
				console.log("Uniswap Router address updated.");
			}
			// Example: Check/update WETH address
			if (swapHelper.wethAddress() != WETH_ADDRESS) {
				console.log("Updating WETH address in SwapHelper...");
				bool hadAdminRole = accessControl.hasRole(adminRole, deployer);
				if (!hadAdminRole) accessControl.grantRole(adminRole, deployer);

				swapHelper.setWethAddress(WETH_ADDRESS);

				if (!hadAdminRole) accessControl.renounceRole(adminRole, deployer);
				console.log("WETH address updated.");
			}
			// Example: Ensure USDC is still whitelisted (or whitelist if newly added)
			if (!swapHelper.isTokenWhitelisted(USDC_ADDRESS)) {
				console.log("Whitelisting USDC token post-upgrade...");
				bool hadAdminRole = accessControl.hasRole(adminRole, deployer);
				if (!hadAdminRole) accessControl.grantRole(adminRole, deployer);

				swapHelper.whitelistToken(USDC_ADDRESS);

				if (!hadAdminRole) accessControl.renounceRole(adminRole, deployer);
				console.log("USDC token whitelisted.");
			}
		}

		// Note: Removed logic interacting with MorpherOracle

		vm.stopBroadcast();

		console.log("MorpherSwapHelper deployment/upgrade and setup complete.");
		console.log("MorpherSwapHelper Proxy address:", swapHelperProxy);
	}
}
