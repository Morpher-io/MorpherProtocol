// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "./BaseSetup.sol";
import "../contracts/MorpherSidechainToBaseMigration.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol";

contract MorpherSidechainToBaseMigrationTest is BaseSetup {
    bytes32 public constant ADMINISTRATOR_ROLE = keccak256("ADMINISTRATOR_ROLE");
    bytes32 public constant MIGRATION_OPERATOR_ROLE = keccak256("MIGRATION_OPERATOR_ROLE");
    
    // Test data
    bytes32 testMerkleRoot;
    address testUser;
    uint256 testBalance;
    bytes32[] testProof;
    bytes userSignature;
    
    // Position test data
    bytes32 testMarketId;
    
    function setUp() public override {
        super.setUp();
        
		morpherAccessControl.grantRole(morpherOracle.ADMINISTRATOR_ROLE(), address(this));
		morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(this));
        // Deploy the migration contract
        morpherMigration = new MorpherSidechainToBaseMigration();
        morpherMigration.initialize(address(morpherState), bytes32(0), 500); // 5% bonus
        
        // Create a private key for the test user
        uint256 testUserPrivateKey = 0xA11CE;
        testUser = vm.addr(testUserPrivateKey);
        
        // Setup test data
        testBalance = 1000 ether;
        
        // Create a test market ID
        testMarketId = keccak256("CRYPTO_BTC");
        morpherState.activateMarket(testMarketId);
        
        // Grant roles
        morpherAccessControl.grantRole(ADMINISTRATOR_ROLE, address(this));
        morpherAccessControl.grantRole(MIGRATION_OPERATOR_ROLE, address(this));
        morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(morpherMigration));
        morpherAccessControl.grantRole(morpherTradeEngine.POSITIONADMIN_ROLE(), address(morpherMigration));
        
        // Fund the test user with some tokens for testing
        morpherToken.mint(testUser, 10 ether);
        
        // Create the message that will be signed
        string memory message = "I authorize migration of all my positions from plasma chain to Base L2";
        bytes32 messageHash = keccak256(abi.encodePacked(message, testUser, block.chainid));
        bytes32 ethSignedMessageHash = ECDSAUpgradeable.toEthSignedMessageHash(messageHash);
        
        // Sign the message with the test user's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(testUserPrivateKey, ethSignedMessageHash);
        userSignature = abi.encodePacked(r, s, v);
        
        // Generate actual Merkle root and proof for self-service migration
        // Create leaf for the user's balance
        uint256 lockedAmount = 500 ether;
        uint256 lockDuration = 30 days;
        uint256 lockedRewardAmount = 200 ether;
        bytes32 balanceLeaf = keccak256(abi.encodePacked(testUser, testBalance, lockedAmount, lockDuration, lockedRewardAmount));
        
        // Create a simple Merkle tree with just one leaf
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = balanceLeaf;
        
        // The Merkle root is the leaf itself since we have only one leaf
        testMerkleRoot = balanceLeaf;
        
        // The proof is empty since we have only one leaf
        testProof = new bytes32[](0);
        
        // Set the final balance Merkle root
        morpherMigration.setFinalBalanceMerkleRoot(testMerkleRoot);
    }
    
    function testInitialization() public view {
        assertEq(address(morpherMigration.state()), address(morpherState));
        assertEq(morpherMigration.migrationBonus(), 500);
        assertEq(morpherMigration.migrationPaused(), false);
    }
    
    function testPauseMigration() public {
        morpherMigration.pauseMigration(true);
        assertTrue(morpherMigration.migrationPaused());
        
        morpherMigration.pauseMigration(false);
        assertFalse(morpherMigration.migrationPaused());
    }
    
    function testSetFinalBalanceMerkleRoot() public {
        bytes32 newRoot = bytes32(uint256(123456));
        morpherMigration.setFinalBalanceMerkleRoot(newRoot);
        assertEq(morpherMigration.finalBalanceMerkleRoot(), newRoot);
    }
    
    function testVerifyBalanceSelfService() public {
        // Test with the values used to generate the Merkle root
        uint256 lockedAmount = 500 ether;
        uint256 lockDuration = 30 days;
        uint256 lockedRewardAmount = 200 ether;
        bool result = morpherMigration.verifyBalanceSelfService(testUser, testProof, testBalance, lockedAmount, lockDuration, lockedRewardAmount);
        assertTrue(result);
        
        // Test with different values (should fail)
        result = morpherMigration.verifyBalanceSelfService(testUser, testProof, testBalance, 0, 0, 0);
        assertFalse(result);
        
        // Test with invalid merkle root
        morpherMigration.setFinalBalanceMerkleRoot(bytes32(0));
        vm.expectRevert("MorpherMigration: Final balance root not set");
        morpherMigration.verifyBalanceSelfService(testUser, testProof, testBalance, lockedAmount, lockDuration, lockedRewardAmount);
    }
    
    function testDelegateMigrateBalance() public {
        uint256 initialBalance = morpherToken.balanceOf(testUser);
        uint256 lockedAmount = 500 ether;
        uint256 lockDuration = 30 days;
        
        // Call the function
        morpherMigration.delegateMigrateBalance(
            testUser,
            userSignature,
            testBalance,
            lockedAmount,
            lockDuration,
            0 // No locked rewards
        );
        
        // Check that the balance was migrated with bonus
        uint256 expectedBalance = initialBalance + testBalance + (testBalance * 500 / 10000);
        // Locked tokens are still part of the total balance but not available for transfer
        assertEq(morpherToken.getTradeableBalanceOf(testUser), expectedBalance);
        assertEq(morpherToken.balanceOf(testUser), expectedBalance - lockedAmount);
        
        // Check that the user is marked as migrated
        assertTrue(morpherMigration.migratedBalances(testUser));
        
        // Verify time lock
        (uint256 actualLockedAmount, uint256 lockedUntil) = morpherToken.getTimeLock(testUser);
        assertEq(actualLockedAmount, lockedAmount);
        assertEq(lockedUntil, block.timestamp + lockDuration);
        
        // Check statistics
        (uint256 positionsMigrated, uint256 balancesMigrated, uint256 usersMigrated, bool active, bool finalRootSet) = 
            morpherMigration.getMigrationStats();
        
        assertEq(positionsMigrated, 0, "No positions should be migrated");
        assertEq(balancesMigrated, 1, "One balance should be migrated");
        assertEq(usersMigrated, 1, "One user should be migrated");
        assertTrue(active, "Migration should be active");
        assertTrue(finalRootSet, "Final root should not be set");
    }
    
    function testDelegateMigratePositionsBatch() public {
        // Create position data in memory
        MorpherSidechainToBaseMigration.PositionMigrationData[] memory positionData = 
            new MorpherSidechainToBaseMigration.PositionMigrationData[](1);
        
        positionData[0] = MorpherSidechainToBaseMigration.PositionMigrationData({
            marketId: testMarketId,
            timeStamp: block.timestamp,
            longShares: 1 ether,
            shortShares: 0,
            meanEntryPrice: 50000 * 10**8,
            meanEntrySpread: 100 * 10**8,
            meanEntryLeverage: 1 * 10**8,
            liquidationPrice: 0
        });
        
        // Call the function
        morpherMigration.delegateMigratePositionsBatch(
            testUser,
            userSignature,
            positionData
        );
        
        // Check that the position was migrated
        MorpherTradeEngine.position memory position = morpherTradeEngine.getPosition(testUser, testMarketId);
        assertEq(position.longShares, 1 ether);
        
        // Check statistics
        (uint256 positionsMigrated, uint256 balancesMigrated, uint256 usersMigrated, bool active, bool finalRootSet) = 
            morpherMigration.getMigrationStats();
        
        assertEq(positionsMigrated, 1, "One position should be migrated");
        assertEq(balancesMigrated, 0, "No balances should be migrated yet");
        assertEq(usersMigrated, 0, "User count should not increase for position-only migration");
        assertTrue(active, "Migration should be active");
        assertFalse(finalRootSet, "Final root should not be set");
    }
    
    function testMigrateBalanceSelfService() public {
        uint256 initialBalance = morpherToken.balanceOf(testUser);
        uint256 lockedAmount = 500 ether;
        uint256 lockDuration = 30 days;
        uint256 lockedRewardAmount = 200 ether;
        
        // Call the function as the test user
        vm.startPrank(testUser);
        morpherMigration.migrateBalanceSelfService(testProof, testBalance, lockedAmount, lockDuration, lockedRewardAmount);
        vm.stopPrank();
        
        // Check that the balance was migrated (no bonus in self-service)
        uint256 expectedBalance = initialBalance + testBalance;
        // Locked tokens are still part of the total balance but not available for transfer
        assertEq(morpherToken.getTradeableBalanceOf(testUser), expectedBalance);
        assertEq(morpherToken.balanceOf(testUser), expectedBalance - lockedAmount);
        
        // Check that the user is marked as migrated
        assertTrue(morpherMigration.migratedBalances(testUser));
        
        // Verify time lock
        (uint256 actualLockedAmount, uint256 lockedUntil) = morpherToken.getTimeLock(testUser);
        assertEq(actualLockedAmount, lockedAmount);
        assertEq(lockedUntil, block.timestamp + lockDuration);
        
        // Verify migration statistics
        (uint256 positionsMigrated, uint256 balancesMigrated, uint256 usersMigrated, bool active, bool finalRootSet) = 
            morpherMigration.getMigrationStats();
        assertEq(positionsMigrated, 0, "No positions should be migrated");
        assertEq(balancesMigrated, 1, "One balance should be migrated");
        assertEq(usersMigrated, 1, "One user should be migrated");
        assertTrue(active, "Migration should be active");
        assertTrue(finalRootSet, "Final root should be set");
    }
    
    function testCannotMigrateBalanceTwice() public {
        // First migration
        morpherMigration.delegateMigrateBalance(
            testUser,
            userSignature,
            testBalance,
            0,
            0,
            0
        );
        
        // Try to migrate again - should revert
        vm.expectRevert("MorpherMigration: Balance already migrated");
        morpherMigration.delegateMigrateBalance(
            testUser,
            userSignature,
            testBalance,
            0,
            0,
            0
        );
    }
    
    function testCannotMigratePositionTwice() public {
        // Create position data in memory
        MorpherSidechainToBaseMigration.PositionMigrationData[] memory positionData = 
            new MorpherSidechainToBaseMigration.PositionMigrationData[](1);
        
        positionData[0] = MorpherSidechainToBaseMigration.PositionMigrationData({
            marketId: testMarketId,
            timeStamp: block.timestamp,
            longShares: 1 ether,
            shortShares: 0,
            meanEntryPrice: 50000 * 10**8,
            meanEntrySpread: 100 * 10**8,
            meanEntryLeverage: 1 * 10**8,
            liquidationPrice: 0
        });
        
        // First migration
        morpherMigration.delegateMigratePositionsBatch(
            testUser,
            userSignature,
            positionData
        );
        
        // Try to migrate again - should revert
        vm.expectRevert("MorpherMigration: Position already migrated");
        morpherMigration.delegateMigratePositionsBatch(
            testUser,
            userSignature,
            positionData
        );
    }
    
    function testCannotMigrateWhenPaused() public {
        // Pause migration
        morpherMigration.pauseMigration(true);
        
        vm.expectRevert("MorpherMigration: Migration is paused");
        morpherMigration.delegateMigrateBalance(
            testUser,
            userSignature,
            testBalance,
            0,
            0,
            0
        );
    }
    
    function testMigrateBalanceWithZeroLock() public {
        // Create a new Merkle root for zero lock
        bytes32 zeroLockLeaf = keccak256(abi.encodePacked(testUser, testBalance, uint256(0), uint256(0), uint256(0)));
        morpherMigration.setFinalBalanceMerkleRoot(zeroLockLeaf);
        
        uint256 initialBalance = morpherToken.balanceOf(testUser);
        
        // Call the function as the test user with zero lock
        vm.startPrank(testUser);
        morpherMigration.migrateBalanceSelfService(new bytes32[](0), testBalance, 0, 0, 0);
        vm.stopPrank();
        
        // Check that the balance was migrated with no lock
        uint256 expectedBalance = initialBalance + testBalance;
        assertEq(morpherToken.balanceOf(testUser), expectedBalance);
        
        // Verify no time lock was created
        (uint256 lockedAmount, uint256 lockedUntil) = morpherToken.getTimeLock(testUser);
        assertEq(lockedAmount, 0);
        assertEq(lockedUntil, 0);
        
        // Check that the user is marked as migrated
        assertTrue(morpherMigration.migratedBalances(testUser));
    }
    
    function testMigrateBalanceWithPartialLock() public {
        // Create a new Merkle root for partial lock
        uint256 lockedAmount = testBalance / 2; // Lock half the balance
        uint256 lockDuration = 90 days;
        bytes32 partialLockLeaf = keccak256(abi.encodePacked(testUser, testBalance, lockedAmount, lockDuration, uint256(0)));
        morpherMigration.setFinalBalanceMerkleRoot(partialLockLeaf);
        
        uint256 initialBalance = morpherToken.balanceOf(testUser);
        
        // Call the function as the test user
        vm.startPrank(testUser);
        morpherMigration.migrateBalanceSelfService(new bytes32[](0), testBalance, lockedAmount, lockDuration, 0);
        vm.stopPrank();
        
        // Check that the balance was migrated with partial lock
        uint256 expectedBalance = initialBalance + testBalance;
        assertEq(morpherToken.getTradeableBalanceOf(testUser), expectedBalance);
        assertEq(morpherToken.balanceOf(testUser), expectedBalance - lockedAmount);
        
        // Verify time lock
        (uint256 actualLockedAmount, uint256 lockedUntil) = morpherToken.getTimeLock(testUser);
        assertEq(actualLockedAmount, lockedAmount);
        assertEq(lockedUntil, block.timestamp + lockDuration);
    }
    function testDelegateMigrateBalanceWithLock() public {
        
        uint256 initialBalance = morpherToken.balanceOf(testUser);
        uint256 lockedAmount = testBalance;  // Lock the entire balance
        uint256 lockDuration = 365 days;     // Lock for a year
        
        // Call the function
        morpherMigration.delegateMigrateBalance(
            testUser,
            userSignature,
            testBalance,
            lockedAmount,
            lockDuration,
            0
        );
        
        // Check that the balance was migrated with bonus
        uint256 expectedBalance = initialBalance + testBalance + (testBalance * 500 / 10000);
        // Locked tokens are still part of the total balance but not available for transfer
        assertEq(morpherToken.getTradeableBalanceOf(testUser), expectedBalance);
        assertEq(morpherToken.balanceOf(testUser), expectedBalance - lockedAmount);
        
        // Verify time lock
        (uint256 actualLockedAmount, uint256 lockedUntil) = morpherToken.getTimeLock(testUser);
        assertEq(actualLockedAmount, lockedAmount);
        assertEq(lockedUntil, block.timestamp + lockDuration);
        
        // Check that the user is marked as migrated
        assertTrue(morpherMigration.migratedBalances(testUser));
        
        // Check that the migration was authorized
        assertTrue(morpherMigration.userAuthorizedMigration(testUser));
    }
    
    function testSelfServiceMigrationWithLockedRewards() public {
        // We're already set up with the correct Merkle root from setUp()
        uint256 initialBalance = morpherToken.balanceOf(testUser);
        uint256 lockedAmount = 500 ether;
        uint256 lockDuration = 30 days;
        uint256 lockedRewardAmount = 200 ether;
        
        // Call the function as the test user
        vm.startPrank(testUser);
        morpherMigration.migrateBalanceSelfService(testProof, testBalance, lockedAmount, lockDuration, lockedRewardAmount);
        vm.stopPrank();
        
        // Check that the balance was migrated with partial lock
        uint256 expectedBalance = initialBalance + testBalance;
        assertEq(morpherToken.getTradeableBalanceOf(testUser), expectedBalance);
        assertEq(morpherToken.balanceOf(testUser), expectedBalance - lockedAmount - lockedRewardAmount);
        
        // Verify time lock
        (uint256 actualLockedAmount, uint256 lockedUntil) = morpherToken.getTimeLock(testUser);
        assertEq(actualLockedAmount, lockedAmount);
        assertEq(lockedUntil, block.timestamp + lockDuration);
        
        // Verify locked rewards
        uint256 actualLockedRewards = morpherToken.getLockedRewards(testUser);
        assertEq(actualLockedRewards, lockedRewardAmount);
        
        // Check that the user is marked as migrated
        assertTrue(morpherMigration.migratedBalances(testUser));
    }

    function testFullMigrationFlow() public {
        // 1. First migrate positions
        // Create position data
        MorpherSidechainToBaseMigration.PositionMigrationData[] memory positionData = 
            new MorpherSidechainToBaseMigration.PositionMigrationData[](1);
        
        positionData[0] = MorpherSidechainToBaseMigration.PositionMigrationData({
            marketId: testMarketId,
            timeStamp: block.timestamp,
            longShares: 2 ether,
            shortShares: 0,
            meanEntryPrice: 50000 * 10**8,
            meanEntrySpread: 100 * 10**8,
            meanEntryLeverage: 1 * 10**8,
            liquidationPrice: 0
        });
        
        // Migrate positions
        morpherMigration.delegateMigratePositionsBatch(
            testUser,
            userSignature,
            positionData
        );
        
        // 2. Then set final balance root and migrate balance
        morpherMigration.setFinalBalanceMerkleRoot(testMerkleRoot);
        
        // Migrate balance with partial lock
        uint256 initialBalance = morpherToken.balanceOf(testUser);
        uint256 lockedAmount = testBalance / 4; // Lock 25% of the balance
        uint256 lockDuration = 180 days;
        
        morpherMigration.delegateMigrateBalance(
            testUser,
            userSignature,
            testBalance,
            lockedAmount,
            lockDuration,
            0
        );
        
        // 3. Verify everything was migrated correctly
        
        // Check position
        MorpherTradeEngine.position memory position = morpherTradeEngine.getPosition(testUser, testMarketId);
        assertEq(position.longShares, 2 ether, "Position longShares should be migrated correctly");
        assertEq(position.shortShares, 0, "Position shortShares should be migrated correctly");
        
        // Check balance with bonus
        uint256 expectedBalance = initialBalance + testBalance + (testBalance * 500 / 10000);
        assertEq(morpherToken.getTradeableBalanceOf(testUser), expectedBalance, "Total balance should include bonus");
        assertEq(morpherToken.balanceOf(testUser), expectedBalance - lockedAmount, "Available balance should exclude locked tokens");
        
        // Check time lock
        (uint256 actualLockedAmount, uint256 lockedUntil) = morpherToken.getTimeLock(testUser);
        assertEq(actualLockedAmount, lockedAmount, "Locked amount should match");
        assertEq(lockedUntil, block.timestamp + lockDuration, "Lock duration should match");
        
        // Check migration status
        assertTrue(morpherMigration.migratedBalances(testUser), "Balance should be marked as migrated");
        assertTrue(morpherMigration.userAuthorizedMigration(testUser), "User should be marked as authorized");
        
        // Check final statistics
        (uint256 positionsMigrated, uint256 balancesMigrated, uint256 usersMigrated, bool active, bool finalRootSet) = 
            morpherMigration.getMigrationStats();
        assertEq(positionsMigrated, 1, "One position should be migrated");
        assertEq(balancesMigrated, 1, "One balance should be migrated");
        assertEq(usersMigrated, 1, "One user should be migrated");
        assertTrue(active, "Migration should be active");
        assertTrue(finalRootSet, "Final root should be set");
    }
}
