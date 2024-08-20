// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "./BaseSetup.sol";
import "../contracts/MorpherStaking.sol";

contract MorkpherStakingTest is BaseSetup, MorpherStaking {

    uint public constant FIRST_RATE_TS = 1617094819;
    uint public constant SECOND_RATE_TS = 1644491427;
    // added for testing
    uint public constant THIRD_RATE_TS = 1670000000;

    function setUp() public override {
		super.setUp();
        morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(this));
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
        uint expectedShareValue = resultingPoolShares * morpherStaking.poolShareValue();
        (uint _value,) = morpherStaking.getStakeValue(user);
        assertEq(_value, expectedShareValue);
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
        assertEq(morpherToken.balanceOf(user), stake2Amount - resultingPoolSharesStake3 * morpherStaking.poolShareValue());
        assertEq(morpherToken.balanceOf(userB), stakeAmount);
        uint totalShares = resultingPoolSharesStake1 + resultingPoolSharesStake2 + resultingPoolSharesStake3;
        assertEq(morpherStaking.totalShares(), totalShares);

        // user
        (uint numPoolShares, uint lockedUntil) = morpherStaking.poolShares(user);
        assertEq(numPoolShares, resultingPoolSharesStake1 + resultingPoolSharesStake3);
        assertEq(lockedUntil, block.timestamp + morpherStaking.lockupPeriod());
        uint expectedShareValue = (resultingPoolSharesStake1 + resultingPoolSharesStake3) * morpherStaking.poolShareValue();
        (uint _value,) = morpherStaking.getStakeValue(user);
        assertEq(_value, expectedShareValue);

        // userB
        (uint numPoolShares2, uint lockedUntil2) = morpherStaking.poolShares(userB);
        assertEq(numPoolShares2, resultingPoolSharesStake2);
        assertEq(lockedUntil2, block.timestamp + morpherStaking.lockupPeriod() - 15 * 24 * 60 * 60);
        (uint _value2,) = morpherStaking.getStakeValue(userB);
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
        uint expectedAmount = morpherStaking.poolShareValue() * resultingPoolShares / 2;

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit Unstaked(user, expectedAmount, resultingPoolShares / 2);
        morpherStaking.unstake(resultingPoolShares / 2);

        assertEq(morpherToken.balanceOf(user), expectedAmount);
        assertEq(morpherStaking.totalShares(), resultingPoolShares / 2);
        (uint numPoolShares, uint lockedUntil) = morpherStaking.poolShares(user);
        assertEq(numPoolShares, resultingPoolShares / 2);
        assertEq(lockedUntil, block.timestamp);
        uint expectedShareValue = resultingPoolShares / 2 * morpherStaking.poolShareValue();
        (uint _value,) = morpherStaking.getStakeValue(user);
        assertEq(_value, expectedShareValue);
    }

    // INTEREST RATE -------------------------------------------------------------------------------

    function testGetTheCorrectRate() public {

        assertEq(morpherStaking.interestRate(), 0);

        vm.warp(FIRST_RATE_TS - 1);
        assertEq(morpherStaking.interestRate(), 0);
        vm.warp(FIRST_RATE_TS);
        assertEq(morpherStaking.interestRate(), 15000);
        vm.warp(FIRST_RATE_TS + 1);
        assertEq(morpherStaking.interestRate(), 15000);

        vm.warp(SECOND_RATE_TS - 1);
        assertEq(morpherStaking.interestRate(), 15000);
        vm.warp(SECOND_RATE_TS);
        assertEq(morpherStaking.interestRate(), 30000);
        vm.warp(SECOND_RATE_TS + 1);
        assertEq(morpherStaking.interestRate(), 30000);

        vm.warp(SECOND_RATE_TS + 1000000000000);
        assertEq(morpherStaking.interestRate(), 30000);
    }

    function testMultiRatePositionStart() public {
        morpherStaking.addInterestRate(45000, THIRD_RATE_TS);

        uint positionTimestamp = 1630000000;

        // at the start, should be the first rate
        uint expectedRate = 15000;
        vm.warp(positionTimestamp);
        assertEq(morpherStaking.getInterestRate(positionTimestamp), expectedRate);
        vm.warp(positionTimestamp + 100000);
        assertEq(morpherStaking.getInterestRate(positionTimestamp), expectedRate);

        uint _sum = 15000 * (SECOND_RATE_TS - positionTimestamp) + 30000 * (1660000000 - SECOND_RATE_TS);
        expectedRate = _sum / (1660000000 - positionTimestamp);
        vm.warp(1660000000);
        assertEq(morpherStaking.getInterestRate(positionTimestamp), expectedRate);

        _sum = 15000 * (SECOND_RATE_TS - positionTimestamp) + 30000 * (THIRD_RATE_TS - SECOND_RATE_TS) + 45000 * (1700000000 - THIRD_RATE_TS);
        expectedRate = _sum / (1700000000 - positionTimestamp);
        vm.warp(1700000000);
        assertEq(morpherStaking.getInterestRate(positionTimestamp), expectedRate);
    }

    function testMultiRatePositionMiddle() public {
        morpherStaking.addInterestRate(45000, THIRD_RATE_TS);

        uint positionTimestamp = 1660000000;

        uint expectedRate = 30000;
        vm.warp(positionTimestamp);
        assertEq(morpherStaking.getInterestRate(positionTimestamp), expectedRate);
        vm.warp(positionTimestamp + 100000);
        assertEq(morpherStaking.getInterestRate(positionTimestamp), expectedRate);

        uint _sum = 30000 * (THIRD_RATE_TS - positionTimestamp) + 45000 * (1700000000 - THIRD_RATE_TS);
        expectedRate = _sum / (1700000000 - positionTimestamp);
        vm.warp(1700000000);
        assertEq(morpherStaking.getInterestRate(positionTimestamp), expectedRate);
    }

    function testMultiRatePositionEnd() public {
        morpherStaking.addInterestRate(45000, THIRD_RATE_TS);

        uint positionTimestamp = 1700000000;

        uint expectedRate = 45000;
        vm.warp(positionTimestamp);
        assertEq(morpherStaking.getInterestRate(positionTimestamp), expectedRate);
        vm.warp(positionTimestamp + 100000);
        assertEq(morpherStaking.getInterestRate(positionTimestamp), expectedRate);
    }
}
