//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.15;

import "./MorpherState.sol";
import "./MorpherAccessControl.sol";

// ----------------------------------------------------------------------------------
// Staking Morpher Token generates interest
// The interest is set to 0.015% a day or ~5.475% in the first year
// Stakers will be able to vote on all ProtocolDecisions in MorpherGovernance (soon...)
// There is a lockup after staking or topping up (30 days) and a minimum stake (100k MPH)
// ----------------------------------------------------------------------------------

contract MorpherInterestRateBase {
	MorpherState public morpherState;

	bytes32 public constant ADMINISTRATOR_ROLE = keccak256("ADMINISTRATOR_ROLE");

	//uint256 public interestRate = 15000; // 0.015% per day initially, diminishing returns over time
	struct InterestRate {
		uint256 validFrom;
		uint256 rate;
	}

	mapping(uint256 => InterestRate) public interestRates;
	uint256 public numInterestRates;

	// ----------------------------------------------------------------------------
	// Events
	// ----------------------------------------------------------------------------
	event InterestRateAdded(uint256 interestRate, uint256 validFromTimestamp);
	event InterestRateRateChanged(uint256 interstRateIndex, uint256 oldvalue, uint256 newValue);
	event InterestRateValidFromChanged(uint256 interstRateIndex, uint256 oldvalue, uint256 newValue);
	event LinkState(address stateAddress);

	modifier onlyRole(bytes32 role) {
		require(
			MorpherAccessControl(morpherState.morpherAccessControlAddress()).hasRole(role, msg.sender),
			"MorpherToken: Permission denied."
		);
		_;
	}

	function setMorpherStateAddress(address _stateAddress) public onlyRole(ADMINISTRATOR_ROLE) {
		morpherState = MorpherState(_stateAddress);
		emit LinkState(_stateAddress);
	}

	function setInterestRate(uint256 _interestRate) public onlyRole(ADMINISTRATOR_ROLE) {
		addInterestRate(_interestRate, block.timestamp);
	}

	/**
        fallback function in case the old tradeengine asks for the current interest rate
    */
	function interestRate() public view returns (uint256) {
		//start with the last one, as its most likely the last active one, no need to run through the whole map
		if (numInterestRates == 0) {
			return 0;
		}
		// i gets -1 before checking it to be >= 0 causing underflow of uint
		for (int256 i = int256(numInterestRates) - 1; i >= 0; i--) {
			if (interestRates[uint256(i)].validFrom <= block.timestamp) {
				return interestRates[uint256(i)].rate;
			}
		}
		return 0;
	}

	function addInterestRate(uint _rate, uint _validFrom) public onlyRole(ADMINISTRATOR_ROLE) {
		require(
			numInterestRates == 0 || interestRates[numInterestRates - 1].validFrom < _validFrom,
			"MorpherStaking: Interest Rate Valid From must be later than last interestRate"
		);
		require(_rate <= 100000000, "MorpherTradeEngine: Interest Rate cannot be larger than 100%");
		require(
			_validFrom - 365 days <= block.timestamp,
			"MorpherTradeEngine: Interest Rate cannot start more than 1 year into the future"
		);
		//omitting rate sanity checks here. It should always be smaller than 100% (100000000) but I'll leave that to the common sense of the admin.
		interestRates[numInterestRates].validFrom = _validFrom;
		interestRates[numInterestRates].rate = _rate;
		numInterestRates++;
		emit InterestRateAdded(_rate, _validFrom);
	}

	function changeInterestRateValue(uint256 _numInterestRate, uint256 _rate) public onlyRole(ADMINISTRATOR_ROLE) {
		emit InterestRateRateChanged(_numInterestRate, interestRates[_numInterestRate].rate, _rate);
		interestRates[_numInterestRate].rate = _rate;
	}

	function changeInterestRateValidFrom(
		uint256 _numInterestRate,
		uint256 _validFrom
	) public onlyRole(ADMINISTRATOR_ROLE) {
		emit InterestRateValidFromChanged(_numInterestRate, interestRates[_numInterestRate].validFrom, _validFrom);
		require(numInterestRates > _numInterestRate, "MorpherStaking: Interest Rate Does not exist!");
		require(
			(_numInterestRate == 0 &&
				numInterestRates - 1 > 0 &&
				interestRates[_numInterestRate + 1].validFrom > _validFrom) || //we change the first one and there exist more than one
				(_numInterestRate > 0 &&
					_numInterestRate == numInterestRates - 1 &&
					interestRates[_numInterestRate - 1].validFrom < _validFrom) || //we changed the last one
				(_numInterestRate > 0 &&
					_numInterestRate < numInterestRates - 1 &&
					interestRates[_numInterestRate - 1].validFrom < _validFrom &&
					interestRates[_numInterestRate + 1].validFrom > _validFrom),
			"MorpherStaking: validFrom cannot be smaller than previous Interest Rate or larger than next Interest Rate"
		);
		interestRates[_numInterestRate].validFrom = _validFrom;
	}

	function getInterestRate(uint256 _positionTimestamp) public view returns (uint256) {
		uint256 sumInterestRatesWeighted = 0;

		// in case we are before the first rate
		if (numInterestRates == 0 || interestRates[0].validFrom > block.timestamp) {
			return 0;
		}

		// avoid division by 0
		if (block.timestamp == _positionTimestamp) {
			return interestRate();
		}

		for (uint256 i = 0; i < numInterestRates; i++) {
			if (i == numInterestRates - 1 || interestRates[i + 1].validFrom > block.timestamp) {
				//reached last interest rate
				uint rateIncrease;
				if (_positionTimestamp > interestRates[i].validFrom) {
					rateIncrease = (interestRates[i].rate * (block.timestamp - _positionTimestamp));
				} else {
					rateIncrease = (interestRates[i].rate * (block.timestamp - interestRates[i].validFrom));
				}
				sumInterestRatesWeighted = sumInterestRatesWeighted + rateIncrease;
				break; //in case there are more in the future
			} else {
				//only take interest rates after the position was created
				if (interestRates[i + 1].validFrom > _positionTimestamp) {
					uint rateIncrease;
					if (_positionTimestamp > interestRates[i].validFrom) {
						rateIncrease = (interestRates[i].rate * (interestRates[i + 1].validFrom - _positionTimestamp));
					} else {
						rateIncrease = (interestRates[i].rate *
							(interestRates[i + 1].validFrom - interestRates[i].validFrom));
					}
					sumInterestRatesWeighted = sumInterestRatesWeighted + rateIncrease;
				}
			}
		}
		uint interestRateInternal = sumInterestRatesWeighted / (block.timestamp - _positionTimestamp);
		return interestRateInternal;
	}
}
