// SPDX-License-Identifier: GPLv3
pragma solidity 0.8.19;

// ----------------------------------------------------------------------------------
// MorpherStakingUnstakeOnly
// A minimal staking contract deployed during sidechain sunset that allows
// administrators to force-unstake users' stakes. This bypasses the lockup period
// to ensure all users can receive their tokens during the migration.
//
// This contract interacts with the old MorpherState on the sidechain.
// ----------------------------------------------------------------------------------

interface IMorpherStateOld {
    function setPosition(
        address _address,
        bytes32 _marketId,
        uint256 _timeStamp,
        uint256 _longShares,
        uint256 _shortShares,
        uint256 _meanEntryPrice,
        uint256 _meanEntrySpread,
        uint256 _meanEntryLeverage,
        uint256 _liquidationPrice
    ) external;

    function getPosition(
        address _address,
        bytes32 _marketId
    ) external view returns (
        uint256 _longShares,
        uint256 _shortShares,
        uint256 _meanEntryPrice,
        uint256 _meanEntrySpread,
        uint256 _meanEntryLeverage,
        uint256 _liquidationPrice
    );

    function getLastUpdated(address _address, bytes32 _marketId) external view returns (uint256 _lastUpdated);

    function transfer(address _from, address _to, uint256 _token) external;

    function balanceOf(address _tokenOwner) external view returns (uint256 balance);

    function mint(address _address, uint256 _token) external;

    function burn(address _address, uint256 _token) external;

    function getAdministrator() external view returns (address);
}

interface IMorpherStakingOld {
    function poolShareValue() external view returns (uint256);
    function lastReward() external view returns (uint256);
    function totalShares() external view returns (uint256);
    function interestRate() external view returns (uint256);
}

