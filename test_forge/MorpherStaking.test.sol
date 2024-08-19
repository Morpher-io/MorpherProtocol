// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "./BaseSetup.sol";
import "../contracts/MorpherStaking.sol";

contract MorkpherStakingTest is BaseSetup, MorpherStaking {

	function setUp() public override {
		super.setUp();
	}

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
}
