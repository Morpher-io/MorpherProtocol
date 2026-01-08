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
 *   4. Add user addresses to the usersToUnstake array in setUp()
 */
contract AdminUnstakeBatch is Script {
    // Set this to the deployed MorpherStakingUnstakeOnly address
    address public stakingUnstakeOnlyAddress;

    // Users to unstake - populate this array with staking users
    address[] public usersToUnstake;

    function setUp() public {
        // Get the deployed contract address from environment
        stakingUnstakeOnlyAddress = vm.envAddress("STAKING_UNSTAKE_ONLY_ADDRESS");

        // Add user addresses here
        // Example:
        // usersToUnstake.push(0x1234567890123456789012345678901234567890);
        // usersToUnstake.push(0xabcdefabcdefabcdefabcdefabcdefabcdefabcd);

        console.log("=== Admin Unstake Batch Script ===");
        console.log("Staking Unstake Only Address:", stakingUnstakeOnlyAddress);
        console.log("Users to unstake:", usersToUnstake.length);
    }

    function run() external {
        require(stakingUnstakeOnlyAddress != address(0), "STAKING_UNSTAKE_ONLY_ADDRESS not set");
        require(usersToUnstake.length > 0, "No users to unstake. Add addresses to setUp()");

        uint256 adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        MorpherStakingUnstakeOnly stakingContract = MorpherStakingUnstakeOnly(stakingUnstakeOnlyAddress);

        console.log("");
        console.log("Current pool share value:", stakingContract.getCurrentPoolShareValue());
        console.log("");

        // Show stakes before unstaking
        console.log("Stakes before unstaking:");
        for (uint256 i = 0; i < usersToUnstake.length; i++) {
            address user = usersToUnstake[i];
            uint256 shares = stakingContract.getStake(user);
            uint256 value = stakingContract.getStakeValue(user);
            console.log("  User:", user);
            console.log("    Shares:", shares);
            console.log("    Value:", value);
        }
        console.log("");

        vm.startBroadcast(adminPrivateKey);

        // Batch size to avoid gas limits (adjust as needed)
        uint256 batchSize = 50;
        uint256 totalUnstaked = 0;

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

            console.log("Processing batch", i / batchSize + 1, ":", batch.length, "users");

            uint256 batchAmount = stakingContract.adminUnstakeBatch(batch);
            totalUnstaked += batchAmount;

            console.log("  Batch unstaked amount:", batchAmount);
        }

        vm.stopBroadcast();

        console.log("");
        console.log("=== Summary ===");
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
}
