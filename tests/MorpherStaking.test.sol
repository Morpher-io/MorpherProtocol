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

	function setUp() public override {
		super.setUp();
		morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(this));
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
		uint256 interestRate = morpherInterestRateManager.interestRate();
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
		uint256 interestRate = morpherInterestRateManager.interestRate();
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
}
