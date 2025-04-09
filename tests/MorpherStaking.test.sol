// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "./BaseSetup.sol";

contract MorkpherStakingTest is BaseSetup {
	uint256 constant INTERVAL = 1 days;

	event SetLockupPeriod(uint256 newLockupPeriod);
	event SetMinimumStake(uint256 newMinimumStake);

	event PoolShareValueUpdated(uint256 indexed lastReward, uint256 poolShareValue);
	event Staked(address indexed userAddress, uint256 indexed amount, uint256 poolShares, uint256 lockedUntil);
	event Unstaked(address indexed userAddress, uint256 indexed amount, uint256 poolShares);

	// EIP712 typehashes (must match contract)
	bytes32 constant STAKE_TYPEHASH = keccak256("Stake(uint256 amount,address owner,uint256 nonce,uint256 deadline)");
	bytes32 constant UNSTAKE_TYPEHASH = keccak256("Unstake(uint256 shares,address owner,uint256 nonce,uint256 deadline)");

	// Test user private key
	uint256 constant TEST_USER_PK = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
	address testUserWithPK = vm.addr(TEST_USER_PK);

	// Struct for stake permit test data
	struct StakePermitTestData {
		address owner_addr;
		uint256 stake_amount;
		uint256 initial_nonce;
		uint256 expectedPoolSharesVal;
		uint256 expectedLockedUntilVal;
		uint256 actualPoolShares;
		// We'll fetch initial balance/shares in the specific tests
	}

	function setUp() public override {
		super.setUp();
		morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(this));
		morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), testUserWithPK); // Mint for test user

		// Fund the test user with PK
		morpherToken.mint(testUserWithPK, 1_000_000 * 1e18);

		// EIP712 domain is now hardcoded in the contract via override, no special init needed for tests.
	}

	// ADMINISTRATIVE FUNCTIONS --------------------------------------------------------------------

	function testAdministrativeFunctions() public {
		address admin = address(0x1234);
		morpherAccessControl.grantRole(morpherStaking.ADMINISTRATOR_ROLE(), admin);
		morpherAccessControl.grantRole(morpherStaking.STAKINGADMIN_ROLE(), admin);

		vm.warp(1670000000);
		vm.prank(admin);
		morpherInterestRateManager.setInterestRate(50000);

		uint currentRate = morpherInterestRateManager.interestRate();
		assertEq(currentRate, 50000);


		vm.prank(admin);
		morpherStaking.setInterestRate(50000);
		assertEq(morpherStaking.interestRate(), 50000);

		vm.prank(admin);
		vm.expectEmit(true, true, true, true);
		emit SetLockupPeriod(35 days);
		morpherStaking.setLockupPeriodRate(35 days);
		uint lockupPeriod = morpherStaking.lockupPeriod();
		assertEq(lockupPeriod, 35 days);

		vm.prank(admin);
		vm.expectEmit(true, true, true, true);
		emit SetMinimumStake(10 ** 24);
		morpherStaking.setMinimumStake(10 ** 24);
		uint minimumStake = morpherStaking.minimumStake();
		assertEq(minimumStake, 10 ** 24);

	}

	// UPDATE POOL SHARE VALUE ---------------------------------------------------------------------

	function testShouldNotUpdatePoolShareInLessThanOneDay() public {
		// deployed at first interest rate timestamp!
		vm.warp(1617094819);

		uint256 initialPoolShareValue = morpherStaking.poolShareValue();
		uint256 initialLastReward = morpherStaking.lastReward();

		uint256 lessThanOneDay = INTERVAL - 1;
		vm.warp(block.timestamp + lessThanOneDay);

		morpherStaking.updatePoolShareValue();

		assertEq(morpherStaking.poolShareValue(), initialPoolShareValue);
		assertEq(morpherStaking.lastReward(), initialLastReward);
	}

	function testEventAndPoolShareValueUpdateAfterOneDay() public {
		vm.warp(1617094819);

		uint256 initialPoolShareValue = morpherStaking.poolShareValue();
		uint256 interestRate = morpherStaking.interestRate();
		uint256 initialLastReward = morpherStaking.lastReward();

		vm.warp(block.timestamp + INTERVAL);

		vm.expectEmit(true, true, true, true);
		emit PoolShareValueUpdated(initialLastReward + INTERVAL, initialPoolShareValue + interestRate);

		morpherStaking.updatePoolShareValue();

		assertEq(morpherStaking.poolShareValue(), initialPoolShareValue + interestRate);
		assertEq(morpherStaking.lastReward(), initialLastReward + INTERVAL);
	}

	function testPoolShareValueUpdateAfterMultipleIntervals() public {
		vm.warp(1617094819);

		uint256 initialPoolShareValue = morpherStaking.poolShareValue();
		uint256 interestRate = morpherStaking.interestRate();
		uint256 initialLastReward = morpherStaking.lastReward();

		vm.warp(block.timestamp + (5 * INTERVAL) + 50000);

		morpherStaking.updatePoolShareValue();

		uint256 expectedPoolShareValueAfter5Days = initialPoolShareValue + (5 * interestRate);
		uint256 expectedLastRewardAfter5Days = initialLastReward + (5 * INTERVAL);

		assertEq(morpherStaking.poolShareValue(), expectedPoolShareValueAfter5Days);
		assertEq(morpherStaking.lastReward(), expectedLastRewardAfter5Days);

		vm.warp(block.timestamp + (10 * INTERVAL) + 50000);

		morpherStaking.updatePoolShareValue();

		uint256 expectedPoolShareValueAfter16Days = expectedPoolShareValueAfter5Days + (11 * interestRate);
		uint256 expectedLastRewardAfter16Days = expectedLastRewardAfter5Days + (11 * INTERVAL);

		assertEq(morpherStaking.poolShareValue(), expectedPoolShareValueAfter16Days);
		assertEq(morpherStaking.lastReward(), expectedLastRewardAfter16Days);
	}

	// STAKE ---------------------------------------------------------------------------------------

	function testShouldHaveTokensToStake() public {
		address user = address(0xff01);
		uint256 minimumStake = morpherStaking.minimumStake();
		uint256 userBalance = minimumStake - 1;

		morpherToken.mint(user, userBalance);

		vm.prank(user);
		morpherToken.approve(address(morpherStaking), userBalance + 1);

		vm.prank(user);
		vm.expectRevert();
		morpherStaking.stake(userBalance + 1);
	}

	function testShouldStakeMinimumStake() public {
		address user = address(0xff01);
		uint256 minimumStake = morpherStaking.minimumStake();
		uint256 userBalance = minimumStake;

		morpherToken.mint(user, userBalance);

		vm.prank(user);
		morpherToken.approve(address(morpherStaking), userBalance);

		vm.prank(user);
		vm.expectRevert();
		morpherStaking.stake(userBalance - 1);
	}

	function testStakeSuccess() public {
		vm.warp(1617094819);

		address user = address(0xff01);
		uint256 stakeAmount = 300000 * 1e18;

		morpherToken.mint(user, stakeAmount);

		vm.prank(user);
		morpherToken.approve(address(morpherStaking), stakeAmount);

		uint resultingPoolShares = stakeAmount / morpherStaking.poolShareValue();

		uint expectedLockedUntil = block.timestamp + morpherStaking.lockupPeriod();
		vm.prank(user);
		vm.expectEmit(true, true, true, true);
		emit Staked(user, stakeAmount, resultingPoolShares, expectedLockedUntil);
		morpherStaking.stake(stakeAmount);

		assertEq(morpherToken.balanceOf(user), 0);
		assertEq(morpherStaking.totalShares(), resultingPoolShares);
		(uint numPoolShares, uint lockedUntil) = morpherStaking.poolShares(user);
		assertEq(numPoolShares, resultingPoolShares);
		assertEq(lockedUntil, expectedLockedUntil);
		uint numPoolSharesAgain = morpherStaking.getStake(user);
		assertEq(numPoolShares, numPoolSharesAgain);
		uint expectedShareValue = resultingPoolShares * morpherStaking.poolShareValue();
		(uint _value, ) = morpherStaking.getStakeValue(user);
		assertEq(_value, expectedShareValue);

		// total share value = user share value
		uint totalValue = morpherStaking.getTotalPooledValue();
		assertEq(totalValue, expectedShareValue);
	}

	function testMultipleStake() public {
		vm.warp(1617094819);

		address user = address(0xff01);
		address userB = address(0xff02);
		uint256 stakeAmount = 300000 * 1e18;
		uint256 stake2Amount = 200000 * 1e18;
		morpherToken.mint(user, stakeAmount + stake2Amount);
		morpherToken.mint(userB, stakeAmount + stake2Amount);
		vm.prank(user);
		morpherToken.approve(address(morpherStaking), stakeAmount + stake2Amount);
		vm.prank(userB);
		morpherToken.approve(address(morpherStaking), stake2Amount);

		vm.prank(user);
		morpherStaking.stake(stakeAmount);
		uint resultingPoolSharesStake1 = stakeAmount / morpherStaking.poolShareValue();

		vm.prank(userB);
		morpherStaking.stake(stake2Amount);
		uint resultingPoolSharesStake2 = stake2Amount / morpherStaking.poolShareValue();

		vm.warp(block.timestamp + 15 * 24 * 60 * 60);

		vm.prank(user);
		morpherStaking.stake(stake2Amount);
		uint resultingPoolSharesStake3 = stake2Amount / morpherStaking.poolShareValue();

		// second stake is not an exact division, it has reminder
		assertEq(
			morpherToken.balanceOf(user),
			stake2Amount - resultingPoolSharesStake3 * morpherStaking.poolShareValue()
		);
		assertEq(morpherToken.balanceOf(userB), stakeAmount);
		uint totalShares = resultingPoolSharesStake1 + resultingPoolSharesStake2 + resultingPoolSharesStake3;
		assertEq(morpherStaking.totalShares(), totalShares);

		// user
		(uint numPoolShares, uint lockedUntil) = morpherStaking.poolShares(user);
		assertEq(numPoolShares, resultingPoolSharesStake1 + resultingPoolSharesStake3);
		assertEq(lockedUntil, block.timestamp + morpherStaking.lockupPeriod());
		uint expectedShareValue = (resultingPoolSharesStake1 + resultingPoolSharesStake3) *
			morpherStaking.poolShareValue();
		(uint _value, ) = morpherStaking.getStakeValue(user);
		assertEq(_value, expectedShareValue);

		// userB
		(uint numPoolShares2, uint lockedUntil2) = morpherStaking.poolShares(userB);
		assertEq(numPoolShares2, resultingPoolSharesStake2);
		assertEq(lockedUntil2, block.timestamp + morpherStaking.lockupPeriod() - 15 * 24 * 60 * 60);
		(uint _value2, ) = morpherStaking.getStakeValue(userB);
		assertEq(_value2, resultingPoolSharesStake2 * morpherStaking.poolShareValue());
	}

	// UNSTAKE -------------------------------------------------------------------------------------

	function testCannotUnstakeMoreThanOwnedShares() public {
		address user = address(0xff01);
		uint256 stakeAmount = 300000 * 1e18;

		morpherToken.mint(user, stakeAmount);

		vm.prank(user);
		morpherToken.approve(address(morpherStaking), stakeAmount);

		vm.prank(user);
		morpherStaking.stake(stakeAmount);

		uint resultingPoolShares = stakeAmount / morpherStaking.poolShareValue();

		vm.warp(block.timestamp + morpherStaking.lockupPeriod());

		vm.prank(user);
		vm.expectRevert();
		morpherStaking.unstake(resultingPoolShares + 1);
	}

	function testCannotUnstakeBeforeLimit() public {
		address user = address(0xff01);
		uint256 stakeAmount = 300000 * 1e18;

		morpherToken.mint(user, stakeAmount);

		vm.prank(user);
		morpherToken.approve(address(morpherStaking), stakeAmount);

		vm.prank(user);
		morpherStaking.stake(stakeAmount);

		uint resultingPoolShares = stakeAmount / morpherStaking.poolShareValue();

		vm.warp(block.timestamp + morpherStaking.lockupPeriod() - 1);

		vm.prank(user);
		vm.expectRevert();
		morpherStaking.unstake(resultingPoolShares);
	}

	

	function testUnstakeSuccess() public {
		vm.warp(1617094819);

		address user = address(0xff01);
		uint256 stakeAmount = 300000 * 1e18;

		morpherToken.mint(user, stakeAmount);

		vm.prank(user);
		morpherToken.approve(address(morpherStaking), stakeAmount);

		uint resultingPoolShares = stakeAmount / morpherStaking.poolShareValue();

		vm.prank(user);
		morpherStaking.stake(stakeAmount);

		vm.warp(block.timestamp + morpherStaking.lockupPeriod());

		morpherStaking.updatePoolShareValue();
		uint expectedAmount = (morpherStaking.poolShareValue() * resultingPoolShares) / 2;

		vm.prank(user);
		vm.expectEmit(true, true, true, true);
		emit Unstaked(user, expectedAmount, resultingPoolShares / 2);
		morpherStaking.unstake(resultingPoolShares / 2);

		assertEq(morpherToken.balanceOf(user), expectedAmount);
		assertEq(morpherStaking.totalShares(), resultingPoolShares / 2);
		(uint numPoolShares, uint lockedUntil) = morpherStaking.poolShares(user);
		assertEq(numPoolShares, resultingPoolShares / 2);
		assertEq(lockedUntil, block.timestamp);
		uint expectedShareValue = (resultingPoolShares / 2) * morpherStaking.poolShareValue();
		(uint _value, ) = morpherStaking.getStakeValue(user);
		assertEq(_value, expectedShareValue);
	}

	// --- Permit Tests ---

	// Internal helper for stakeWithPermit success tests - Returns struct
	function _setupAndStakeWithPermit() internal returns (StakePermitTestData memory testData) {
		vm.warp(1617094819); // Set consistent time

		testData.owner_addr = testUserWithPK;
		testData.stake_amount = 300_000 * 1e18;
		uint256 current_deadline = block.timestamp + 1 hours;
		testData.initial_nonce = morpherStaking.nonces(testData.owner_addr);

		// Approve token transfer
		vm.prank(testData.owner_addr);
		morpherToken.approve(address(morpherStaking), testData.stake_amount);

		// Hash struct
		bytes32 structHash = keccak256(abi.encode(STAKE_TYPEHASH, testData.stake_amount, testData.owner_addr, testData.initial_nonce, current_deadline));
		// Calculate EIP712 digest
		bytes32 domainSeparator = morpherStaking.DOMAIN_SEPARATOR();
		bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
		// Sign
		(uint8 v_sig, bytes32 r_sig, bytes32 s_sig) = vm.sign(TEST_USER_PK, digest);

		// Pre-calculate expected values
		testData.expectedPoolSharesVal = testData.stake_amount / morpherStaking.poolShareValue();
		testData.expectedLockedUntilVal = block.timestamp + morpherStaking.lockupPeriod();

		// Emit event check before the call
		vm.expectEmit(true, true, true, true);
		emit Staked(testData.owner_addr, testData.stake_amount, testData.expectedPoolSharesVal, testData.expectedLockedUntilVal);

		// Call stakeWithPermit
		testData.actualPoolShares = morpherStaking.stakeWithPermit(testData.stake_amount, testData.owner_addr, current_deadline, v_sig, r_sig, s_sig);

		// Return the populated struct
	}

	function testStakeWithPermit_Success_StakingState() public {
		// Fetch initial state before calling helper
		uint256 initialTotalShares = morpherStaking.totalShares();

		// Call helper - receive struct
		StakePermitTestData memory testData = _setupAndStakeWithPermit();

		// Assertions for staking state using struct fields
		assertEq(testData.actualPoolShares, testData.expectedPoolSharesVal, "Incorrect pool shares returned");
		assertEq(morpherStaking.totalShares(), initialTotalShares + testData.expectedPoolSharesVal, "Total shares incorrect"); // Use local initialTotalShares
		(uint numPoolShares, uint lockedUntil) = morpherStaking.poolShares(testData.owner_addr);
		assertEq(numPoolShares, testData.expectedPoolSharesVal, "Stored pool shares incorrect");
		assertEq(lockedUntil, testData.expectedLockedUntilVal, "Lockup incorrect");
	}

	function testStakeWithPermit_Success_TokenBalance() public {
		// Fetch initial state before calling helper
		address owner_addr_local = testUserWithPK; // Need owner address locally too
		uint256 initialBalance = morpherToken.balanceOf(owner_addr_local);

		// Call helper - receive struct
		StakePermitTestData memory testData = _setupAndStakeWithPermit();

		// Assertion for token balance using struct fields
		assertEq(morpherToken.balanceOf(testData.owner_addr), initialBalance - (testData.expectedPoolSharesVal * morpherStaking.poolShareValue()), "Owner balance incorrect"); // Use local initialBalance
	}

	function testStakeWithPermit_Success_Nonce() public {
		// Call helper - receive struct
		StakePermitTestData memory testData = _setupAndStakeWithPermit();

		// Assertion for nonce using struct fields
		assertEq(morpherStaking.nonces(testData.owner_addr), testData.initial_nonce + 1, "Nonce not incremented");
	}

	function testStakeWithPermit_Revert_InvalidSignature() public {
		address owner = testUserWithPK;
		uint256 amount = 300_000 * 1e18;
		uint256 deadline = block.timestamp + 1 hours;
		uint256 nonce = morpherStaking.nonces(owner);

		// Approve token transfer
		vm.prank(owner);
		morpherToken.approve(address(morpherStaking), amount);

		// Hash struct
		bytes32 structHash = keccak256(abi.encode(STAKE_TYPEHASH, amount, owner, nonce, deadline));
		// Calculate EIP712 digest
		bytes32 domainSeparator = morpherStaking.DOMAIN_SEPARATOR();
		bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
		// Sign with wrong key
		(uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBADBADBAD, digest); // Use a different PK

		vm.expectRevert("MorpherStaking: invalid signature");
		morpherStaking.stakeWithPermit(amount, owner, deadline, v, r, s);
	}

	function testStakeWithPermit_Revert_ExpiredDeadline() public {
		address owner = testUserWithPK;
		uint256 amount = 300_000 * 1e18;
		uint256 deadline = block.timestamp - 1 seconds; // Expired
		uint256 nonce = morpherStaking.nonces(owner);

		// Approve token transfer
		vm.prank(owner);
		morpherToken.approve(address(morpherStaking), amount);

		// Hash struct
		bytes32 structHash = keccak256(abi.encode(STAKE_TYPEHASH, amount, owner, nonce, deadline));
		// Calculate EIP712 digest
		bytes32 domainSeparator = morpherStaking.DOMAIN_SEPARATOR();
		bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
		// Sign
		(uint8 v, bytes32 r, bytes32 s) = vm.sign(TEST_USER_PK, digest);

		vm.expectRevert("MorpherStaking: expired deadline");
		morpherStaking.stakeWithPermit(amount, owner, deadline, v, r, s);
	}

	// Internal helper for unstakeWithPermit success tests
	function _setupAndUnstakeWithPermit() internal returns (
		address owner,
		uint256 stakedShares,
		uint256 sharesToUnstake,
		uint256 nonce,
		// uint256 initialTotalShares, // Removed from return
		uint256 balanceAfterStake, // Added return value
		uint256 expectedAmountOut,
		uint256 actualAmountOut
	) {
		vm.warp(1617094819); // Set consistent time
		owner = testUserWithPK;
		uint256 stakeAmount = 300_000 * 1e18;

		// Initial stake
		vm.prank(owner);
		morpherToken.approve(address(morpherStaking), stakeAmount);
		vm.prank(owner);
		stakedShares = morpherStaking.stake(stakeAmount);
		balanceAfterStake = morpherToken.balanceOf(owner); // Get balance *after* stake

		// Warp time past lockup
		vm.warp(block.timestamp + morpherStaking.lockupPeriod() + 1 days);
		morpherStaking.updatePoolShareValue(); // Update value before unstake

		// Prepare unstake permit
		sharesToUnstake = stakedShares / 2;
		// uint256 deadline = block.timestamp + 1 hours; // Inlined below
		nonce = morpherStaking.nonces(owner);

		// Calculate EIP712 digest directly
		bytes32 digest = keccak256(abi.encodePacked(
			"\x19\x01",
			morpherStaking.DOMAIN_SEPARATOR(),
			keccak256(abi.encode(
				UNSTAKE_TYPEHASH,
				sharesToUnstake,
				owner,
				nonce,
				block.timestamp + 1 hours // Inlined deadline
			))
		));
		// Sign
		(uint8 v, bytes32 r, bytes32 s) = vm.sign(TEST_USER_PK, digest);

		// Pre-calculate values (excluding initial total shares)
		// initialTotalShares = morpherStaking.totalShares(); // Removed calculation
		expectedAmountOut = sharesToUnstake * morpherStaking.poolShareValue();

		// Emit check
		vm.expectEmit(true, true, true, true);
		emit Unstaked(owner, expectedAmountOut, sharesToUnstake);

		// Call unstakeWithPermit (inlining deadline)
		actualAmountOut = morpherStaking.unstakeWithPermit(sharesToUnstake, owner, block.timestamp + 1 hours, v, r, s);
	}


	function testUnstakeWithPermit_Success_Amount() public {
		// Call helper
		(,,,,, uint256 expectedAmountOut, uint256 actualAmountOut) = _setupAndUnstakeWithPermit(); // Adjusted destructuring (6 return values now)

		// Assertions
		assertEq(actualAmountOut, expectedAmountOut, "Incorrect amount returned");
	}

	function testUnstakeWithPermit_Success_TokenBalance() public {
		// Fetch initial state before calling helper
		// uint256 initialBalance = morpherToken.balanceOf(owner_local); // No longer needed here

		// Call helper
		(address owner, , , , uint256 balanceAfterStake, uint256 expectedAmountOut,) = _setupAndUnstakeWithPermit(); // Adjusted destructuring

		// Assertions
		assertEq(morpherToken.balanceOf(owner), balanceAfterStake + expectedAmountOut, "Owner balance incorrect after unstake");
	}

	function testUnstakeWithPermit_Success_StakingState() public {
		// Fetch initial state before calling helper
		address owner_local = testUserWithPK; // Need owner address locally too
		uint256 initialTotalShares = morpherStaking.totalShares();

		// Call helper
		(address owner, uint256 stakedShares, uint256 sharesToUnstake, , , ,) = _setupAndUnstakeWithPermit(); // Adjusted destructuring (7 return values now)

		// Assertions
		assertEq(morpherStaking.totalShares(), initialTotalShares - sharesToUnstake, "Total shares incorrect"); // Use local initialTotalShares
		(uint numPoolShares, ) = morpherStaking.poolShares(owner);
		assertEq(numPoolShares, stakedShares - sharesToUnstake, "Stored pool shares incorrect");
	}

	function testUnstakeWithPermit_Success_Nonce() public {
		// Call helper
		(address owner, , , uint256 nonce,,, ) = _setupAndUnstakeWithPermit(); // Adjusted destructuring (7 return values now)

		// Assertions
		assertEq(morpherStaking.nonces(owner), nonce + 1, "Nonce not incremented");
	}

	function testUnstakeWithPermit_Revert_LockupActive() public {
		vm.warp(1617094819); // Set consistent time
		address owner = testUserWithPK;
		uint256 stakeAmount = 300_000 * 1e18;

		// Initial stake
		vm.prank(owner);
		morpherToken.approve(address(morpherStaking), stakeAmount);
		vm.prank(owner);
		uint256 stakedShares = morpherStaking.stake(stakeAmount);

		// Don't warp time past lockup

		// Prepare unstake permit
		uint256 sharesToUnstake = stakedShares / 2;
		uint256 deadline = block.timestamp + 1 hours;
		uint256 nonce = morpherStaking.nonces(owner);

		// Hash struct
		bytes32 structHash = keccak256(abi.encode(UNSTAKE_TYPEHASH, sharesToUnstake, owner, nonce, deadline));
		// Calculate EIP712 digest
		bytes32 domainSeparator = morpherStaking.DOMAIN_SEPARATOR();
		bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
		// Sign
		(uint8 v, bytes32 r, bytes32 s) = vm.sign(TEST_USER_PK, digest);

		vm.expectRevert("MorpherStaking: cannot unstake before lockup expiration");
		morpherStaking.unstakeWithPermit(sharesToUnstake, owner, deadline, v, r, s);
	}

}
