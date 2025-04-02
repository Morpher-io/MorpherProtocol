//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
// --- Import and Inherit from DeployOrUpgradeV5 ---
import {DeployOrUpgradeV5} from "./deployOrUpgradeV5.sol";

// Import the *adapted* v5 contracts
import {MorpherToken} from "../contracts/MorpherToken.sol";
import {MorpherState} from "../contracts/MorpherState.sol"; // Keep for setting address in state
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol"; // Keep for role granting

// --- Inherit from DeployOrUpgradeV5 ---
contract DeployMorpherToken is DeployOrUpgradeV5 { // Inherit from V5 helper

	string constant CONTRACT_KEY = "MorpherToken";
	// Use fully qualified name or filename as required by the upgrades plugin
	string constant CONTRACT_NAME = "contracts/MorpherToken.sol:MorpherToken";
	// Define the EIP712 domain name for the permit function
	string constant PERMIT_NAME = "MorpherToken"; // Or "MorpherToken" - should match what users expect

	function run() public {
		// Load dependencies
		address accessControlAddress = loadAddress("MorpherAccessControl");
		require(accessControlAddress != address(0), "V5 AccessControl must be deployed first");
		address stateAddress = loadAddress("MorpherState");
		require(stateAddress != address(0), "V5 MorpherState must be deployed first");

		// Check if deploying fresh
		address existingProxy = loadAddress(CONTRACT_KEY);
		bool isNewDeployment = existingProxy == address(0);

		vm.startBroadcast();

		// Deploy or upgrade using the V5 UUPS logic
		address tokenProxy = deployOrUpgradeV5(
			CONTRACT_KEY,
			CONTRACT_NAME,
			// Ensure initializer signature matches the adapted v5 contract, including permit name
			abi.encodeCall(MorpherToken.initialize, (accessControlAddress, stateAddress, PERMIT_NAME)),
			bytes("") // No upgrade call data needed for this example
		);

		console.log("MorpherToken V5 Proxy at:", tokenProxy);

		// Grant roles on AccessControl contract and configure token if this is a new deployment
		if (isNewDeployment) {
			console.log("Granting initial roles on AccessControl for MorpherToken...");
			MorpherAccessControl accessControl = MorpherAccessControl(accessControlAddress);
			MorpherToken tokenContract = MorpherToken(tokenProxy); // Use proxy address

			// Define roles using constants from the contract *type*
			bytes32 pauserRole = MorpherToken.PAUSER_ROLE;
			bytes32 adminRole = MorpherToken.ADMINISTRATOR_ROLE;
			bytes32 minterRole = MorpherToken.MINTER_ROLE;
			bytes32 burnerRole = MorpherToken.BURNER_ROLE; // Needed for staking/other burns
			bytes32 tokenUpdaterRole = MorpherToken.TOKENUPDATER_ROLE; // Needed for setting balances
			bytes32 airdropAdminRole = MorpherToken.AIRDROPADMIN_ROLE; // Needed for locking rewards

			// Grant initial roles to deployer (or designated admin/pauser addresses)
			address envAdmin = vm.envOr("TOKEN_ADMIN_ADDRESS", msg.sender);
			address envPauser = vm.envOr("TOKEN_PAUSER_ADDRESS", msg.sender);
			address envTokenUpdater = vm.envOr("TOKEN_UPDATER_ADDRESS", msg.sender);
			address envAirdropAdmin = vm.envOr("AIRDROP_ADMIN_ADDRESS", msg.sender);

			accessControl.grantRole(pauserRole, envPauser);
			accessControl.grantRole(adminRole, envAdmin);
			accessControl.grantRole(tokenUpdaterRole, envTokenUpdater);
			accessControl.grantRole(airdropAdminRole, envAirdropAdmin);
			// Grant MINTER_ROLE initially to deployer for initial mint, revoke later if needed
			accessControl.grantRole(minterRole, msg.sender);
			// Grant BURNER_ROLE to deployer initially if needed for setup, revoke later
			accessControl.grantRole(burnerRole, msg.sender);

			console.log("Granted PAUSER/ADMIN/UPDATER/AIRDROP roles.");

			// Get treasury address from environment or use deployer
			address treasuryAddress = vm.envOr("MORPHER_TREASURY", msg.sender);

			// Mint initial supply (adjust amounts as needed for the new chain)
			// tokenContract.setTotalTokensOnOtherChain(0); // Start fresh on new chain

			uint256 initialMint = 1_000_000_000 ether; // Example: Mint total supply to treasury
			tokenContract.mint(treasuryAddress, initialMint);
			console.log("Minted", initialMint / 1 ether, "MPH to treasury:", treasuryAddress);

			// Configure State with token address
			MorpherState(stateAddress).setMorpherToken(tokenProxy);
			console.log("Set MorpherToken address in MorpherState.");

			// Set initial daily transfer limit
			uint256 dailyLimit = 200_000 ether;
			tokenContract.setDailyMintedTransferLimit(dailyLimit);
			console.log("Set daily minted transfer limit to:", dailyLimit / 1 ether);

			// Revoke deployer's MINTER/BURNER roles if no longer needed
			if (msg.sender != envAdmin) { // Keep if admin is deployer
				accessControl.revokeRole(minterRole, msg.sender);
				accessControl.revokeRole(burnerRole, msg.sender);
				console.log("Revoked deployer MINTER/BURNER roles.");
			}

		} else {
			// --- Post-upgrade configuration (if needed) ---
			// Example: Ensure state address is set if it wasn't before
			MorpherToken tokenContract = MorpherToken(tokenProxy);
			if (address(tokenContract.morpherState()) != stateAddress) {
				console.log("Updating MorpherState address in MorpherToken...");
				tokenContract.setMorpherStateAddress(stateAddress);
			}
			// Example: Update daily limit if changed
			// uint256 newDailyLimit = 250_000 ether;
			// if (tokenContract.getDailyMintedTransferLimit() != newDailyLimit) {
			//     console.log("Updating daily minted transfer limit...");
			//     tokenContract.setDailyMintedTransferLimit(newDailyLimit);
			// }
		}

		vm.stopBroadcast();
	}
}
