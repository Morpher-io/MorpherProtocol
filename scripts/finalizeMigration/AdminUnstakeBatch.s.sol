// SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "./MorpherStakingUnstakeOnly.sol";

/**
 * @title AdminUnstakeBatch
 * @notice Batch unstakes users from the old staking contract using MorpherStakingUnstakeOnly
 *
 * Usage:
 *   forge script scripts/finalizeMigration/AdminUnstakeBatch.s.sol \
 *     --rpc-url $SIDECHAIN_RPC_URL \
 *     --private-key $ADMIN_PRIVATE_KEY \
 *     --broadcast \
 *     -vvvv
 *
 * Before running:
 *   1. Deploy MorpherStakingUnstakeOnly using DeployStakingUnstakeOnly.s.sol
 *   2. Grant access and enable transfers for the new contract in MorpherState
 *   3. Set STAKING_UNSTAKE_ONLY_ADDRESS env variable to the deployed address
 *   4. Create staked-users.csv with one address per line in this directory
 *      (or set STAKED_USERS_CSV env variable to a custom path)
 *
 * CSV format (one address per line):
 *   0x1234567890123456789012345678901234567890
 *   0xabcdefabcdefabcdefabcdefabcdefabcdefabcd
 *   ...
 */
contract AdminUnstakeBatch is Script {
    // Set this to the deployed MorpherStakingUnstakeOnly address
    address public stakingUnstakeOnlyAddress;

    // Users to unstake - loaded from CSV
    address[] public usersToUnstake;

    // Default CSV path relative to project root
    string constant DEFAULT_CSV_PATH = "scripts/finalizeMigration/staked-users.csv";

    function setUp() public {
        // Get the deployed contract address from environment
        stakingUnstakeOnlyAddress = vm.envAddress("STAKING_UNSTAKE_ONLY_ADDRESS");

        // Get CSV path from env or use default
        string memory csvPath = vm.envOr("STAKED_USERS_CSV", DEFAULT_CSV_PATH);

        console.log("=== Admin Unstake Batch Script ===");
        console.log("Staking Unstake Only Address:", stakingUnstakeOnlyAddress);
        console.log("Loading users from:", csvPath);

        // Read and parse CSV file
        _loadUsersFromCsv(csvPath);

        console.log("Users loaded:", usersToUnstake.length);
    }

    function _loadUsersFromCsv(string memory csvPath) internal {
        // Read the entire file
        string memory fileContent = vm.readFile(csvPath);

        // Split by newlines and parse each address
        string[] memory lines = vm.split(fileContent, "\n");

        for (uint256 i = 0; i < lines.length; i++) {
            string memory line = lines[i];

            // Skip empty lines
            if (bytes(line).length == 0) {
                continue;
            }

            // Trim any carriage return (Windows line endings)
            line = _trimCarriageReturn(line);

            // Skip if still empty after trim
            if (bytes(line).length == 0) {
                continue;
            }

            // Skip header if present (starts with non-0x)
            if (bytes(line).length < 2 || bytes(line)[0] != bytes1("0") || bytes(line)[1] != bytes1("x")) {
                // Could be a header like "address" - skip it
                continue;
            }

            // Parse the address
            address user = vm.parseAddress(line);
            if (user != address(0)) {
                usersToUnstake.push(user);
            }
        }
    }

    function _trimCarriageReturn(string memory s) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        if (b.length > 0 && b[b.length - 1] == bytes1("\r")) {
            bytes memory trimmed = new bytes(b.length - 1);
            for (uint256 i = 0; i < b.length - 1; i++) {
                trimmed[i] = b[i];
            }
            return string(trimmed);
        }
        return s;
    }

    function run() external {
        require(stakingUnstakeOnlyAddress != address(0), "STAKING_UNSTAKE_ONLY_ADDRESS not set");
        require(usersToUnstake.length > 0, "No users to unstake. Check CSV file.");

        uint256 adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        MorpherStakingUnstakeOnly stakingContract = MorpherStakingUnstakeOnly(stakingUnstakeOnlyAddress);

        console.log("");
        console.log("Current pool share value:", stakingContract.getCurrentPoolShareValue());
        console.log("");

        // Show first few stakes before unstaking (limit output for large lists)
        uint256 previewCount = usersToUnstake.length > 5 ? 5 : usersToUnstake.length;
        console.log("Stakes preview (first", previewCount, "users):");
        for (uint256 i = 0; i < previewCount; i++) {
            address user = usersToUnstake[i];
            uint256 shares = stakingContract.getStake(user);
            uint256 value = stakingContract.getStakeValue(user);
            console.log("  User:", user);
            console.log("    Shares:", shares);
            console.log("    Value:", value);
        }
        if (usersToUnstake.length > 5) {
            console.log("  ... and", usersToUnstake.length - 5, "more users");
        }
        console.log("");

        vm.startBroadcast(adminPrivateKey);

        // Batch size to avoid gas limits (8M gas limit on sidechain)
        uint256 batchSize = 50;
        uint256 totalUnstaked = 0;
        uint256 batchCount = 0;

        for (uint256 i = 0; i < usersToUnstake.length; i += batchSize) {
            uint256 end = i + batchSize;
            if (end > usersToUnstake.length) {
                end = usersToUnstake.length;
            }

            // Create batch array
            address[] memory batch = new address[](end - i);
            for (uint256 j = i; j < end; j++) {
                batch[j - i] = usersToUnstake[j];
            }

            batchCount++;
            console.log("Processing batch", batchCount, ":", batch.length, "users (", i + 1, "-", end, ")");

            uint256 batchAmount = stakingContract.adminUnstakeBatch(batch);
            totalUnstaked += batchAmount;

            console.log("  Batch unstaked amount:", batchAmount);
        }

        vm.stopBroadcast();

        console.log("");
        console.log("=== Summary ===");
        console.log("Total batches processed:", batchCount);
        console.log("Total users processed:", usersToUnstake.length);
        console.log("Total tokens unstaked:", totalUnstaked);
    }

    /**
     * @notice Unstake a single user (useful for testing or individual unstakes)
     */
    function unstakeSingleUser(address _user) external {
        require(stakingUnstakeOnlyAddress != address(0), "STAKING_UNSTAKE_ONLY_ADDRESS not set");

        uint256 adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        MorpherStakingUnstakeOnly stakingContract = MorpherStakingUnstakeOnly(stakingUnstakeOnlyAddress);

        console.log("Unstaking user:", _user);
        console.log("  Current stake:", stakingContract.getStake(_user));
        console.log("  Current value:", stakingContract.getStakeValue(_user));

        vm.startBroadcast(adminPrivateKey);

        uint256 amount = stakingContract.adminUnstake(_user);

        vm.stopBroadcast();

        console.log("  Unstaked amount:", amount);
    }

    /**
     * @notice Dry run - shows what would be unstaked without executing
     */
    function dryRun() external view {
        require(stakingUnstakeOnlyAddress != address(0), "STAKING_UNSTAKE_ONLY_ADDRESS not set");
        require(usersToUnstake.length > 0, "No users to unstake. Check CSV file.");

        MorpherStakingUnstakeOnly stakingContract = MorpherStakingUnstakeOnly(stakingUnstakeOnlyAddress);
        uint256 currentPoolShareValue = stakingContract.getCurrentPoolShareValue();

        console.log("");
        console.log("=== DRY RUN - No transactions will be sent ===");
        console.log("Current pool share value:", currentPoolShareValue);
        console.log("");

        uint256 totalShares = 0;
        uint256 totalValue = 0;
        uint256 usersWithStake = 0;

        for (uint256 i = 0; i < usersToUnstake.length; i++) {
            address user = usersToUnstake[i];
            uint256 shares = stakingContract.getStake(user);

            if (shares > 0) {
                uint256 value = shares * currentPoolShareValue;
                totalShares += shares;
                totalValue += value;
                usersWithStake++;

                console.log("User:", user);
                console.log("  Shares:", shares);
                console.log("  Value:", value);
            }
        }

        console.log("");
        console.log("=== Dry Run Summary ===");
        console.log("Users in CSV:", usersToUnstake.length);
        console.log("Users with active stake:", usersWithStake);
        console.log("Total shares to unstake:", totalShares);
        console.log("Total value to unstake:", totalValue);
        console.log("Batches needed (50 per batch):", (usersToUnstake.length + 49) / 50);
    }
}
