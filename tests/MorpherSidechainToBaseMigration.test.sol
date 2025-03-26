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
    MorpherSidechainToBaseMigration.PositionMigrationData[] positionData;
    bytes32 testMarketId;
    
    function setUp() public override {
        super.setUp();
        
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
        
        // Setup position data
        positionData = new MorpherSidechainToBaseMigration.PositionMigrationData[](1);
        positionData[0] = MorpherSidechainToBaseMigration.PositionMigrationData({
            marketId: testMarketId,
            timeStamp: block.timestamp,
            longShares: 1 ether,
            shortShares: 0,
            meanEntryPrice: 50000 * 10**8,
            meanEntrySpread: 100 * 10**8,
            meanEntryLeverage: 1 * 10**8,
            liquidationPrice: 0,
            proof: testProof
        });
        
        // Grant roles
        morpherAccessControl.grantRole(ADMINISTRATOR_ROLE, address(this));
        morpherAccessControl.grantRole(MIGRATION_OPERATOR_ROLE, address(this));
        morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(morpherMigration));
        morpherAccessControl.grantRole(morpherTradeEngine.POSITIONADMIN_ROLE(), address(morpherMigration));
        
        // Create a mock signature (in a real test we would use proper signing)
        userSignature = abi.encodePacked(bytes32(0), bytes32(0), bytes1(0));
        
        // Fund the test user with some tokens for testing
        vm.startPrank(address(this));
        morpherToken.mint(testUser, 10 ether);
        vm.stopPrank();
    }
    
    function testInitialization() public {
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
            address(0),
            abi.encodeWithSelector(verifySelector),
            abi.encode(true)
        );
        
        bool result = morpherMigration.verifyBalance(testUser, testProof, testMerkleRoot, testBalance);
        assertTrue(result);
    }
    
    function testDelegateMigrateBalance() public {
        // We need to mock the signature verification and merkle proof verification
        bytes4 verifySelector = bytes4(keccak256("verify(bytes32[],bytes32,bytes32)"));
        vm.mockCall(
            address(0),
            abi.encodeWithSelector(verifySelector),
            abi.encode(true)
        );
        
        // Mock the ECDSA recovery to return our test user
        vm.mockCall(
            address(0),
            abi.encodeWithSelector(bytes4(keccak256("recover(bytes32,bytes)"))),
            abi.encode(testUser)
        );
        
        uint256 initialBalance = morpherToken.balanceOf(testUser);
        
        // Call the function
        morpherMigration.delegateMigrateBalance(
            testUser,
            userSignature,
            testMerkleRoot,
            testProof,
            testBalance
        );
        
        // Check that the balance was migrated with bonus
        uint256 expectedBalance = initialBalance + testBalance + (testBalance * 500 / 10000);
        assertEq(morpherToken.balanceOf(testUser), expectedBalance);
        
        // Check that the user is marked as migrated
        assertTrue(morpherMigration.migratedBalances(testUser));
        
        // Check statistics
        (uint256 positionsMigrated, uint256 balancesMigrated, uint256 usersMigrated, bool active, bool finalRootSet) = 
            morpherMigration.getMigrationStats();
        
        assertEq(balancesMigrated, 1);
        assertEq(usersMigrated, 1);
    }
    
    function testDelegateMigratePositionsBatch() public {
        // We need to mock the signature verification and merkle proof verification
        vm.mockCall(
            address(0),
            abi.encodeWithSelector(MerkleProofUpgradeable.verify.selector),
            abi.encode(true)
        );
        
        // Mock the ECDSA recovery to return our test user
        vm.mockCall(
            address(0),
            abi.encodeWithSelector(bytes4(keccak256("recover(bytes32,bytes)"))),
            abi.encode(testUser)
        );
        
        // Call the function
        morpherMigration.delegateMigratePositionsBatch(
            testUser,
            userSignature,
            testMerkleRoot,
            positionData
        );
        
        // Check that the position was migrated
        MorpherTradeEngine.position memory position = morpherTradeEngine.getPosition(testUser, testMarketId);
        assertEq(position.longShares, 1 ether);
        
        // Check statistics
        (uint256 positionsMigrated, uint256 balancesMigrated, uint256 usersMigrated, bool active, bool finalRootSet) = 
            morpherMigration.getMigrationStats();
        
        assertEq(positionsMigrated, 1);
    }
    
    function testMigrateBalanceSelfService() public {
        // Set the final balance merkle root
        morpherMigration.setFinalBalanceMerkleRoot(testMerkleRoot);
        
        // We need to mock the merkle proof verification
        bytes4 verifySelector = bytes4(keccak256("verify(bytes32[],bytes32,bytes32)"));
        vm.mockCall(
            address(0),
            abi.encodeWithSelector(verifySelector),
            abi.encode(true)
        );
        
        uint256 initialBalance = morpherToken.balanceOf(testUser);
        
        // Call the function as the test user
        vm.startPrank(testUser);
        morpherMigration.migrateBalanceSelfService(testProof, testBalance);
        vm.stopPrank();
        
        // Check that the balance was migrated (no bonus in self-service)
        uint256 expectedBalance = initialBalance + testBalance;
        assertEq(morpherToken.balanceOf(testUser), expectedBalance);
        
        // Check that the user is marked as migrated
        assertTrue(morpherMigration.migratedBalances(testUser));
    }
    
    function testCannotMigrateBalanceTwice() public {
        // First migration
        bytes4 verifySelector = bytes4(keccak256("verify(bytes32[],bytes32,bytes32)"));
        vm.mockCall(
            address(0),
            abi.encodeWithSelector(verifySelector),
            abi.encode(true)
        );
        
        vm.mockCall(
            address(0),
            abi.encodeWithSelector(bytes4(keccak256("recover(bytes32,bytes)"))),
            abi.encode(testUser)
        );
        
        morpherMigration.delegateMigrateBalance(
            testUser,
            userSignature,
            testMerkleRoot,
            testProof,
            testBalance
        );
        
        // Try to migrate again - should revert
        vm.expectRevert("MorpherMigration: Balance already migrated");
        morpherMigration.delegateMigrateBalance(
            testUser,
            userSignature,
            testMerkleRoot,
            testProof,
            testBalance
        );
    }
    
    function testCannotMigratePositionTwice() public {
        // First migration
        bytes4 verifySelector = bytes4(keccak256("verify(bytes32[],bytes32,bytes32)"));
        vm.mockCall(
            address(0),
            abi.encodeWithSelector(verifySelector),
            abi.encode(true)
        );
        
        vm.mockCall(
            address(0),
            abi.encodeWithSelector(bytes4(keccak256("recover(bytes32,bytes)"))),
            abi.encode(testUser)
        );
        
        morpherMigration.delegateMigratePositionsBatch(
            testUser,
            userSignature,
            testMerkleRoot,
            positionData
        );
        
        // Try to migrate again - should revert
        vm.expectRevert("MorpherMigration: Position already migrated");
        morpherMigration.delegateMigratePositionsBatch(
            testUser,
            userSignature,
            testMerkleRoot,
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
            testMerkleRoot,
            testProof,
            testBalance
        );
    }
}
