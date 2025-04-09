//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.20; // Update pragma if needed

// --- V5 Imports ---
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ContextUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/utils/ContextUpgradeable.sol";
import {EIP712Upgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/utils/cryptography/EIP712Upgradeable.sol"; // Added
import {NoncesUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/utils/NoncesUpgradeable.sol"; // Added
import {ECDSA} from "../lib/openzeppelin-contracts-5/contracts/utils/cryptography/ECDSA.sol"; // Added non-upgradeable ECDSA

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
	ContextUpgradeable, // Inherit UUPSUpgradeable and ContextUpgradeable
	EIP712Upgradeable, // Added
	NoncesUpgradeable // Added
{
	// using CountersUpgradeable for CountersUpgradeable.Counter; // Replaced by NoncesUpgradeable

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
	// --- EIP712 Domain details will be provided by overriding _EIP712Name and _EIP712Version ---
	// bytes32 private constant _HASHED_NAME = keccak256("MorpherStaking"); // Removed
	// bytes32 private constant _HASHED_VERSION = keccak256("1"); // Removed
	// --- _TYPE_HASH is handled by EIP712Upgradeable ---
	// bytes32 public constant _STAKE_TYPEHASH = ...; // Keep action-specific hashes public
	// bytes32 public constant _UNSTAKE_TYPEHASH = ...;
	// mapping(address => CountersUpgradeable.Counter) private _nonces; // Replaced by NoncesUpgradeable internal mapping
	address private msgSenderOverride; // Added for permit functions

	// --- Action-specific typehashes ---
	// solhint-disable-next-line var-name-mixedcase
	bytes32 public constant _STAKE_TYPEHASH =
		keccak256("Stake(uint256 amount,address owner,uint256 nonce,uint256 deadline)");
	// solhint-disable-next-line var-name-mixedcase
	bytes32 public constant _UNSTAKE_TYPEHASH =
		keccak256("Unstake(uint256 shares,address owner,uint256 nonce,uint256 deadline)");

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
		// Remove EIP712 params string memory _eip712Name,
		// Remove EIP712 params string memory _eip712Version
	) public initializer {
		__UUPSUpgradeable_init(); // Initialize UUPS
		__Context_init(); // Initialize Context
		// __EIP712_init(_eip712Name, _eip712Version); // Remove EIP712 init
		__Nonces_init(); // Initialize Nonces

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

	/**
	 * Overrides the msgSender Context to understand when a call by signature happened
	 */
	function _msgSender() internal view override(ContextUpgradeable) returns (address sender) {
		if (msgSenderOverride != address(0)) {
			return msgSenderOverride;
		}
		return super._msgSender();
	}

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

	// --- EIP712 Permit functions ---

	/**
	 * @dev See {IERC20Permit-nonces}. Returns the nonce used by NoncesUpgradeable.
	 */
	function nonces(address owner) public view virtual override(NoncesUpgradeable) returns (uint256) {
		return super.nonces(owner); // Use implementation from NoncesUpgradeable
	}

	/**
	 * @dev See {IERC20Permit-DOMAIN_SEPARATOR}. Returns the domain separator provided by EIP712Upgradeable.
	 */
	// solhint-disable-next-line func-name-mixedcase
	function DOMAIN_SEPARATOR() external view returns (bytes32) { // Remove override if not inheriting IERC20Permit
		return _domainSeparatorV4(); // Use implementation from EIP712Upgradeable
	}

	// --- Remove manual helpers, use library implementations ---
	// function _useNonce(...) ... // Provided by NoncesUpgradeable
	// function _domainSeparatorV4() ... // Provided by EIP712Upgradeable - We will override this
	// function _buildDomainSeparator(...) ... // Handled by EIP712Upgradeable - We don't need this if overriding _domainSeparatorV4
	// function _hashTypedDataV4(...) ... // Provided by EIP712Upgradeable - We still use this

    /**
     * @dev Overrides the EIP712 name calculation.
     */
    // solhint-disable-next-line func-name-mixedcase
    function _EIP712Name() internal pure override returns (string memory) {
        return "MorpherStaking";
    }

    /**
     * @dev Overrides the EIP712 version calculation.
     */
    // solhint-disable-next-line func-name-mixedcase
    function _EIP712Version() internal pure override returns (string memory) {
        return "1";
    }

	function stakeWithPermit(
		uint256 _amount,
		address _owner,
		uint256 deadline,
		uint8 v,
		bytes32 r,
		bytes32 s
	) public virtual returns (uint256) {
		require(block.timestamp <= deadline, "MorpherStaking: expired deadline");

		// Use _useNonce from NoncesUpgradeable
		uint256 currentNonce = _useNonce(_owner);

		bytes32 structHash = keccak256(
			abi.encode(
				_STAKE_TYPEHASH,
				_amount,
				_owner,
				currentNonce, // Use consumed nonce
				deadline
			)
		);

		// Use _hashTypedDataV4 from EIP712Upgradeable
		bytes32 digest = _hashTypedDataV4(structHash);

		// Use ECDSA library directly
		address signer = ECDSA.recover(digest, v, r, s);
		require(signer == _owner, "MorpherStaking: invalid signature");

		// Use msgSenderOverride for context
		msgSenderOverride = _owner;
		uint256 _poolShares = stake(_amount);
		msgSenderOverride = address(0);
		return _poolShares;
	}

	function unstakeWithPermit(
		uint256 _shares,
		address _owner,
		uint256 deadline,
		uint8 v,
		bytes32 r,
		bytes32 s
	) public virtual returns (uint256) {
		require(block.timestamp <= deadline, "MorpherStaking: expired deadline");

		// Use _useNonce from NoncesUpgradeable
		uint256 currentNonce = _useNonce(_owner);

		bytes32 structHash = keccak256(
			abi.encode(
				_UNSTAKE_TYPEHASH,
				_shares,
				_owner,
				currentNonce, // Use consumed nonce
				deadline
			)
		);

		// Use _hashTypedDataV4 from EIP712Upgradeable
		bytes32 digest = _hashTypedDataV4(structHash);

		// Use ECDSA library directly
		address signer = ECDSA.recover(digest, v, r, s);
		require(signer == _owner, "MorpherStaking: invalid signature");

		// Use msgSenderOverride for context
		msgSenderOverride = _owner;
		uint256 _amount = unstake(_shares);
		msgSenderOverride = address(0);
		return _amount;
	}

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
