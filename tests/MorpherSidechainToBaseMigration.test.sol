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
        
        // Setup test data
        testUser = address(0x1234);
        testBalance = 1000 ether;
        testMerkleRoot = bytes32(uint256(1));
        testProof = new bytes32[](1);
        testProof[0] = bytes32(uint256(2));
        
        // Create a test market ID
        testMarketId = keccak256("CRYPTO_BTC");
        morpherState.activateMarket(testMarketId);
        
        // Create a test market ID
        testMarketId = keccak256("CRYPTO_BTC");
        morpherState.activateMarket(testMarketId);
        
        // Grant roles
        morpherAccessControl.grantRole(ADMINISTRATOR_ROLE, address(this));
        morpherAccessControl.grantRole(MIGRATION_OPERATOR_ROLE, address(this));
        morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(morpherMigration));
        morpherAccessControl.grantRole(morpherTradeEngine.POSITIONADMIN_ROLE(), address(morpherMigration));
        
        // Create a mock signature (in a real test we would use proper signing)
        userSignature = abi.encodePacked(bytes32(0), bytes32(0), bytes1(0));
        
        // Fund the test user with some tokens for testing
        morpherToken.mint(testUser, 10 ether);
        
        // Setup global mocks for ECDSA recovery
        bytes4 recoverSelector = bytes4(keccak256("recover(bytes32,bytes)"));
        vm.mockCall(
            address(ECDSAUpgradeable),
            abi.encodeWithSelector(recoverSelector),
            abi.encode(testUser)
        );
        
        // Mock the toEthSignedMessageHash function
        bytes4 toEthSignedMessageHashSelector = bytes4(keccak256("toEthSignedMessageHash(bytes32)"));
        vm.mockCall(
            address(ECDSAUpgradeable),
            abi.encodeWithSelector(toEthSignedMessageHashSelector),
            abi.encode(bytes32(0))
        );
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
    
    function testVerifyBalance() public {
        // Mock the MerkleProof verification
        bytes4 verifySelector = bytes4(keccak256("verify(bytes32[],bytes32,bytes32)"));
        vm.mockCall(
            address(MerkleProofUpgradeable),
            abi.encodeWithSelector(verifySelector),
            abi.encode(true)
        );
        
        // Test with no lock
        bool result = morpherMigration.verifyBalance(testUser, testProof, testMerkleRoot, testBalance, 0, 0);
        assertTrue(result);
        
        // Test with lock
        uint256 lockedAmount = 500 ether;
        uint256 lockDuration = 30 days;
        result = morpherMigration.verifyBalance(testUser, testProof, testMerkleRoot, testBalance, lockedAmount, lockDuration);
        assertTrue(result);
    }
    
    function testDelegateMigrateBalance() public {
        // We need to mock the merkle proof verification
        bytes4 verifySelector = bytes4(keccak256("verify(bytes32[],bytes32,bytes32)"));
        vm.mockCall(
            address(MerkleProofUpgradeable),
            abi.encodeWithSelector(verifySelector),
            abi.encode(true)
        );
        
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
        // We need to mock the merkle proof verification
        bytes4 verifySelector = bytes4(keccak256("verify(bytes32[],bytes32,bytes32)"));
        vm.mockCall(
            address(MerkleProofUpgradeable),
            abi.encodeWithSelector(verifySelector),
            abi.encode(true)
        );
        
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
        // Set the final balance merkle root
        morpherMigration.setFinalBalanceMerkleRoot(testMerkleRoot);
        
        // We need to mock the merkle proof verification
        bytes4 verifySelector = bytes4(keccak256("verify(bytes32[],bytes32,bytes32)"));
        vm.mockCall(
            address(MerkleProofUpgradeable),
            abi.encodeWithSelector(verifySelector),
            abi.encode(true)
        );
        
        uint256 initialBalance = morpherToken.balanceOf(testUser);
        uint256 lockedAmount = 500 ether;
        uint256 lockDuration = 30 days;
        
        // Call the function as the test user
        vm.startPrank(testUser);
        morpherMigration.migrateBalanceSelfService(testProof, testBalance, lockedAmount, lockDuration, 0);
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
        bytes4 verifySelector = bytes4(keccak256("verify(bytes32[],bytes32,bytes32)"));
        vm.mockCall(
            address(MerkleProofUpgradeable),
            abi.encodeWithSelector(verifySelector),
            abi.encode(true)
        );
        
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
        bytes4 verifySelector = bytes4(keccak256("verify(bytes32[],bytes32,bytes32)"));
        vm.mockCall(
            address(MerkleProofUpgradeable),
            abi.encodeWithSelector(verifySelector),
            abi.encode(true)
        );
        
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
        
        // Try to migrate - should revert
        vm.mockCall(
            address(0),
            abi.encodeWithSelector(bytes4(keccak256("recover(bytes32,bytes)"))),
            abi.encode(testUser)
        );
        
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
        // Set the final balance merkle root
        morpherMigration.setFinalBalanceMerkleRoot(testMerkleRoot);
        
        // We need to mock the merkle proof verification
        bytes4 verifySelector = bytes4(keccak256("verify(bytes32[],bytes32,bytes32)"));
        vm.mockCall(
            address(MerkleProofUpgradeable),
            abi.encodeWithSelector(verifySelector),
            abi.encode(true)
        );
        
        uint256 initialBalance = morpherToken.balanceOf(testUser);
        
        // Call the function as the test user with zero lock
        vm.startPrank(testUser);
        morpherMigration.migrateBalanceSelfService(testProof, testBalance, 0, 0, 0);
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
        // Set the final balance merkle root
        morpherMigration.setFinalBalanceMerkleRoot(testMerkleRoot);
        
        // We need to mock the merkle proof verification
        bytes4 verifySelector = bytes4(keccak256("verify(bytes32[],bytes32,bytes32)"));
        vm.mockCall(
            address(MerkleProofUpgradeable),
            abi.encodeWithSelector(verifySelector),
            abi.encode(true)
        );
        
        uint256 initialBalance = morpherToken.balanceOf(testUser);
        uint256 lockedAmount = testBalance / 2; // Lock half the balance
        uint256 lockDuration = 90 days;
        
        // Call the function as the test user
        vm.startPrank(testUser);
        morpherMigration.migrateBalanceSelfService(testProof, testBalance, lockedAmount, lockDuration, 0);
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
        // Mock the ECDSA recovery to return our test user
        vm.mockCall(
            address(0),
            abi.encodeWithSelector(bytes4(keccak256("recover(bytes32,bytes)"))),
            abi.encode(testUser)
        );
        
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
        // Set the final balance merkle root
        morpherMigration.setFinalBalanceMerkleRoot(testMerkleRoot);
        
        // We need to mock the merkle proof verification
        bytes4 verifySelector = bytes4(keccak256("verify(bytes32[],bytes32,bytes32)"));
        vm.mockCall(
            address(MerkleProofUpgradeable),
            abi.encodeWithSelector(verifySelector),
            abi.encode(true)
        );
        
        uint256 initialBalance = morpherToken.balanceOf(testUser);
        uint256 lockedAmount = testBalance / 4; // Lock 25% with time lock
        uint256 lockDuration = 90 days;
        uint256 lockedRewardAmount = testBalance / 4; // Lock 25% as rewards
        
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
        bytes4 verifySelector = bytes4(keccak256("verify(bytes32[],bytes32,bytes32)"));
        vm.mockCall(
            address(MerkleProofUpgradeable),
            abi.encodeWithSelector(verifySelector),
            abi.encode(true)
        );
        
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
