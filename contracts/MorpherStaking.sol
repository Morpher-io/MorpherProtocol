pragma solidity 0.5.16;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./MorpherState.sol";

// ----------------------------------------------------------------------------------
// Staking Morpher Token generates interest
// The interest is set to 0.015% a day or ~5.475% in the first year
// Stakers will be able to vote on all ProtocolDecisions in MorpherGovernance (soon...)
// There is a lockup after staking or topping up (30 days) and a minimum stake (100k MPH)
// ----------------------------------------------------------------------------------

contract MorpherStaking is Ownable {
    using SafeMath for uint256;
    MorpherState state;

    uint256 constant PRECISION = 10**8;
    uint256 constant INTERVAL  = 1 days;

    mapping(address => uint256) private poolShares;
    mapping(address => uint256) private lockup;

    uint256 public poolShareValue = PRECISION;
    uint256 public lastReward;
    uint256 public totalShares;
    uint256 public interestRate = 15000; // 0.015% per day initially, diminishing returns over time
    uint256 public lockupPeriod = 30 days; // to prevent tactical staking and ensure smooth governance
    uint256 public minimumStake = 10**23; // 100k MPH minimum

    address public stakingAdmin;

// ----------------------------------------------------------------------------
// Events
// ----------------------------------------------------------------------------
    event SetInterestRate(uint256 newInterestRate);
    event SetLockupPeriod(uint256 newLockupPeriod);
    event SetMinimumStake(uint256 newMinimumStake);
    event LinkState(address stateAddress);
    event SetStakingAdmin(address stakingAdmin);
    
    event PoolShareValueUpdated(uint256 indexed lastReward, uint256 poolShareValue);
    event StakingRewardsMinted(uint256 indexed lastReward, uint256 delta);
    event Staked(address indexed userAddress, uint256 indexed amount, uint256 poolShares);
    event Unstaked(address indexed userAddress, uint256 indexed amount, uint256 poolShares);
    
    modifier onlyStakingAdmin {
        require(msg.sender == stakingAdmin, "MorpherStaking: can only be called by Staking Administrator.");
        _;
    }
    
    constructor(address _morpherState, address _stakingAdmin) public {
        setStakingAdmin(_stakingAdmin);
        setMorpherStateAddress(_morpherState);
        emit SetLockupPeriod(lockupPeriod);
        emit SetMinimumStake(minimumStake);
        emit SetInterestRate(interestRate);
        lastReward = now;
        // missing: transferOwnership to Governance once deployed
    }

// ----------------------------------------------------------------------------
// updatePoolShareValue
// Updates the value of the Pool Shares and returns the new value.
// Staking rewards are linear, there is no compound interest.
// ----------------------------------------------------------------------------
    
    function updatePoolShareValue() public returns (uint256 _newPoolShareValue) {
        if (now >= lastReward.add(INTERVAL)) {
            uint256 _numOfIntervals = now.sub(lastReward).div(INTERVAL);
            poolShareValue = poolShareValue.add(_numOfIntervals.mul(interestRate));
            lastReward = lastReward.add(_numOfIntervals.mul(INTERVAL));
            emit PoolShareValueUpdated(lastReward, poolShareValue);
        }
        mintStakingRewards();
        return poolShareValue;        
    }

// ----------------------------------------------------------------------------
// Staking rewards are minted if necessary
// ----------------------------------------------------------------------------

    function mintStakingRewards() private {
        uint256 _targetBalance = poolShareValue.mul(totalShares);
        if (state.balanceOf(address(this)) < _targetBalance) {
            // If there are not enough token held by the contract, mint them
            uint256 _delta = _targetBalance.sub(state.balanceOf(address(this)));
            state.mint(address(this), _delta);
            emit StakingRewardsMinted(lastReward, _delta);
        }
    }

// ----------------------------------------------------------------------------
// stake(uint256 _amount)
// User specifies an amount they intend to stake. Pool Shares are issued accordingly
// and the _amount is transferred to the staking contract
// ----------------------------------------------------------------------------

    function stake(uint256 _amount) public returns (uint256 _poolShares) {
        require(state.balanceOf(msg.sender) >= _amount, "MorpherStaking: insufficient MPH token balance");
        updatePoolShareValue();
        _poolShares = _amount.div(poolShareValue);
        require(minimumStake >= poolShares[msg.sender].add(_poolShares).mul(poolShareValue), "MorpherStaking: stake amount lower than minimum stake");
        state.transfer(msg.sender, address(this), _poolShares.mul(poolShareValue));
        totalShares = totalShares.add(_poolShares);
        poolShares[msg.sender] = poolShares[msg.sender].add(_poolShares);
        lockup[msg.sender] = now;
        emit Staked(msg.sender, _amount, _poolShares);
        return _poolShares;
    }

// ----------------------------------------------------------------------------
// unStake(uint256 _amount)
// User specifies number of Pool Shares they want to unstake. 
// Pool Shares get deleted and the user receives their MPH plus interest
// ----------------------------------------------------------------------------

    function unStake(uint256 _numOfShares) public returns (uint256 _amount) {
        require(_numOfShares >= poolShares[msg.sender], "MorpherStaking: insufficient pool shares");
        require(now >= lockup[msg.sender].add(lockupPeriod), "MorpherStaking: cannot unstake before lockup expiration");
        updatePoolShareValue();
        poolShares[msg.sender] = poolShares[msg.sender].sub(_numOfShares);
        totalShares = totalShares.sub(_numOfShares);
        _amount = _numOfShares.mul(poolShareValue);
        state.transfer(address(this), msg.sender, _amount);
        emit Unstaked(msg.sender, _amount, _numOfShares);
        return _amount;
    }

// ----------------------------------------------------------------------------
// Administrative functions
// ----------------------------------------------------------------------------

    function setStakingAdmin(address _address) public onlyOwner {
        stakingAdmin = _address;
        emit SetStakingAdmin(_address);
    }

    function setMorpherStateAddress(address _stateAddress) public onlyOwner {
        state = MorpherState(_stateAddress);
        emit LinkState(_stateAddress);
    }

    function setInterestRate(uint256 _interestRate) public onlyStakingAdmin {
        interestRate = _interestRate;
        emit SetInterestRate(_interestRate);
    }

    function setLockupPeriodRate(uint256 _lockupPeriod) public onlyStakingAdmin {
        lockupPeriod = _lockupPeriod;
        emit SetLockupPeriod(_lockupPeriod);
    }
    
    function setMinimumStake(uint256 _minimumStake) public onlyStakingAdmin {
        minimumStake = _minimumStake;
        emit SetMinimumStake(_minimumStake);
    }

// ----------------------------------------------------------------------------
// Getter functions
// ----------------------------------------------------------------------------

    function getTotalPooledValue() public view returns (uint256 _totalPooled) {
        // Only accurate if poolShareValue is up to date
        return poolShareValue.mul(totalShares);
    }

    function getTotalShares() public view returns (uint256 _totalShares) {
        return totalShares;
    }

    function getStake(address _address) public view returns (uint256 _poolShares) {
        return poolShares[_address];
    }

    function getStakeValue(address _address) public view returns(uint256 _value, uint256 _lastUpdate) {
        // Only accurate if poolShareValue is up to date
        return (poolShares[_address].mul(poolShareValue), lastReward);
    }
    
// ------------------------------------------------------------------------
// Don't accept ETH
// ------------------------------------------------------------------------

    function () external payable {
        revert("MorpherStaking: you can't deposit Ether here");
    }
}
