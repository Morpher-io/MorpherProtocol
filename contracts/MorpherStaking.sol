//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.20; // Update pragma if needed

// --- V5 Imports ---
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ContextUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/utils/ContextUpgradeable.sol"; // Add Context back
// Remove EIP712Upgradeable, ECDSAUpgradeable, CountersUpgradeable if only used for permit
// import {CountersUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/utils/CountersUpgradeable.sol";

import "./MorpherState.sol"; // Use adapted v5 interface
import "./MorpherUserBlocking.sol"; // Use adapted v5 interface
import "./MorpherToken.sol";
import "./MorpherInterestRateManager.sol";

// ----------------------------------------------------------------------------------
// Staking Morpher Token generates interest
// The interest is set to 0.015% a day or ~5.475% in the first year
// Stakers will be able to vote on all ProtocolDecisions in MorpherGovernance (soon...)
// There is a lockup after staking or topping up (30 days) and a minimum stake (100k MPH)
// ----------------------------------------------------------------------------------

contract MorpherStaking is
	UUPSUpgradeable,
	ContextUpgradeable // Inherit UUPSUpgradeable and ContextUpgradeable
{
	// using CountersUpgradeable for CountersUpgradeable.Counter; // Keep only if Counters are used elsewhere

	MorpherState public morpherState;

	uint256 constant PRECISION = 10 ** 8;
	uint256 constant INTERVAL = 1 days;

	bytes32 public constant ADMINISTRATOR_ROLE = keccak256("ADMINISTRATOR_ROLE");
	bytes32 public constant STAKINGADMIN_ROLE = keccak256("STAKINGADMIN_ROLE");

	//mapping(address => uint256) private poolShares;
	//mapping(address => uint256) private lockup;

	uint256 public poolShareValue;
	uint256 public lastReward;
	uint256 public totalShares;

	struct InterestRate {
		uint256 validFrom;
		uint256 rate;
	}

	mapping(uint256 => InterestRate) private _OLDinterestRates; //deprecated, not in use/proxy
	uint256 public interestRate; // Daily interest rate with PRECISION decimals, reuse/changed from numInterestRates
	uint256 public lockupPeriod; // to prevent tactical staking and ensure smooth governance
	uint256 public minimumStake; // 100k MPH minimum

	address public stakingAddress;
	bytes32 public marketIdStakingMPH; //STAKING_MPH

	struct PoolShares {
		uint256 numPoolShares;
		uint256 lockedUntil;
	}
	mapping(address => PoolShares) public poolShares;

	// --- Remove manual EIP712 Permit state variables ---
	// bytes32 public constant _HASHED_NAME = ...;
	// bytes32 public constant _HASHED_VERSION = ...;
	// bytes32 public constant _TYPE_HASH = ...;
	// bytes32 public constant _STAKE_TYPEHASH = ...;
	// bytes32 public constant _UNSTAKE_TYPEHASH = ...;
	// mapping(address => CountersUpgradeable.Counter) private _nonces;
	// address private msgSenderOverride;

	// END STATE ----------------------------------------------------------------------------

	event SetLockupPeriod(uint256 newLockupPeriod);
	event SetMinimumStake(uint256 newMinimumStake);
	event InterestRateChanged(uint256 newInterestRate);
	event LinkState(address stateAddress);

	event PoolShareValueUpdated(uint256 indexed lastReward, uint256 poolShareValue);
	event StakingRewardsMinted(uint256 indexed lastReward, uint256 delta);
	event Staked(address indexed userAddress, uint256 indexed amount, uint256 poolShares, uint256 lockedUntil);
	event StakeMigrated(address indexed userAddress, uint256 numPoolShares, uint256 lockedUntil); // Added Event
	event Unstaked(address indexed userAddress, uint256 indexed amount, uint256 poolShares);

	modifier onlyRole(bytes32 role) {
		require(
			MorpherAccessControl(morpherState.morpherAccessControlAddress()).hasRole(role, _msgSender()),
			"MorpherToken: Permission denied."
		);
		_;
	}

	modifier userNotBlocked() {
		require(
			!MorpherUserBlocking(morpherState.morpherUserBlockingAddress()).userIsBlocked(_msgSender()),
			"MorpherStaking: User is blocked"
		);
		_;
	}

	// --- Updated Initializer for Migration ---
	// Add _initialPoolShareValue and _initialLastReward parameters
	function initialize(
		address _morpherStateAddress,
		uint256 _initialPoolShareValue,
		uint256 _initialLastReward
	) public initializer {
		__UUPSUpgradeable_init(); // Initialize UUPS
		__Context_init(); // Initialize Context

		morpherState = MorpherState(_morpherStateAddress);
		lastReward = _initialLastReward; // Set lastReward from parameter
		lockupPeriod = 30 days; // to prevent tactical staking and ensure smooth governance
		minimumStake = 10 ** 23; // 100k MPH minimum
		stakingAddress = 0x2222222222222222222222222222222222222222;
		marketIdStakingMPH = 0x9a31fdde7a3b1444b1befb10735dcc3b72cbd9dd604d2ff45144352bf0f359a6; //STAKING_MPH
		poolShareValue = _initialPoolShareValue; // Set poolShareValue from parameter
		emit SetLockupPeriod(lockupPeriod);
		emit SetMinimumStake(minimumStake);
		// missing: transferOwnership to Governance once deployed
	}

	// --- Implement _authorizeUpgrade ---
	function _authorizeUpgrade(address /** unsed */) internal view override {
		address accessControlAddress = morpherState.morpherAccessControlAddress();
		require(accessControlAddress != address(0), "MorpherStaking: AccessControl not set in State");
		// Check if the sender has the PROXYUPDATER_ROLE defined in MorpherAccessControl
		require(
			MorpherAccessControl(accessControlAddress).hasRole(
				MorpherAccessControl(accessControlAddress).PROXYUPDATER_ROLE(), // Get role hash from AC
				msg.sender // Use msg.sender directly
			),
			"MorpherStaking: Caller is not the proxy updater"
		);
	}

	// --- Remove _msgSender override ---
	// function _msgSender() ...

	// ----------------------------------------------------------------------------
	// updatePoolShareValue
	// Updates the value of the Pool Shares and returns the new value.
	// Staking rewards are linear, there is no compound interest.
	// ----------------------------------------------------------------------------

	function updatePoolShareValue() public returns (uint256 _newPoolShareValue) {
		if (block.timestamp >= lastReward + INTERVAL) {
			uint256 _numOfIntervals = uint256(block.timestamp - lastReward) / INTERVAL;
			poolShareValue = poolShareValue + (_numOfIntervals * interestRate);
			lastReward = lastReward + (_numOfIntervals * (INTERVAL));
			emit PoolShareValueUpdated(lastReward, poolShareValue);
		}
		//mintStakingRewards(); //burning/minting does not influence this
		return poolShareValue;
	}

	// ----------------------------------------------------------------------------
	// Staking rewards are minted if necessary
	// ----------------------------------------------------------------------------

	// function mintStakingRewards() private {
	//     uint256 _targetBalance = poolShareValue * (totalShares);
	//     if (MorpherToken(state.morpherTokenAddress()).balanceOf(stakingAddress) < _targetBalance) {
	//         // If there are not enough token held by the contract, mint them
	//         uint256 _delta = _targetBalance - (MorpherToken(state.morpherTokenAddress()).balanceOf(stakingAddress));
	//         MorpherToken(state.morpherTokenAddress()).mint(stakingAddress, _delta);
	//         emit StakingRewardsMinted(lastReward, _delta);
	//     }
	// }

	// ----------------------------------------------------------------------------
	// stake(uint256 _amount)
	// User specifies an amount they intend to stake. Pool Shares are issued accordingly
	// and the _amount is transferred to the staking contract
	// ----------------------------------------------------------------------------

	function stake(uint256 _amount) public virtual userNotBlocked returns (uint256 _poolShares) {
		require(
			MorpherToken(morpherState.morpherTokenAddress()).getTradeableBalanceOf(_msgSender()) >= _amount,
			"MorpherStaking: insufficient MPH token balance"
		);
		updatePoolShareValue();
		_poolShares = _amount / (poolShareValue);
		uint _numOfShares = poolShares[_msgSender()].numPoolShares;
		require(
			minimumStake <= (_numOfShares + _poolShares) * poolShareValue,
			"MorpherStaking: stake amount lower than minimum stake"
		);
		MorpherToken(morpherState.morpherTokenAddress()).burn(_msgSender(), _poolShares * (poolShareValue));
		totalShares = totalShares + (_poolShares);
		poolShares[_msgSender()].numPoolShares = _numOfShares + _poolShares;
		poolShares[_msgSender()].lockedUntil = block.timestamp + lockupPeriod;
		emit Staked(_msgSender(), _amount, _poolShares, block.timestamp + (lockupPeriod));
		return _poolShares;
	}

	// ----------------------------------------------------------------------------
	// unstake(uint256 _amount)
	// User specifies number of Pool Shares they want to unstake.
	// Pool Shares get deleted and the user receives their MPH plus interest
	// ----------------------------------------------------------------------------

	function unstake(uint256 _numOfShares) public virtual userNotBlocked returns (uint256 _amount) {
		uint256 _numOfExistingShares = poolShares[_msgSender()].numPoolShares;
		require(_numOfShares <= _numOfExistingShares, "MorpherStaking: insufficient pool shares");

		uint256 lockedInUntil = poolShares[_msgSender()].lockedUntil;
		require(block.timestamp >= lockedInUntil, "MorpherStaking: cannot unstake before lockup expiration");
		updatePoolShareValue();
		poolShares[_msgSender()].numPoolShares = poolShares[_msgSender()].numPoolShares - _numOfShares;
		totalShares = totalShares - _numOfShares;
		_amount = _numOfShares * poolShareValue;
		MorpherToken(morpherState.morpherTokenAddress()).mint(_msgSender(), _amount);
		emit Unstaked(_msgSender(), _amount, _numOfShares);
		return _amount;
	}

	function setMorpherStateAddress(address _stateAddress) public onlyRole(ADMINISTRATOR_ROLE) {
		morpherState = MorpherState(_stateAddress);
		emit LinkState(_stateAddress);
	}

	function setLockupPeriodRate(uint256 _lockupPeriod) public onlyRole(STAKINGADMIN_ROLE) {
		lockupPeriod = _lockupPeriod;
		emit SetLockupPeriod(_lockupPeriod);
	}

	function setMinimumStake(uint256 _minimumStake) public onlyRole(STAKINGADMIN_ROLE) {
		minimumStake = _minimumStake;
		emit SetMinimumStake(_minimumStake);
	}

	function setInterestRate(uint256 _interestRate) public onlyRole(STAKINGADMIN_ROLE) {
		require(_interestRate <= 100000000, "MorpherStaking: Interest Rate cannot be larger than 100%");
		interestRate = _interestRate;
		emit InterestRateChanged(_interestRate);
	}

	/**
	 * @notice Sets the staking data for a user during migration. Only callable by STAKINGADMIN_ROLE.
	 * @dev This function bypasses standard staking logic like minimum stake and lockup period creation.
	 * @param _user The address of the user whose stake is being migrated.
	 * @param _numPoolShares The number of pool shares the user had.
	 * @param _lockedUntil The timestamp until which the migrated stake remains locked.
	 */
	function setMigratedStake(address _user, uint256 _numPoolShares, uint256 _lockedUntil)
		public
		onlyRole(STAKINGADMIN_ROLE)
	{
		require(_user != address(0), "MorpherStaking: User address cannot be zero");
		// Note: This potentially overwrites existing stake data for the user. Assumed intended for migration.
		poolShares[_user] = PoolShares(_numPoolShares, _lockedUntil);
		totalShares += _numPoolShares; // Crucial: Update totalShares
		emit StakeMigrated(_user, _numPoolShares, _lockedUntil);
	}

	// ----------------------------------------------------------------------------
	// Getter functions
	// ----------------------------------------------------------------------------

	// --- Remove manual EIP712 Permit functions ---
	// function _useNonce(...) ...
	// function _domainSeparatorV4() ...
	// function _buildDomainSeparator(...) ...
	// function _hashTypedDataV4(...) ...
	// function nonces(...) ...
	// function DOMAIN_SEPARATOR() ...
	// function stakeWithPermit(...) ...
	// function unstakeWithPermit(...) ...

	function getTotalPooledValue() public view returns (uint256 _totalPooled) {
		// Only accurate if poolShareValue is up to date
		return poolShareValue * (totalShares);
	}

	function getStake(address _address) public view returns (uint256 _poolShares) {
		return poolShares[_address].numPoolShares;
	}

	function getStakeValue(address _address) public view returns (uint256 _value, uint256 _lastUpdate) {
		// Only accurate if poolShareValue is up to date
		return (getStake(_address) * (poolShareValue), lastReward);
	}
}
