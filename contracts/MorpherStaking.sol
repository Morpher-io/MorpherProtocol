//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.15;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";

import "./MorpherState.sol";
import "./MorpherUserBlocking.sol";
import "./MorpherToken.sol";
import "./MorpherInterestRateManager.sol";

// ----------------------------------------------------------------------------------
// Staking Morpher Token generates interest
// The interest is set to 0.015% a day or ~5.475% in the first year
// Stakers will be able to vote on all ProtocolDecisions in MorpherGovernance (soon...)
// There is a lockup after staking or topping up (30 days) and a minimum stake (100k MPH)
// ----------------------------------------------------------------------------------

contract MorpherStaking is Initializable, ContextUpgradeable {
    using CountersUpgradeable for CountersUpgradeable.Counter;

    MorpherState public morpherState;

    uint256 constant PRECISION = 10**8;
    uint256 constant INTERVAL  = 1 days;

    bytes32 constant public ADMINISTRATOR_ROLE = keccak256("ADMINISTRATOR_ROLE");
    bytes32 constant public STAKINGADMIN_ROLE = keccak256("STAKINGADMIN_ROLE");

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


    
    bytes32 public constant _HASHED_NAME = keccak256("MorpherStaking");
    bytes32 public constant _HASHED_VERSION = keccak256("1");
    bytes32 public constant _TYPE_HASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    
    bytes32 public constant _STAKE_TYPEHASH = keccak256("Stake(uint256 amount,address owner,uint256 nonce,uint256 deadline)");
    bytes32 public constant _UNSTAKE_TYPEHASH = keccak256("Unstake(uint256 shares,address owner,uint256 nonce,uint256 deadline)");
    
    mapping(address => CountersUpgradeable.Counter) private _nonces;

	address private msgSenderOverride;

    // END STATE ----------------------------------------------------------------------------

    event SetLockupPeriod(uint256 newLockupPeriod);
    event SetMinimumStake(uint256 newMinimumStake);
    event InterestRateChanged(uint256 newInterestRate);
	event LinkState(address stateAddress);
    
    event PoolShareValueUpdated(uint256 indexed lastReward, uint256 poolShareValue);
    event StakingRewardsMinted(uint256 indexed lastReward, uint256 delta);
    event Staked(address indexed userAddress, uint256 indexed amount, uint256 poolShares, uint256 lockedUntil);
    event Unstaked(address indexed userAddress, uint256 indexed amount, uint256 poolShares);

    modifier onlyRole(bytes32 role) {
		require(
			MorpherAccessControl(morpherState.morpherAccessControlAddress()).hasRole(role, _msgSender()),
			"MorpherToken: Permission denied."
		);
		_;
	}
    
    modifier userNotBlocked {
        require(!MorpherUserBlocking(morpherState.morpherUserBlockingAddress()).userIsBlocked(_msgSender()), "MorpherStaking: User is blocked");
        _;
    }
    
    function initialize(address _morpherState) public initializer {
        ContextUpgradeable.__Context_init();

        morpherState = MorpherState(_morpherState);
        
        lastReward = block.timestamp;
        lockupPeriod = 30 days; // to prevent tactical staking and ensure smooth governance
        minimumStake = 10**23; // 100k MPH minimum
        stakingAddress = 0x2222222222222222222222222222222222222222;
        marketIdStakingMPH = 0x9a31fdde7a3b1444b1befb10735dcc3b72cbd9dd604d2ff45144352bf0f359a6; //STAKING_MPH
        poolShareValue = PRECISION;
        emit SetLockupPeriod(lockupPeriod);
        emit SetMinimumStake(minimumStake);
        // missing: transferOwnership to Governance once deployed
    }

    /**
	 * Overrides the msgSender Context to understand when a call by signature happened
	 */
	function _msgSender() internal view override returns (address) {
		if (msgSenderOverride != address(0)) {
			return msgSenderOverride;
		}

		return msg.sender;
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
        require(MorpherToken(morpherState.morpherTokenAddress()).balanceOf(_msgSender()) >= _amount, "MorpherStaking: insufficient MPH token balance");
        updatePoolShareValue();
        _poolShares = _amount / (poolShareValue);
        uint _numOfShares = poolShares[_msgSender()].numPoolShares;
        require(minimumStake <= (_numOfShares + _poolShares) * poolShareValue, "MorpherStaking: stake amount lower than minimum stake");
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

    // ----------------------------------------------------------------------------
    // Getter functions
    // ----------------------------------------------------------------------------

    /**
     * @dev "Consume a nonce": return the current value and increment.
     */
    function _useNonce(address owner) internal virtual returns (uint256 current) {
        CountersUpgradeable.Counter storage nonce = _nonces[owner];
        current = nonce.current();
        nonce.increment();
    }

    /**
     * @dev Returns the domain separator for the current chain.
     */
    function _domainSeparatorV4() internal view returns (bytes32) {
        return _buildDomainSeparator(_TYPE_HASH, _HASHED_NAME, _HASHED_VERSION);
    }

    function _buildDomainSeparator(
        bytes32 typeHash,
        bytes32 nameHash,
        bytes32 versionHash
    ) private view returns (bytes32) {
        return keccak256(abi.encode(typeHash, nameHash, versionHash, block.chainid, address(this)));
    }

    function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32) {
        return ECDSAUpgradeable.toTypedDataHash(_domainSeparatorV4(), structHash);
    }

    /**
     * @dev See {IERC20Permit-nonces}.
     */
    function nonces(address owner) public view virtual returns (uint256) {
        return _nonces[owner].current();
    }

    /**
     * @dev See {IERC20Permit-DOMAIN_SEPARATOR}.
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
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

        bytes32 structHash = keccak256(
            abi.encode(
                _STAKE_TYPEHASH,
                _amount,
                _owner,
                _useNonce(_owner),
                deadline
            )
        );

        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = ECDSAUpgradeable.recover(hash, v, r, s);
        require(signer == _owner, "MorpherStaking: invalid signature");
        msgSenderOverride = _owner;
        uint _poolShares = stake(_amount);
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

        bytes32 structHash = keccak256(
            abi.encode(
                _UNSTAKE_TYPEHASH,
                _shares,
                _owner,
                _useNonce(_owner),
                deadline
            )
        );

        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = ECDSAUpgradeable.recover(hash, v, r, s);
        require(signer == _owner, "MorpherStaking: invalid signature");

        msgSenderOverride = _owner;
        uint _amount = unstake(_shares);
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

    function getStakeValue(address _address) public view returns(uint256 _value, uint256 _lastUpdate) {
        // Only accurate if poolShareValue is up to date
        return (getStake(_address) * (poolShareValue), lastReward);
    }
}
