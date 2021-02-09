pragma solidity 0.5.16;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./MorpherState.sol";

// ----------------------------------------------------------------------------------
// ----------------------------------------------------------------------------------

contract MorpherStaking2 is Ownable {
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
    uint256 public lockupPeriod = 30 days;
    uint256 public minimumStake = 10**23; // 100k MPH minimum

    address public stakingAdmin;

// ----------------------------------------------------------------------------
// Events
// ----------------------------------------------------------------------------
    event Staked(address indexed userAddress, uint256 indexed amount, uint256 poolShares);
    event Unstaked(address indexed userAddress, uint256 indexed amount, uint256 poolShares);
    event SetInterestRate(uint256 newInterestRate);
    event PoolShareValueUpdated(uint256 indexed lastReward, uint256 poolShareValue);
    event StakingRewardsMinted(uint256 indexed lastReward, uint256 delta);
    
    constructor(address _stakingAdmin) public {
        setStakingAdmin(_stakingAdmin);
        lastReward = now;
        // transferOwnership
    }

    modifier onlyStakingAdmin {
        require(msg.sender == stakingAdmin, "MorpherStaking: can only be called by Staking Administrator.");
        _;
    }
    
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

    function mintStakingRewards() private {
        uint256 _targetBalance = poolShareValue.mul(totalShares);
        if (state.balanceOf(address(this)) < _targetBalance) {
            // If there are not enough token held by the contract, mint them
            uint256 _delta = _targetBalance.sub(state.balanceOf(address(this)));
            state.mint(address(this), _delta);
            emit StakingRewardsMinted(lastReward, _delta);
        }
    }

    function stake(uint256 _amount) public returns (uint256 _poolShares) {
        require(state.balanceOf(msg.sender) >= _amount, "MorpherStaking: insufficient MPH token balance");
        updatePoolShareValue();
        _poolShares = _amount.div(poolShareValue);
        state.transfer(msg.sender, address(this), _poolShares.mul(poolShareValue));
        totalShares = totalShares.add(_poolShares);
        poolShares[msg.sender] = poolShares[msg.sender].add(_poolShares);
        emit Staked(msg.sender, _amount, _poolShares);
        return _poolShares;
    }

    function unStake(uint256 _numOfShares) public {
        require(_numOfShares >= poolShares[msg.sender], "MorpherStaking: insufficient pool shares");
        updatePoolShareValue();
        poolShares[msg.sender] = poolShares[msg.sender].sub(_numOfShares);
        totalShares = totalShares.sub(_numOfShares);
        state.transfer(address(this), msg.sender, _numOfShares.mul(poolShareValue));
        emit Unstaked(msg.sender, _numOfShares.mul(poolShareValue), _numOfShares);
    }

    function getTotalPooledValue() public view returns (uint256 _totalPooled) {
        return poolShareValue.mul(totalShares);
    }

    function getTotalShares() public view returns (uint256 _totalShares) {
        return totalShares;
    }
// ----------------------------------------------------------------------------
// Administrative functions
// ----------------------------------------------------------------------------
    function setStakingAdmin(address _address) public onlyOwner {
        stakingAdmin = _address;
    }

    function setMorpherStateAddress(address _stateAddress) public onlyOwner {
        state = MorpherState(_stateAddress);
    }

    function setInterestRate(uint256 _interestRate) public onlyStakingAdmin {
        interestRate = _interestRate;
    }

    function setLockupPeriodRate(uint256 _lockupPeriod) public onlyStakingAdmin {
        lockupPeriod = _lockupPeriod;
    }
    
    function setMinimumStake(uint256 _minimumStake) public onlyStakingAdmin {
        minimumStake = _minimumStake;
    }

// ----------------------------------------------------------------------------
// Get staking amount by address
// ----------------------------------------------------------------------------
    function getStake(address _address) public view returns (uint256 _poolShares) {
        return poolShares[_address];
    }

    function getStakeValue(address _address) public view returns(uint256 _value, uint256 _lastUpdate) {
        return (poolShares[_address].mul(poolShareValue), lastReward);
    }
    
// ------------------------------------------------------------------------
// Don't accept ETH
// ------------------------------------------------------------------------
    function () external payable {
        revert("MorpherAirdrop: you can't deposit Ether here");
    }
}
