// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20; // Update pragma if needed

import {ERC20Upgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/token/ERC20/ERC20Upgradeable.sol";
import {MessageHashUtils} from "../lib/openzeppelin-contracts-5/contracts/utils/cryptography/MessageHashUtils.sol";
// Import EIP712 for struct hashing in test (optional, can reconstruct hash manually)
// import {EIP712} from "../lib/openzeppelin-contracts-5/contracts/utils/cryptography/EIP712.sol";

import "./BaseSetup.sol";

contract MorpherTokenTest is
	BaseSetup,
	ERC20Upgradeable // Remove ERC20Upgradeable inheritance if not needed directly
{
	address _admin = address(0x1234);
	address _tokenUpdater = address(0x5678);
	address _pauser = address(0x90);

	// --- Remove manual EIP712 constants ---
	// bytes32 private constant _TYPE_HASH = ...;
	// bytes32 private constant _PERMIT_TYPEHASH = ...; // Rebuild locally if needed for signing

	event SetTotalTokensOnOtherChain(uint256 _oldValue, uint256 _newValue);
	event SetTotalTokensInPositions(uint256 _oldValue, uint256 _newValue);
	event SetRestrictTransfers(bool _oldValue, bool _newValue);
	event Paused(address pauser);
	event Unpaused(address pauser);

	function setUp() public override {
		super.setUp();
		morpherAccessControl.grantRole(morpherToken.ADMINISTRATOR_ROLE(), _admin);
		morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), _admin);
		morpherAccessControl.grantRole(morpherToken.BURNER_ROLE(), _admin);
		morpherAccessControl.grantRole(morpherToken.POLYGONMINTER_ROLE(), _admin);
		morpherAccessControl.grantRole(morpherToken.PAUSER_ROLE(), _pauser);
		morpherAccessControl.grantRole(morpherToken.TOKENUPDATER_ROLE(), _tokenUpdater);
	}

	function testAdminFunctions() public {
		vm.startPrank(_admin);

		// --- Remove setHashedName/Version calls ---
		// string memory name = "MorpherToken2";
		// bytes32 expectedHash = keccak256(bytes(name));
		// morpherToken.setHashedName(name);
		// string memory version = "2";
		// expectedHash = keccak256(bytes(version));
		// morpherToken.setHashedVersion(version);

		vm.expectEmit(true, true, true, true);
		emit SetRestrictTransfers(false, false); // Assuming initial state is false
		morpherToken.setRestrictTransfers(false);
		assertEq(morpherToken.getRestrictTransfers(), false);

		vm.stopPrank();
		vm.startPrank(_tokenUpdater);

		uint256 totalTokensInPositions = 500 * 10 ** 18;
		vm.expectEmit(true, true, true, true);
		emit SetTotalTokensInPositions(0, totalTokensInPositions);
		morpherToken.setTotalInPositions(totalTokensInPositions);
		assertEq(morpherToken.getTotalTokensInPositions(), totalTokensInPositions);

		vm.stopPrank();

		uint256 totalSupply = morpherToken.totalSupply();
		assertEq(totalSupply, 500 * 10 ** 18);

		vm.startPrank(_pauser);
		vm.expectEmit(true, true, true, true);
		emit Paused(_pauser);
		morpherToken.pause();
		assertEq(morpherToken.paused(), true);
		vm.expectEmit(true, true, true, true);
		emit Unpaused(_pauser);
		morpherToken.unpause();
		assertEq(morpherToken.paused(), false);
		vm.stopPrank();
	}

	function testPermitWithEIP712() public {
		Account memory owner = makeAccount("owner");
		address spender = address(0xdef);
		uint value = 1 ether;
		uint deadline = block.timestamp + 1 hours; // Use future timestamp

		vm.startPrank(_admin);
		morpherToken.mint(owner.addr, value);
		vm.stopPrank();

		uint nonce = morpherToken.nonces(owner.addr);

		// Generate signature using helper
		(uint8 v, bytes32 r, bytes32 s) = _generatePermitSignature(owner, spender, value, nonce, deadline);

		// Call permit
		vm.expectEmit(true, true, true, true);
		emit Approval(owner.addr, spender, value);
		morpherToken.permit(owner.addr, spender, value, deadline, v, r, s);
	}

	function testDepositWithdraw() public {
		address user = address(0xabcdef);
		vm.startPrank(_admin);

		vm.expectEmit(true, true, true, true);
		emit Transfer(address(0), user, 1 ether);
		morpherToken.deposit(user, bytes(abi.encode(1 ether)));

		uint256 totalSupply = morpherToken.totalSupply();
		assertEq(totalSupply, 1 ether);

		morpherToken.mint(_admin, 2 ether);

		totalSupply = morpherToken.totalSupply();
		assertEq(totalSupply, 3 ether);

		vm.expectEmit(true, true, true, true);
		emit Transfer(_admin, address(0), 1 ether);
		morpherToken.withdraw(1 ether);

		totalSupply = morpherToken.totalSupply();
		assertEq(totalSupply, 2 ether);
	}

	function testTimeLockTokens() public {
		address user = address(0xabcdef);

		// Mint tokens to user
		vm.startPrank(_admin);
		morpherToken.mint(user, 10 ether);

		// Lock 5 ether for 180 days
		uint256 lockDuration = 180 days;
		morpherToken.lockTokensForTime(user, 5 ether, lockDuration);
		vm.stopPrank();

		// Check balances
		assertEq(morpherToken.getTradeableBalanceOf(user), 10 ether);
		assertEq(morpherToken.balanceOf(user), 5 ether); // Only 5 ether available

		// Get time lock info
		(uint256 lockedAmount, uint256 lockedUntil) = morpherToken.getTimeLock(user);
		assertEq(lockedAmount, 5 ether);
		assertEq(lockedUntil, block.timestamp + lockDuration);

		// Try to transfer more than available balance
		vm.startPrank(user);
		vm.expectRevert("MorpherToken: transfer amount exceeds available balance (locked)");
		morpherToken.transfer(address(0x123), 6 ether);

		// Transfer within available balance
		morpherToken.transfer(address(0x123), 4 ether);
		vm.stopPrank();

		// Check balances after transfer
		assertEq(morpherToken.getTradeableBalanceOf(user), 6 ether);
		assertEq(morpherToken.balanceOf(user), 1 ether);

		// Fast forward past lock period
		vm.warp(block.timestamp + lockDuration + 1);

		// Check that tokens are now available
		(lockedAmount, lockedUntil) = morpherToken.getTimeLock(user);
		assertEq(lockedAmount, 0); // Lock has expired
		assertEq(lockedUntil, 0);

		// Balances should reflect unlocked tokens
		assertEq(morpherToken.balanceOf(user), 6 ether);

		// Manually trigger unlock
		vm.prank(user);
		morpherToken.unlockExpiredTokens(user);

		// Check total time locked
		assertEq(morpherToken.getTotalTimeLocked(), 0);
	}

	function testTimeLockAndRewardsLock() public {
		address user = address(0xabcdef);

		// Grant AIRDROPADMIN_ROLE to admin for reward locking
		morpherAccessControl.grantRole(morpherToken.AIRDROPADMIN_ROLE(), _admin);
		vm.startPrank(_admin);

		// Mint tokens to user
		morpherToken.mint(user, 10 ether);

		// Lock 3 ether as rewards
		morpherToken.lockRewards(user, 3 ether);

		// Lock 4 ether with time lock
		uint256 lockDuration = 30 days;
		morpherToken.lockTokensForTime(user, 4 ether, lockDuration);
		vm.stopPrank();

		// Check balances
		assertEq(morpherToken.getTradeableBalanceOf(user), 10 ether);
		assertEq(morpherToken.balanceOf(user), 3 ether); // 10 - 3 (rewards) - 4 (time lock)

		// Try to transfer more than available balance
		vm.startPrank(user);
		vm.expectRevert("MorpherToken: transfer amount exceeds available balance (locked)");
		morpherToken.transfer(address(0x123), 4 ether);

		// Transfer within available balance
		morpherToken.transfer(address(0x123), 2 ether);
		vm.stopPrank();

		// Check balances after transfer
		assertEq(morpherToken.getTradeableBalanceOf(user), 8 ether);
		assertEq(morpherToken.balanceOf(user), 1 ether);

		// Fast forward past time lock period
		vm.warp(block.timestamp + lockDuration + 1);

		// Check balances - time lock should be expired but rewards lock remains
		assertEq(morpherToken.balanceOf(user), 5 ether); // 8 - 3 (rewards)

		// Manually trigger unlock
		vm.prank(user);
		morpherToken.unlockExpiredTokens(user);

		// Unlock rewards
		vm.startPrank(_admin);
		morpherToken.unlockRewards(user, 3 ether);
		vm.stopPrank();

		// Check final balance - all locks removed
		assertEq(morpherToken.balanceOf(user), 8 ether);
	}

	function testDailyMintedTransferLimit() public {
		address user = address(0xabcdef);
		address recipient = address(0x123456);

		// Set daily transfer limit
		vm.startPrank(_admin);
		morpherToken.setDailyMintedTransferLimit(5 ether);
		vm.stopPrank();

		// Mint tokens as MintingLimiter (these should not be tracked as transferred in)
		vm.startPrank(morpherState.morpherMintingLimiterAddress());
		morpherToken.mint(user, 10 ether);
		vm.stopPrank();

		// Check balance and transferred in tokens
		assertEq(morpherToken.balanceOf(user), 10 ether);
		assertEq(morpherToken.getTransferredInTokens(user), 0 ether);

		// Try to transfer more than the daily limit
		vm.startPrank(user);
		vm.expectRevert("MorpherToken: daily minted token transfer limit exceeded");
		morpherToken.transfer(recipient, 6 ether);
		vm.stopPrank();

		// Transfer within the limit
		vm.startPrank(user);
		morpherToken.transfer(recipient, 4 ether);
		vm.stopPrank();

		// Check balances after transfer
		assertEq(morpherToken.balanceOf(user), 6 ether);
		assertEq(morpherToken.balanceOf(recipient), 4 ether);
		assertEq(morpherToken.getDailyMintedTransfers(user), 4 ether);
		assertEq(morpherToken.getTransferredInTokens(recipient), 4 ether);

		// Try another transfer that would exceed the limit
		vm.startPrank(user);
		vm.expectRevert("MorpherToken: daily minted token transfer limit exceeded");
		morpherToken.transfer(recipient, 2 ether);
		vm.stopPrank();

		// Transfer exactly at the limit
		vm.startPrank(user);
		morpherToken.transfer(recipient, 1 ether);
		vm.stopPrank();

		// Check final balances
		assertEq(morpherToken.balanceOf(user), 5 ether);
		assertEq(morpherToken.balanceOf(recipient), 5 ether);
		assertEq(morpherToken.getDailyMintedTransfers(user), 5 ether);
		assertEq(morpherToken.getTransferredInTokens(recipient), 5 ether);

		// Test burn/mint cycle with TradeEngine
		vm.startPrank(morpherState.morpherTradeEngineAddress());
		morpherToken.burn(user, 3 ether);
		vm.stopPrank();

		vm.startPrank(morpherState.morpherMintingLimiterAddress());
		morpherToken.mint(user, 3 ether);
		vm.stopPrank();

		// Admin should be able to bypass the limit
		vm.startPrank(_admin);
		morpherToken.mint(user, 10 ether);
		vm.stopPrank();

		// Admin transfer should bypass limit
		vm.prank(user);
		morpherToken.approve(_admin, 10 ether);
		vm.startPrank(_admin);
		morpherToken.transferFrom(user, recipient, 10 ether);
		vm.stopPrank();

		// Check final balances after admin transfer
		assertEq(morpherToken.balanceOf(user), 5 ether);
		assertEq(morpherToken.balanceOf(recipient), 15 ether);
	}
	function testTransferredInTokensWithBurnMintCycle() public {
		address user1 = address(0xabcdef);
		address user2 = address(0x123456);

		// Set daily transfer limit
		vm.startPrank(_admin);
		morpherToken.setDailyMintedTransferLimit(5 ether);
		morpherToken.mint(user1, 10 ether);
		vm.stopPrank();

		// User1 transfers to User2
		vm.startPrank(user1);
		morpherToken.transfer(user2, 10 ether);
		vm.stopPrank();

		// Check that User2 has transferred in tokens
		assertEq(morpherToken.getTransferredInTokens(user2), 10 ether);

		// TradeEngine burns tokens (opening a position)
		vm.startPrank(morpherState.morpherTradeEngineAddress());
		morpherToken.burn(user2, 10 ether);
		vm.stopPrank();

		// Check balances
		assertEq(morpherToken.balanceOf(user2), 0 ether);
		// Transferred in tokens remain the same even after burning
		assertEq(morpherToken.getTransferredInTokens(user2), 10 ether);

		// TradeEngine mints tokens back (closing a position with 50% profit)
		vm.startPrank(morpherState.morpherTradeEngineAddress());
		morpherToken.mint(user2, 15 ether); // 10 original + 5 profit
		vm.stopPrank();

		// Check balances - user should have 15 ether total
		assertEq(morpherToken.balanceOf(user2), 15 ether);
		assertEq(morpherToken.getTransferredInTokens(user2), 10 ether);

		// User2 should be able to transfer all tokens (10 original + 5 profit)
		// The first 10 ether should be from transferred-in tokens (not subject to limit)
		// The 5 ether profit is within the daily limit
		vm.startPrank(user2);
		morpherToken.transfer(user1, 15 ether);
		vm.stopPrank();

		// Check final balances
		assertEq(morpherToken.balanceOf(user2), 0 ether);
		assertEq(morpherToken.balanceOf(user1), 15 ether);
		assertEq(morpherToken.getTransferredInTokens(user2), 0);
		assertEq(morpherToken.getDailyMintedTransfers(user2), 5 ether); // Only the profit counts toward the daily limit
	}
	function testMintFromOtherSourcesTrackedAsTransferredIn() public {
		address user = address(0xabcdef);

		// Mint tokens as admin (should be tracked as transferred in)
		vm.startPrank(_admin);
		morpherToken.mint(user, 10 ether);
		vm.stopPrank();

		// Check balance and transferred in tokens
		assertEq(morpherToken.balanceOf(user), 10 ether);
		assertEq(morpherToken.getTransferredInTokens(user), 10 ether);

		// Mint tokens as MintingLimiter (should not be tracked as transferred in)
		vm.startPrank(morpherState.morpherMintingLimiterAddress());
		morpherToken.mint(user, 5 ether);
		vm.stopPrank();

		// Check updated balance and transferred in tokens
		assertEq(morpherToken.balanceOf(user), 15 ether);
		assertEq(morpherToken.getTransferredInTokens(user), 10 ether); // Still 10 ether

		// Mint tokens as TradeEngine (should not be tracked as transferred in)
		vm.startPrank(morpherState.morpherTradeEngineAddress());
		morpherToken.mint(user, 5 ether);
		vm.stopPrank();

		// Check final balance and transferred in tokens
		assertEq(morpherToken.balanceOf(user), 20 ether);
		assertEq(morpherToken.getTransferredInTokens(user), 10 ether); // Still 10 ether
	}

	function testPositionWithProfitAndTransferLimit() public {
		address user1 = address(0xabcdef);
		address user2 = address(0x123456);

		// Set daily transfer limit to 3 ether (less than the expected profit)
		vm.startPrank(_admin);
		morpherToken.setDailyMintedTransferLimit(3 ether);
		morpherToken.mint(user1, 10 ether);
		vm.stopPrank();

		// User1 transfers to User2
		vm.startPrank(user1);
		morpherToken.transfer(user2, 10 ether);
		vm.stopPrank();

		// Verify initial state
		assertEq(morpherToken.getTransferredInTokens(user2), 10 ether);

		// TradeEngine burns tokens (opening a position)
		vm.startPrank(morpherState.morpherTradeEngineAddress());
		morpherToken.burn(user2, 10 ether);
		vm.stopPrank();

		// Verify state after burning - transferred in tokens remain the same
		assertEq(morpherToken.balanceOf(user2), 0);
		assertEq(morpherToken.getTransferredInTokens(user2), 10 ether);

		// TradeEngine mints tokens back (closing position with 100% profit)
		vm.startPrank(morpherState.morpherTradeEngineAddress());
		morpherToken.mint(user2, 20 ether); // 10 original + 10 profit
		vm.stopPrank();

		// Verify state after minting
		assertEq(morpherToken.balanceOf(user2), 20 ether);
		assertEq(morpherToken.getTransferredInTokens(user2), 10 ether);

		// User2 should be able to transfer transferred-in tokens (10 ether) plus up to the daily limit (3 ether)
		vm.startPrank(user2);
		morpherToken.transfer(user1, 13 ether);
		vm.stopPrank();

		// Verify state after first transfer
		assertEq(morpherToken.balanceOf(user2), 7 ether);
		assertEq(morpherToken.balanceOf(user1), 13 ether);
		assertEq(morpherToken.getTransferredInTokens(user2), 0); // Transferred-in tokens fully used
		assertEq(morpherToken.getDailyMintedTransfers(user2), 3 ether); // 3 ether counted toward daily limit

		// Try to transfer more than the remaining daily limit
		vm.startPrank(user2);
		vm.expectRevert("MorpherToken: daily minted token transfer limit exceeded");
		morpherToken.transfer(user1, 4 ether); // Would exceed daily limit
		vm.stopPrank();

		// Transfer exactly at the remaining limit
		vm.startPrank(user2);
		morpherToken.transfer(user1, 0 ether); // No more transfers allowed today
		vm.stopPrank();

		// Verify final state
		assertEq(morpherToken.balanceOf(user2), 7 ether);
		assertEq(morpherToken.balanceOf(user1), 13 ether);
		assertEq(morpherToken.getDailyMintedTransfers(user2), 3 ether);
	}

	// --- Additional Tests for Coverage ---

	// --- _update Function Tests ---

	function testUpdateTransferRestrictionFailNoRole() public {
		address user1 = makeAddr("user1");
		address user2 = makeAddr("user2");
		vm.startPrank(_admin);
		morpherToken.mint(user1, 1 ether);
		morpherToken.setRestrictTransfers(true); // Enable restriction
		vm.stopPrank();

		vm.startPrank(user1);
		// User1 lacks TRANSFER_ROLE, MINTER_ROLE, BURNER_ROLE
		vm.expectRevert("MorpherToken: Transfer denied by restriction");
		morpherToken.transfer(user2, 1 ether);
		vm.stopPrank();
	}

	function testUpdateTransferRestrictionSuccessSenderRole() public {
		address user1 = makeAddr("user1");
		address user2 = makeAddr("user2");
		// Grant TRANSFER_ROLE to sender
		morpherAccessControl.grantRole(morpherToken.TRANSFER_ROLE(), user1);
		
		vm.startPrank(_admin);
		morpherToken.mint(user1, 1 ether);
		morpherToken.setRestrictTransfers(true); // Enable restriction
		vm.stopPrank();

		vm.startPrank(user1);
		morpherToken.transfer(user2, 1 ether); // Should succeed
		vm.stopPrank();
		assertEq(morpherToken.balanceOf(user2), 1 ether);
	}

	function testUpdateTransferRestrictionSuccessMinterRole() public {
		address user1 = makeAddr("user1");
		address user2 = makeAddr("user2");
		address minter = makeAddr("minter"); // Use a separate minter address for clarity
		// Grant MINTER_ROLE to caller (minter)
		morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), minter);

		vm.startPrank(_admin);
		morpherToken.mint(user1, 1 ether);
		morpherToken.setRestrictTransfers(true); // Enable restriction
		vm.stopPrank(); // Stop admin prank
		// Approve minter to spend user1's tokens
		vm.prank(user1);
		morpherToken.approve(minter, 1 ether);

		vm.startPrank(minter);
		morpherToken.transferFrom(user1, user2, 1 ether); // Should succeed as minter
		vm.stopPrank();
		assertEq(morpherToken.balanceOf(user2), 1 ether);
	}

	function testUpdateTransferBlockedFailSender() public {
		address user1 = makeAddr("user1");
		address user2 = makeAddr("user2");
		morpherAccessControl.grantRole(morpherToken.TRANSFERBLOCKED_ROLE(), user1);

		vm.startPrank(_admin);
		morpherToken.mint(user1, 1 ether);
		// Block the sender
		vm.stopPrank();

		vm.startPrank(user1);
		vm.expectRevert("MorpherToken: Transfer for sender is blocked.");
		morpherToken.transfer(user2, 1 ether);
		vm.stopPrank();
	}

	function testUpdateTransferBlockedFailReceiver() public {
		address user1 = makeAddr("user1");
		address user2 = makeAddr("user2");
		morpherAccessControl.grantRole(morpherToken.TRANSFERBLOCKED_ROLE(), user2);

		vm.startPrank(_admin);
		morpherToken.mint(user1, 1 ether);
		// Block the receiver
		vm.stopPrank();

		vm.startPrank(user1);
		vm.expectRevert("MorpherToken: Transfer for receiver is blocked.");
		morpherToken.transfer(user2, 1 ether);
		vm.stopPrank();
	}

	function testUpdateDailyLimitAdminBypass() public {
		address user = makeAddr("user");
		address recipient = makeAddr("recipient");
		vm.startPrank(_admin);
		morpherToken.setDailyMintedTransferLimit(1 ether); // Set low limit
		morpherToken.mint(user, 10 ether); // Mint more than limit
		vm.stopPrank(); // Stop user prank
		// Approve admin to spend user's tokens
		vm.prank(user);
		morpherToken.approve(_admin, 10 ether);
		

		// Transfer as admin - should bypass limit
		vm.startPrank(_admin);
		morpherToken.transferFrom(user, recipient, 5 ether); // Transfer more than limit
		vm.stopPrank();

		assertEq(morpherToken.balanceOf(recipient), 5 ether);
		// Daily minted transfers for user should still be 0 as admin bypassed
		assertEq(morpherToken.getDailyMintedTransfers(user), 0);
	}

	function testUpdateDailyLimitTradeEngineBypass() public {
		address user = makeAddr("user");
		address recipient = makeAddr("recipient");
		address tradeEngine = morpherState.morpherTradeEngineAddress();
		vm.startPrank(_admin);
		morpherToken.setDailyMintedTransferLimit(1 ether); // Set low limit
		morpherToken.mint(user, 10 ether); // Mint more than limit

		vm.stopPrank(); // Stop user prank
		// Approve trade engine to spend user's tokens
		vm.prank(user);
		morpherToken.approve(tradeEngine, 10 ether);

		// Transfer as trade engine - should bypass limit logic
		vm.startPrank(tradeEngine);
		morpherToken.transferFrom(user, recipient, 5 ether); // Transfer more than limit
		vm.stopPrank();

		assertEq(morpherToken.balanceOf(recipient), 5 ether);
		// Daily minted transfers for user should still be 0 as trade engine bypassed
		assertEq(morpherToken.getDailyMintedTransfers(user), 0);
	}

	// --- Mint/Burn Role Tests ---

	function testMintFailNoRole() public {
		address user = makeAddr("user");
		address nonMinter = makeAddr("nonMinter");
		vm.startPrank(nonMinter);
		// Use generic role error message from modifier
		vm.expectRevert("MorpherToken: must have minter role to mint");
		morpherToken.mint(user, 1 ether);
		vm.stopPrank();
	}

	function testBurnFailNoRole() public {
		address user = makeAddr("user");
		address nonBurner = makeAddr("nonBurner");
		vm.startPrank(_admin);
		morpherToken.mint(user, 1 ether);
		vm.stopPrank();

		vm.startPrank(nonBurner);
		// Use generic role error message from modifier
		vm.expectRevert("MorpherToken: must have burner role to burn");
		morpherToken.burn(user, 1 ether);
		vm.stopPrank();
	}

	// --- Pause/Unpause Role and Functionality Tests ---

	function testPauseFailNoRole() public {
		address nonPauser = makeAddr("nonPauser");
		vm.startPrank(nonPauser);
		vm.expectRevert("MorpherToken: must have pauser role to pause");
		morpherToken.pause();
		vm.stopPrank();
	}

	function testUnpauseFailNoRole() public {
		address nonPauser = makeAddr("nonPauser");
		// Pause first
		vm.startPrank(_pauser);
		morpherToken.pause();
		vm.stopPrank();

		// Attempt unpause without role
		vm.startPrank(nonPauser);
		vm.expectRevert("MorpherToken: must have pauser role to unpause");
		morpherToken.unpause();
		vm.stopPrank();
	}

	function testTransferFailWhenPaused() public {
		address user1 = makeAddr("user1");
		address user2 = makeAddr("user2");
		vm.startPrank(_admin);
		morpherToken.mint(user1, 1 ether);
		vm.stopPrank();

		// Pause
		vm.startPrank(_pauser);
		morpherToken.pause();
		vm.stopPrank();

		// Attempt transfer
		vm.startPrank(user1);
		vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
		morpherToken.transfer(user2, 1 ether);
		vm.stopPrank();
	}

	// --- Locking Function Role Tests ---

	function testLockRewardsFailNoRole() public {
		address user = makeAddr("user");
		address nonAirdropAdmin = makeAddr("nonAirdropAdmin");
		vm.startPrank(_admin);
		morpherToken.mint(user, 1 ether);
		vm.stopPrank();

		vm.startPrank(nonAirdropAdmin);
		// Use generic role error message from modifier
		vm.expectRevert("MorpherToken: Missing required role.");
		morpherToken.lockRewards(user, 1 ether);
		vm.stopPrank();
	}

	function testUnlockRewardsFailNoRole() public {
		address user = makeAddr("user");
		address nonAdmin = makeAddr("nonAdmin");
		// Grant AIRDROPADMIN_ROLE to admin for locking
		morpherAccessControl.grantRole(morpherToken.AIRDROPADMIN_ROLE(), _admin);
		vm.startPrank(_admin);
		morpherToken.mint(user, 1 ether);
		morpherToken.lockRewards(user, 1 ether);
		vm.stopPrank();

		vm.startPrank(nonAdmin);
		// Use generic role error message from modifier
		vm.expectRevert("MorpherToken: Missing required role.");
		morpherToken.unlockRewards(user, 1 ether);
		vm.stopPrank();
	}

	function testLockTokensForTimeFailNoRole() public {
		address user = makeAddr("user");
		address nonAdmin = makeAddr("nonAdmin");
		vm.startPrank(_admin);
		morpherToken.mint(user, 1 ether);
		vm.stopPrank();

		vm.startPrank(nonAdmin);
		// Use generic role error message from modifier
		vm.expectRevert("MorpherToken: Missing required role.");
		morpherToken.lockTokensForTime(user, 1 ether, 1 days);
		vm.stopPrank();
	}

	// --- Setter Role Tests ---

	function testSetRestrictTransfersFailNoRole() public {
		address nonAdmin = makeAddr("nonAdmin");
		vm.startPrank(nonAdmin);
		// Use generic role error message from modifier
		vm.expectRevert("MorpherToken: Missing required role.");
		morpherToken.setRestrictTransfers(true);
		vm.stopPrank();
	}


	function testSetTotalInPositionsFailNoRole() public {
		address nonUpdater = makeAddr("nonUpdater");
		vm.startPrank(nonUpdater);
		// Use generic role error message from modifier
		vm.expectRevert("MorpherToken: Missing required role.");
		morpherToken.setTotalInPositions(1 ether);
		vm.stopPrank();
	}

	function testSetDailyMintedTransferLimitFailNoRole() public {
		address nonAdmin = makeAddr("nonAdmin");
		vm.startPrank(nonAdmin);
		// Use generic role error message from modifier
		vm.expectRevert("MorpherToken: Missing required role.");
		morpherToken.setDailyMintedTransferLimit(1 ether);
		vm.stopPrank();
	}

	// --- Permit Edge Case Tests ---

	function testPermitFailExpiredDeadline() public {
		Account memory owner = makeAccount("owner");
		address spender = address(0xdef);
		uint value = 1 ether;
		uint deadline = block.timestamp - 1; // Expired deadline

		vm.startPrank(_admin);
		morpherToken.mint(owner.addr, value);
		vm.stopPrank();

		uint nonce = morpherToken.nonces(owner.addr);

		// Generate signature using helper
		(uint8 v, bytes32 r, bytes32 s) = _generatePermitSignature(owner, spender, value, nonce, deadline);

		// Use correct OZ v5 error signature
		vm.expectRevert(abi.encodeWithSelector(ERC20PermitUpgradeable.ERC2612ExpiredSignature.selector, deadline));
		morpherToken.permit(owner.addr, spender, value, deadline, v, r, s);
	}

	function testPermitFailInvalidSignature() public {
		Account memory owner = makeAccount("owner");
		Account memory wrongSigner = makeAccount("wrongSigner");
		// Inlined spender, value, deadline below where possible

		vm.startPrank(_admin);
		morpherToken.mint(owner.addr, 1 ether); // Use literal value
		vm.stopPrank();

		uint nonce = morpherToken.nonces(owner.addr);
		uint256 currentDeadline = block.timestamp + 1 hours; // Store deadline once

		// Combine hash generation slightly
		bytes32 structHash = keccak256(
			abi.encode(
				keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
				owner.addr,
				address(0xdef), // Inline spender
				1 ether, // Inline value
				nonce,
				currentDeadline // Use stored deadline
			)
		);
		bytes32 finalHash = MessageHashUtils.toTypedDataHash(morpherToken.DOMAIN_SEPARATOR(), structHash);

		// Sign the digest with the wrong signer's key
		(uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongSigner.key, finalHash);

		// Use correct OZ v5 error signature
		vm.expectRevert(
			abi.encodeWithSelector(ERC20PermitUpgradeable.ERC2612InvalidSigner.selector, wrongSigner.addr, owner.addr)
		);
		// Call permit with literals/stored deadline
		morpherToken.permit(owner.addr, address(0xdef), 1 ether, currentDeadline, v, r, s);
	}

	function testPermitFailReplay() public {
		Account memory owner = makeAccount("owner");
		address spender = address(0xdef);
		uint value = 1 ether;
		uint deadline = block.timestamp + 1 hours;

		vm.startPrank(_admin);
		morpherToken.mint(owner.addr, value);
		vm.stopPrank();

		uint nonce = morpherToken.nonces(owner.addr);

		// Generate signature using helper
		(uint8 v, bytes32 r, bytes32 s) = _generatePermitSignature(owner, spender, value, nonce, deadline);

		// First call succeeds
		morpherToken.permit(owner.addr, spender, value, deadline, v, r, s);
		assertEq(morpherToken.nonces(owner.addr), nonce + 1);

		assertEq(morpherToken.nonces(owner.addr), nonce + 1);

		// Second call with same signature should fail due to nonce mismatch, resulting in an invalid signer error
		// Use try/catch to check only the selector, as vm.expectRevert(selector) seems to compare full data
		try morpherToken.permit(owner.addr, spender, value, deadline, v, r, s) {
			revert("Second permit call should have reverted");
		} catch (bytes memory revertData) {
			// Check if the revert data starts with the expected selector
			bytes4 actualSelector;
			// Ensure revertData is long enough to contain the selector
			if (revertData.length >= 4) {
				assembly {
					actualSelector := mload(add(revertData, 0x20))
				}
			}
			assertEq(actualSelector, ERC20PermitUpgradeable.ERC2612InvalidSigner.selector, "Incorrect error selector");
		}
	}

	// --- Helper Function for Permit Signature Generation ---

	/**
	 * @dev Internal helper to generate permit signature components.
	 */
	function _generatePermitSignature(
		Account memory owner,
		address spender,
		uint256 value,
		uint256 nonce,
		uint256 deadline
	) internal view returns (uint8 v, bytes32 r, bytes32 s) {
		// Rebuild Permit typehash locally for signing
		bytes32 permitTypehash = keccak256(
			"Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
		);

		// Hash the struct data
		bytes32 structHash = keccak256(abi.encode(permitTypehash, owner.addr, spender, value, nonce, deadline));

		// Get domain separator from the contract
		bytes32 domainSeparator = morpherToken.DOMAIN_SEPARATOR();

		// Create the EIP712 digest
		bytes32 finalHash = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);

		// Sign the digest
		(v, r, s) = vm.sign(owner.key, finalHash);
	}

	// --- Tests for getTransferableBalanceToday ---

	function testTransferableBalance_InitialState() public {
		address user = makeAddr("user");
		assertEq(morpherToken.getTransferableBalanceToday(user), 0, "Initial balance should be 0");

		// Mint some tokens (as admin, counts as transferred-in)
		vm.startPrank(_admin);
		morpherToken.mint(user, 10 ether);
		vm.stopPrank();
		// Without daily limit set, all should be transferable
		assertEq(morpherToken.getTransferableBalanceToday(user), 10 ether, "Admin minted balance should be transferable");
	}

	function testTransferableBalance_MintedByLimiter_NoLimit() public {
		address user = makeAddr("user");

		vm.startPrank(_admin);
		morpherToken.setDailyMintedTransferLimit(type(uint256).max);
		// Mint tokens as MintingLimiter (does not count as transferred-in)
		vm.startPrank(morpherState.morpherMintingLimiterAddress());
		morpherToken.mint(user, 10 ether);
		vm.stopPrank();
		// With the daily limit set to uint256 max all should be transferable (limit is effectively infinity)
		assertEq(morpherToken.getTransferableBalanceToday(user), 10 ether, "Limiter minted balance transferable without limit");
	}
	function testTransferableBalance_MintedByLimiter_NoLimitSet() public {
		address user = makeAddr("user");

		// Mint tokens as MintingLimiter (does not count as transferred-in)
		vm.startPrank(morpherState.morpherMintingLimiterAddress());
		morpherToken.mint(user, 10 ether);
		vm.stopPrank();
		// Without daily limit set nothing should be transferrablöe
		assertEq(morpherToken.getTransferableBalanceToday(user), 0, "Limiter minted balance transferable without limit");
	}

	function testTransferableBalance_MintedByLimiter_WithLimit() public {
		address user = makeAddr("user");
		// Set daily limit
		vm.startPrank(_admin);
		morpherToken.setDailyMintedTransferLimit(3 ether);
		vm.stopPrank();

		// Mint tokens as MintingLimiter (does not count as transferred-in)
		vm.startPrank(morpherState.morpherMintingLimiterAddress());
		morpherToken.mint(user, 10 ether);
		vm.stopPrank();

		// Transferable balance should be capped by the daily limit
		assertEq(morpherToken.getTransferableBalanceToday(user), 3 ether, "Limiter minted balance capped by limit");
	}

	function testTransferableBalance_TransferredIn() public {
		address user1 = makeAddr("user1");
		address user2 = makeAddr("user2");

		// Mint to user1 (as admin, counts as transferred-in for user1 initially)
		vm.startPrank(_admin);
		morpherToken.mint(user1, 10 ether);
		vm.stopPrank();

		assertEq(morpherToken.getTransferableBalanceToday(user1), 10 ether, "User1 initial transferable");
		assertEq(morpherToken.getTransferableBalanceToday(user2), 0 ether, "User2 initial transferable");

		// User1 transfers to User2
		vm.startPrank(user1);
		morpherToken.transfer(user2, 7 ether);
		vm.stopPrank();

		// User1's transferable balance decreases
		assertEq(morpherToken.getTransferableBalanceToday(user1), 3 ether, "User1 transferable after sending");
		// User2's transferable balance increases by the transferred amount
		assertEq(morpherToken.getTransferableBalanceToday(user2), 7 ether, "User2 transferable after receiving");
		assertEq(morpherToken.getTransferredInTokens(user2), 7 ether, "User2 transferred-in tokens correct");
	}

	function testTransferableBalance_LockedRewards() public {
		address user = makeAddr("user");
		// Grant AIRDROPADMIN_ROLE to admin for reward locking
		morpherAccessControl.grantRole(morpherToken.AIRDROPADMIN_ROLE(), _admin);

		// Mint tokens (as admin, counts as transferred-in)
		vm.startPrank(_admin);
		morpherToken.mint(user, 10 ether);
		assertEq(morpherToken.getTransferableBalanceToday(user), 10 ether, "Transferable before lock");

		// Lock rewards
		morpherToken.lockRewards(user, 4 ether);
		vm.stopPrank();

		// Transferable balance should exclude locked rewards
		assertEq(morpherToken.getTransferableBalanceToday(user), 6 ether, "Transferable after lock");
		assertEq(morpherToken.balanceOf(user), 6 ether, "balanceOf excludes locked");
		assertEq(morpherToken.getTradeableBalanceOf(user), 10 ether, "tradeableBalanceOf includes locked");
	}

	function testTransferableBalance_TimeLock() public {
		address user = makeAddr("user");
		uint256 lockDuration = 30 days;

		// Mint tokens (as admin, counts as transferred-in)
		vm.startPrank(_admin);
		morpherToken.mint(user, 10 ether);
		assertEq(morpherToken.getTransferableBalanceToday(user), 10 ether, "Transferable before time lock");

		// Lock tokens
		morpherToken.lockTokensForTime(user, 6 ether, lockDuration);
		vm.stopPrank();

		// Transferable balance should exclude time-locked tokens
		assertEq(morpherToken.getTransferableBalanceToday(user), 4 ether, "Transferable during time lock");
		assertEq(morpherToken.balanceOf(user), 4 ether, "balanceOf excludes time lock");

		// Warp past lock duration
		vm.warp(block.timestamp + lockDuration + 1 days);

		// Transferable balance should now include the unlocked tokens
		assertEq(morpherToken.getTransferableBalanceToday(user), 10 ether, "Transferable after time lock expired");
		assertEq(morpherToken.balanceOf(user), 10 ether, "balanceOf after time lock expired");
	}

	function testTransferableBalance_MintedByTradeEngine() public {
		address user = makeAddr("user");
		// Set daily limit
		vm.startPrank(_admin);
		morpherToken.setDailyMintedTransferLimit(5 ether);
		vm.stopPrank();

		// Mint tokens as TradeEngine (does not count as transferred-in)
		vm.startPrank(morpherState.morpherTradeEngineAddress());
		morpherToken.mint(user, 10 ether);
		vm.stopPrank();

		// Transferable balance should be capped by the daily limit
		assertEq(morpherToken.getTransferableBalanceToday(user), 5 ether, "TradeEngine minted balance capped by limit");
	}

	function testTransferableBalance_Combined() public {
		address user1 = makeAddr("user1");
		address user2 = makeAddr("user2");

		// Set daily limit
		vm.startPrank(_admin);
		morpherToken.setDailyMintedTransferLimit(5 ether);
		// Mint some tokens to user1 (counts as transferred-in)
		morpherToken.mint(user1, 10 ether);
		vm.stopPrank();

		// User1 transfers 6 ether to user2
		vm.startPrank(user1);
		morpherToken.transfer(user2, 6 ether);
		vm.stopPrank();

		// User2 now has 6 ether (transferred-in)
		assertEq(morpherToken.getTransferredInTokens(user2), 6 ether, "User2 transferred-in correct");
		assertEq(morpherToken.getTransferableBalanceToday(user2), 6 ether, "User2 transferable is transferred-in amount");

		// MintingLimiter mints 10 ether to user2 (minted)
		vm.startPrank(morpherState.morpherMintingLimiterAddress());
		morpherToken.mint(user2, 10 ether);
		vm.stopPrank();

		// User2 has 6 (transferred) + 10 (minted) = 16 total
		// Transferable = 6 (transferred) + min(10 minted, 5 daily limit) = 11
		assertEq(morpherToken.balanceOf(user2), 16 ether, "User2 total balance");
		assertEq(morpherToken.getTransferableBalanceToday(user2), 11 ether, "User2 transferable combined");

		// User2 transfers 8 ether out
		vm.startPrank(user2);
		morpherToken.transfer(user1, 8 ether);
		vm.stopPrank();

		// Should use 6 transferred-in first, then 2 from minted (counts towards daily limit)
		assertEq(morpherToken.getTransferredInTokens(user2), 0, "User2 transferred-in after transfer");
		assertEq(morpherToken.getDailyMintedTransfers(user2), 2 ether, "User2 daily minted transferred");
		assertEq(morpherToken.balanceOf(user2), 8 ether, "User2 balance after transfer"); // 16 - 8

		// Remaining daily limit = 5 - 2 = 3
		// Remaining minted balance = 10 - 2 = 8
		// Transferable = 0 (transferred) + min(8 minted, 3 remaining limit) = 3
		assertEq(morpherToken.getTransferableBalanceToday(user2), 3 ether, "User2 transferable after transfer");
	}

	function testTransferableBalance_NextDayReset() public {
		address user = makeAddr("user");
		// Set daily limit
		vm.startPrank(_admin);
		morpherToken.setDailyMintedTransferLimit(5 ether);
		vm.stopPrank();

		// Mint tokens as MintingLimiter
		vm.startPrank(morpherState.morpherMintingLimiterAddress());
		morpherToken.mint(user, 10 ether);
		vm.stopPrank();

		// Transferable is capped
		assertEq(morpherToken.getTransferableBalanceToday(user), 5 ether, "Transferable day 1");

		// Transfer some minted tokens
		vm.startPrank(user);
		morpherToken.transfer(makeAddr("recipient"), 3 ether);
		vm.stopPrank();

		// Remaining limit is 2
		assertEq(morpherToken.getTransferableBalanceToday(user), 2 ether, "Transferable day 1 after transfer");
		assertEq(morpherToken.getDailyMintedTransfers(user), 3 ether, "Daily transferred day 1");

		// Warp to the next day
		vm.warp(block.timestamp + 1 days);

		// Daily limit should reset
		// Remaining minted balance = 10 - 3 = 7
		// Transferable = min(7 minted, 5 new daily limit) = 5
		assertEq(morpherToken.getTransferableBalanceToday(user), 5 ether, "Transferable day 2 (limit reset)");
		assertEq(morpherToken.getDailyMintedTransfers(user), 0 ether, "Daily transferred day 2 (reset)");
	}
}