contract MorpherStakingUnstakeOnly {
    IMorpherStateOld public immutable morpherState;
    IMorpherStakingOld public immutable oldStaking;

    uint256 constant PRECISION = 10**8;
    uint256 constant INTERVAL = 1 days;

    // Staking storage address (where staked tokens are held)
    address public constant STAKING_ADDRESS = 0x2222222222222222222222222222222222222222;
    // Market ID for staking position
    bytes32 public constant MARKET_ID_STAKING_MPH = 0x9a31fdde7a3b1444b1befb10735dcc3b72cbd9dd604d2ff45144352bf0f359a6;

    address public owner;

    event AdminUnstaked(address indexed userAddress, uint256 indexed amount, uint256 poolShares);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "MorpherStakingUnstakeOnly: caller is not the owner");
        _;
    }

    modifier onlyAdministrator() {
        require(
            msg.sender == owner || msg.sender == morpherState.getAdministrator(),
            "MorpherStakingUnstakeOnly: caller is not administrator"
        );
        _;
    }

    constructor(address _morpherState, address _oldStaking) {
        morpherState = IMorpherStateOld(_morpherState);
        oldStaking = IMorpherStakingOld(_oldStaking);
        owner = msg.sender;
    }

    // ----------------------------------------------------------------------------
    // getCurrentPoolShareValue
    // Calculates the current pool share value based on the old staking contract's
    // state and elapsed time since last reward.
    // ----------------------------------------------------------------------------

    function getCurrentPoolShareValue() public view returns (uint256) {
        uint256 _poolShareValue = oldStaking.poolShareValue();
        uint256 _lastReward = oldStaking.lastReward();
        uint256 _interestRate = oldStaking.interestRate();

        if (block.timestamp >= _lastReward + INTERVAL) {
            uint256 _numOfIntervals = (block.timestamp - _lastReward) / INTERVAL;
            _poolShareValue = _poolShareValue + (_numOfIntervals * _interestRate);
        }

        return _poolShareValue;
    }

    // ----------------------------------------------------------------------------
    // adminUnstake(address _user)
    // Administrator force-unstakes a user's stake, bypassing any lockup period.
    // The user receives their tokens based on current pool share value.
    // ----------------------------------------------------------------------------

    function adminUnstake(address _user) public onlyAdministrator returns (uint256 _amount) {
        (uint256 _numOfShares, , , , , ) = morpherState.getPosition(_user, MARKET_ID_STAKING_MPH);
        require(_numOfShares > 0, "MorpherStakingUnstakeOnly: user has no stake");

        uint256 lockedInUntil = morpherState.getLastUpdated(_user, MARKET_ID_STAKING_MPH);
        uint256 currentPoolShareValue = getCurrentPoolShareValue();

        // Clear the user's staking position
        morpherState.setPosition(_user, MARKET_ID_STAKING_MPH, lockedInUntil, 0, 0, 0, 0, 0, 0);

        // Calculate token amount
        _amount = _numOfShares * currentPoolShareValue;

        // Mint any rewards needed to cover the unstake
        uint256 stakingBalance = morpherState.balanceOf(STAKING_ADDRESS);
        if (stakingBalance < _amount) {
            uint256 toMint = _amount - stakingBalance;
            morpherState.mint(STAKING_ADDRESS, toMint);
        }

        // Transfer tokens to user
        morpherState.transfer(STAKING_ADDRESS, _user, _amount);

        emit AdminUnstaked(_user, _amount, _numOfShares);
        return _amount;
    }

    // ----------------------------------------------------------------------------
    // adminUnstakeBatch(address[] memory _users)
    // Administrator force-unstakes multiple users' stakes in a single transaction.
    // ----------------------------------------------------------------------------

    function adminUnstakeBatch(address[] memory _users) public onlyAdministrator returns (uint256 _totalAmount) {
        uint256 currentPoolShareValue = getCurrentPoolShareValue();
        _totalAmount = 0;

        for (uint256 i = 0; i < _users.length; i++) {
            address _user = _users[i];
            (uint256 _numOfShares, , , , , ) = morpherState.getPosition(_user, MARKET_ID_STAKING_MPH);

            if (_numOfShares == 0) {
                continue; // Skip users with no stake
            }

            uint256 lockedInUntil = morpherState.getLastUpdated(_user, MARKET_ID_STAKING_MPH);

            // Clear the user's staking position
            morpherState.setPosition(_user, MARKET_ID_STAKING_MPH, lockedInUntil, 0, 0, 0, 0, 0, 0);

            // Calculate token amount
            uint256 _amount = _numOfShares * currentPoolShareValue;
            _totalAmount += _amount;

            // Mint any rewards needed to cover the unstake
            uint256 stakingBalance = morpherState.balanceOf(STAKING_ADDRESS);
            if (stakingBalance < _amount) {
                uint256 toMint = _amount - stakingBalance;
                morpherState.mint(STAKING_ADDRESS, toMint);
            }

            // Transfer tokens to user
            morpherState.transfer(STAKING_ADDRESS, _user, _amount);

            emit AdminUnstaked(_user, _amount, _numOfShares);
        }

        return _totalAmount;
    }

    // ----------------------------------------------------------------------------
    // Getter functions
    // ----------------------------------------------------------------------------

    function getStake(address _address) public view returns (uint256 _poolShares) {
        (uint256 _numOfShares, , , , , ) = morpherState.getPosition(_address, MARKET_ID_STAKING_MPH);
        return _numOfShares;
    }

    function getStakeValue(address _address) public view returns (uint256 _value) {
        uint256 _numOfShares = getStake(_address);
        return _numOfShares * getCurrentPoolShareValue();
    }

    function getLockedUntil(address _address) public view returns (uint256 _lockedUntil) {
        return morpherState.getLastUpdated(_address, MARKET_ID_STAKING_MPH);
    }

    // ----------------------------------------------------------------------------
    // Ownership
    // ----------------------------------------------------------------------------

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "MorpherStakingUnstakeOnly: new owner is zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
