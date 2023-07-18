
//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./library/Array.sol";

contract DataProviderCollateralStorage {


    using Array for address[];

    uint256 constant WITHDRAW_DELAY = 7 * 24 * 60 * 60; // seconds (1 week)
    uint256 constant MINIMUM_COLLATERAL = 1000 ether;

    struct Collateral {
        uint timestamp;
        uint amount;
    }

    event DataProviderCollateralAdded(address dp, uint amount);
    event DataProviderCollateralStagedForWithdrawal(address dp, uint amount, uint unlockForWithdrawalTimestamp);
    event DataProviderCollateralWithdrawn(address dp, uint amount);

    mapping(address => Collateral) public dpCollateral;
    mapping(address => Collateral) public stagedForWithdrawal;
    mapping(address => uint) public dataProviderTickPrice;
    address[] public dataProviders;

    function setTickPrice(uint price) public {
        dataProviderTickPrice[msg.sender] = price;
    }

    function depositCollateral() public payable {
        dpCollateral[msg.sender].timestamp = block.timestamp;
        dpCollateral[msg.sender].amount += msg.value;
        if(dataProviderHasEnoughStake(msg.sender) && !dataProviders.includes(msg.sender)) {
            dataProviders.push(msg.sender);
        }
        emit DataProviderCollateralAdded(msg.sender, msg.value);
    }

    function stageColleteralForWithdrawal(uint amount) public {
        require(dpCollateral[msg.sender].amount >= amount, "You have not enough collateral staked to stage");
        require(stagedForWithdrawal[msg.sender].amount == 0, "First withdraw your staged collateral before staging new collateral");
        stagedForWithdrawal[msg.sender].timestamp = block.timestamp + WITHDRAW_DELAY;
        stagedForWithdrawal[msg.sender].amount = amount;
        dpCollateral[msg.sender].amount -= amount;
        emit DataProviderCollateralStagedForWithdrawal(msg.sender, amount, block.timestamp + WITHDRAW_DELAY);
    }

    function withdrawStagedCollateral() public {
        require(stagedForWithdrawal[msg.sender].timestamp <= block.timestamp, "Withdrawal not yet possible, stake still locked");
        uint amount = stagedForWithdrawal[msg.sender].amount;
        stagedForWithdrawal[msg.sender].amount = 0;
        if(!dataProviderHasEnoughStake(msg.sender) && dataProviders.includes(msg.sender)) {
            dataProviders.remove(dataProviders.indexOf(msg.sender));
        }
        payable(msg.sender).transfer(amount);
    }

    function dataProviderHasEnoughStake(address dp) public view returns(bool) {
        return dpCollateral[dp].amount >= MINIMUM_COLLATERAL;
    }

    function getDataProviders() public view returns(address[] memory) {
        return dataProviders;
    }
}