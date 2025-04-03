//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Upgrades} from "../lib/openzeppelin-foundry-upgrades/src/LegacyUpgrades.sol";
import {Options} from "../lib/openzeppelin-foundry-upgrades/src/Options.sol"; // Keep Options if used by V5 helper

// --- Import and Inherit from DeployOrUpgradeV5 ---
import {DeployOrUpgradeV5} from "./deployOrUpgradeV5.sol";

//morpher contracts
import {MorpherAirdrop} from "../contracts/MorpherAirdrop.sol"; // Use adapted v5 contract
import {MorpherToken} from "../contracts/MorpherToken.sol"; // Use adapted v5 contract
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol"; // Use adapted v5 contract

// --- Inherit from DeployOrUpgradeV5 ---
contract DeployMorpherAirdrop is DeployOrUpgradeV5 {

    string constant CONTRACT_KEY = "MorpherAirdrop";
    // Use fully qualified name or filename as required by the upgrades plugin
    string constant CONTRACT_NAME = "contracts/MorpherAirdrop.sol:MorpherAirdrop";

    function run() public {
        // Load dependencies
        address tokenAddress = loadAddress("MorpherToken");
        require(tokenAddress != address(0), "V5 MorpherToken must be deployed first");
        address accessControlAddress = loadAddress("MorpherAccessControl");
        require(accessControlAddress != address(0), "V5 AccessControl must be deployed first");
        address stateAddress = loadAddress("MorpherState"); // Load State address
        require(stateAddress != address(0), "V5 MorpherState must be deployed first");

        // Get configuration from environment
        // address airdropAdmin = vm.envOr("MORPHER_AIRDROP_ADMIN", msg.sender); // Role granted later
        // address coldStorageOwner = vm.envOr("MORPHER_OWNER", msg.sender); // REMOVED - No longer Ownable

        // Check if deploying fresh
        address existingProxy = loadAddress(CONTRACT_KEY);
        bool isNewDeployment = existingProxy == address(0);

        vm.startBroadcast();

        // Deploy or upgrade using the V5 UUPS logic
        address airdropProxy = deployOrUpgradeV5(
            CONTRACT_KEY,
            CONTRACT_NAME,
            // Ensure initializer signature matches the adapted v5 contract (state, token)
            abi.encodeCall(
                MorpherAirdrop.initialize,
                (stateAddress, tokenAddress) // Pass state, token ONLY
            ),
            bytes("") // No upgrade call data needed for this example
        );
        saveAddress(CONTRACT_KEY, airdropProxy);
        console.log("MorpherAirdrop V5 Proxy at:", airdropProxy);

        // Initial setup for new deployment on a new chain
        if (isNewDeployment) {
            console.log("Performing initial setup for MorpherAirdrop...");
            MorpherToken token = MorpherToken(tokenAddress);
            MorpherAccessControl ac = MorpherAccessControl(accessControlAddress);
            MorpherAirdrop airdropContract = MorpherAirdrop(airdropProxy); // Use proxy address

            // Grant AIRDROPADMIN_ROLE (defined in Airdrop contract) on AccessControl to the designated admin address
            address envAirdropAdmin = vm.envOr("MORPHER_AIRDROP_ADMIN", msg.sender);
            bytes32 airdropAdminRoleAirdrop = airdropContract.AIRDROPADMIN_ROLE();
            ac.grantRole(airdropAdminRoleAirdrop, envAirdropAdmin);
            console.log("Granted AIRDROPADMIN_ROLE (on AccessControl) to:", envAirdropAdmin);

            // Grant AIRDROPADMIN_ROLE (defined in Token contract) on AccessControl to the Airdrop contract proxy itself
            // This allows the Airdrop contract to call lockRewards on the Token contract
            bytes32 airdropAdminRoleToken = token.AIRDROPADMIN_ROLE();
            ac.grantRole(airdropAdminRoleToken, airdropProxy);
            console.log("Granted AIRDROPADMIN_ROLE (on Token) to Airdrop contract proxy.");

            // Transfer initial Airdrop funds from Treasury to Airdrop contract
            address treasuryAddress = vm.envOr("MORPHER_TREASURY", address(0));
            uint256 airdropSupply = vm.envOr("AIRDROP_SUPPLY", uint256(100_000_000 ether)); // Example: 100M tokens

            if (treasuryAddress != address(0) && airdropSupply > 0) {
                console.log("Transferring", airdropSupply / 1 ether, "MPH from Treasury to Airdrop contract...");
                // Ensure Treasury has TRANSFER_ROLE or deployer acts as Treasury
                // Using vm.prank if deployer needs to act as treasury
                // vm.startPrank(treasuryAddress);
                token.transfer(airdropProxy, airdropSupply);
                // vm.stopPrank();
                console.log("Airdrop funds transferred.");
            } else {
                 console.log("Skipping Airdrop fund transfer: Treasury address or supply not set/zero.");
            }

            // The old logic for treasury rollover seems unnecessary for a fresh deployment.
            // ac.grantRole(token.BURNER_ROLE(), msg.sender);
            // ac.grantRole(token.MINTER_ROLE(), msg.sender);
            // uint treasuryRollover = token.balanceOf(treasuryAddress);
            // token.burn(treasuryAddress, treasuryRollover);
            // token.mint(msg.sender, treasuryRollover);
            // token.transfer(airdropAdmin, 100_000 ether);
        }

        vm.stopBroadcast();
    }
}
