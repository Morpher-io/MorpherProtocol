// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "./BaseSetup.sol";

// using staking as one of the inheriting contracts
contract MorkpherInterestRateManagerTest is BaseSetup {

	bytes32 public constant ADMINISTRATOR_ROLE = keccak256("ADMINISTRATOR_ROLE");

	event InterestRateAdded(uint256 interestRate, uint256 validFromTimestamp);
	event InterestRateRateChanged(uint256 interstRateIndex, uint256 oldvalue, uint256 newValue);
	event InterestRateValidFromChanged(uint256 interstRateIndex, uint256 oldvalue, uint256 newValue);
	event LinkState(address stateAddress);

	uint public constant FIRST_RATE_TS = 1617094819;
	uint public constant SECOND_RATE_TS = 1644491427;
	// added for testing
	uint public constant THIRD_RATE_TS = 1670000000;

	function setUp() public override {
		super.setUp();
		morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(this));
		morpherAccessControl.grantRole(ADMINISTRATOR_ROLE, address(this));
	}

	function testShouldSetState() public {
		vm.expectEmit(true, true, true, true);
		emit LinkState(address(0x3333));
		morpherInterestRateManager.setMorpherStateAddress(address(0x3333));
	}

	function testShouldSetInterestRate() public {
		vm.warp(THIRD_RATE_TS);
		vm.expectEmit(true, true, true, true);
		emit InterestRateAdded(40000, THIRD_RATE_TS);
		morpherInterestRateManager.setInterestRate(40000);
	}

	function testGetTheCorrectRate() public {
		assertEq(morpherInterestRateManager.interestRate(), 0);

		vm.warp(FIRST_RATE_TS - 1);
		assertEq(morpherInterestRateManager.interestRate(), 0);
		vm.warp(FIRST_RATE_TS);
		assertEq(morpherInterestRateManager.interestRate(), 15000);
		vm.warp(FIRST_RATE_TS + 1);
		assertEq(morpherInterestRateManager.interestRate(), 15000);

		vm.warp(SECOND_RATE_TS - 1);
		assertEq(morpherInterestRateManager.interestRate(), 15000);
		vm.warp(SECOND_RATE_TS);
		assertEq(morpherInterestRateManager.interestRate(), 30000);
		vm.warp(SECOND_RATE_TS + 1);
		assertEq(morpherInterestRateManager.interestRate(), 30000);

		vm.warp(SECOND_RATE_TS + 1000000000000);
		assertEq(morpherInterestRateManager.interestRate(), 30000);
	}

	function testMultiRatePositionStart() public {
		vm.warp(SECOND_RATE_TS); // just to add the third rate
		morpherInterestRateManager.addInterestRate(45000, THIRD_RATE_TS);

		uint positionTimestamp = 1630000000;

		// at the start, should be the first rate
		uint expectedRate = 15000;
		vm.warp(positionTimestamp);
		assertEq(morpherInterestRateManager.getInterestRate(positionTimestamp), expectedRate);
		vm.warp(positionTimestamp + 100000);
		assertEq(morpherInterestRateManager.getInterestRate(positionTimestamp), expectedRate);

		uint _sum = 15000 * (SECOND_RATE_TS - positionTimestamp) + 30000 * (1660000000 - SECOND_RATE_TS);
		expectedRate = _sum / (1660000000 - positionTimestamp);
		vm.warp(1660000000);
		assertEq(morpherInterestRateManager.getInterestRate(positionTimestamp), expectedRate);

		_sum =
			15000 *
			(SECOND_RATE_TS - positionTimestamp) +
			30000 *
			(THIRD_RATE_TS - SECOND_RATE_TS) +
			45000 *
			(1700000000 - THIRD_RATE_TS);
		expectedRate = _sum / (1700000000 - positionTimestamp);
		vm.warp(1700000000);
		assertEq(morpherInterestRateManager.getInterestRate(positionTimestamp), expectedRate);
	}

	function testMultiRatePositionMiddle() public {
		vm.warp(SECOND_RATE_TS); // just to add the third rate
		morpherInterestRateManager.addInterestRate(45000, THIRD_RATE_TS);

		uint positionTimestamp = 1660000000;

		uint expectedRate = 30000;
		vm.warp(positionTimestamp);
		assertEq(morpherInterestRateManager.getInterestRate(positionTimestamp), expectedRate);
		vm.warp(positionTimestamp + 100000);
		assertEq(morpherInterestRateManager.getInterestRate(positionTimestamp), expectedRate);

		uint _sum = 30000 * (THIRD_RATE_TS - positionTimestamp) + 45000 * (1700000000 - THIRD_RATE_TS);
		expectedRate = _sum / (1700000000 - positionTimestamp);
		vm.warp(1700000000);
		assertEq(morpherInterestRateManager.getInterestRate(positionTimestamp), expectedRate);
	}

	function testMultiRatePositionEnd() public {
		vm.warp(SECOND_RATE_TS); // just to add the third rate
		morpherInterestRateManager.addInterestRate(45000, THIRD_RATE_TS);

		uint positionTimestamp = 1700000000;

		uint expectedRate = 45000;
		vm.warp(positionTimestamp);
		assertEq(morpherInterestRateManager.getInterestRate(positionTimestamp), expectedRate);
		vm.warp(positionTimestamp + 100000);
		assertEq(morpherInterestRateManager.getInterestRate(positionTimestamp), expectedRate);
	}

	function testChangeRateValue() public {
		vm.expectEmit(true, true, true, true);
		emit InterestRateRateChanged(1, 30000, 35000);
		morpherInterestRateManager.changeInterestRateValue(1, 35000);
		(uint validFrom, uint rate) = morpherInterestRateManager.interestRates(0);
		assertEq(rate, 15000);
		(validFrom, rate) = morpherInterestRateManager.interestRates(1);
		assertEq(rate, 35000);
		(validFrom, rate) = morpherInterestRateManager.interestRates(2);
		assertEq(rate, 0);
	}

	function testChangeRateTimestamp() public {
		vm.expectRevert();
		morpherInterestRateManager.changeInterestRateValidFrom(2, THIRD_RATE_TS);

		// first case
		vm.expectRevert();
		morpherInterestRateManager.changeInterestRateValidFrom(0, SECOND_RATE_TS);
		vm.expectEmit(true, true, true, true);
		emit InterestRateValidFromChanged(0, FIRST_RATE_TS, SECOND_RATE_TS - 1);
		morpherInterestRateManager.changeInterestRateValidFrom(0, SECOND_RATE_TS - 1);
		(uint validFrom, uint rate) = morpherInterestRateManager.interestRates(0);
		assertEq(rate, 15000);
		assertEq(validFrom, SECOND_RATE_TS - 1);
		morpherInterestRateManager.changeInterestRateValidFrom(0, FIRST_RATE_TS);

		// second case
		vm.expectRevert();
		morpherInterestRateManager.changeInterestRateValidFrom(1, FIRST_RATE_TS);
		vm.expectEmit(true, true, true, true);
		emit InterestRateValidFromChanged(1, SECOND_RATE_TS, FIRST_RATE_TS + 1);
		morpherInterestRateManager.changeInterestRateValidFrom(1, FIRST_RATE_TS + 1);
		(validFrom, rate) = morpherInterestRateManager.interestRates(1);
		assertEq(rate, 30000);
		assertEq(validFrom, FIRST_RATE_TS + 1);
		morpherInterestRateManager.changeInterestRateValidFrom(1, SECOND_RATE_TS);

		// third case
		vm.warp(SECOND_RATE_TS);
		morpherInterestRateManager.addInterestRate(45000, THIRD_RATE_TS);
		vm.expectRevert();
		morpherInterestRateManager.changeInterestRateValidFrom(1, THIRD_RATE_TS);
		vm.expectRevert();
		morpherInterestRateManager.changeInterestRateValidFrom(1, FIRST_RATE_TS);
		vm.expectEmit(true, true, true, true);
		emit InterestRateValidFromChanged(1, SECOND_RATE_TS, FIRST_RATE_TS + 1);
		morpherInterestRateManager.changeInterestRateValidFrom(1, FIRST_RATE_TS + 1);
		(validFrom, rate) = morpherInterestRateManager.interestRates(1);
		assertEq(rate, 30000);
		assertEq(validFrom, FIRST_RATE_TS + 1);
		vm.expectEmit(true, true, true, true);
		emit InterestRateValidFromChanged(1, FIRST_RATE_TS + 1, THIRD_RATE_TS - 1);
		morpherInterestRateManager.changeInterestRateValidFrom(1, THIRD_RATE_TS - 1);
		(validFrom, rate) = morpherInterestRateManager.interestRates(1);
		assertEq(rate, 30000);
		assertEq(validFrom, THIRD_RATE_TS - 1);
	}
}
