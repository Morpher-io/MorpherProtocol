// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.5.16;

import "./IERC20.sol";
import "./IMorpherState.sol";
import "./Ownable.sol";

/**
 * @title Account Migration Smart Contract
 * @author Thomas Wiesner 
 * @notice This Contract allows the migration of the tokens and positions from one address to another
 * @dev This smart contract needs platform rights to do its job
 */
contract MorpherAccountMigration is Ownable {

    address tokenAddress;
    address stateAddress;

    constructor(address _morpherTokenAddress, address _morpherStateAddress) public {
        tokenAddress = _morpherTokenAddress;
        stateAddress = _morpherStateAddress;

    }
    
    //this holds a boolean for the _target_ address, the target must allow first to migrate to, otherwise one could overwrite any address
    mapping(address => uint) isAllowedToMigrateUntil;
    //this holds a source->target address, so that only the old source can overwrite a new target address
    mapping(address => address) sourceAddressAllowedToOverwriteTo;

    //this holds a boolean if the market is already migrated or not
    mapping(bytes32 => bool) marketMigrated;

    //this holds a boolean for successful token migration from an address away (source address bound)
    mapping(address => bool) tokensMigratedFrom;

    event TokenMigrationComplete(address _from, address _to, uint _amount, uint _timestamp);
    event MarketMigrationComplete(bytes32 _marketId, address _from, address _to, uint _timestamp);

    event MigrationIncomplete(address _from, address _to, uint _timestamp);
    event MigrationComplete(address _from, address _to, uint _timestamp);

    mapping(bytes32 => uint) marketHashId;
    bytes32[] marketHashes;


    function addMarketHash(bytes32[] memory _marketHashes) public onlyOwner {
        for(uint i = 0; i < _marketHashes.length; i++) {
            if(marketHashId[_marketHashes[i]] == 0) {
                marketHashes.push(_marketHashes[i]);
                marketHashId[_marketHashes[i]] = marketHashes.length - 1;
            }
        }
    }

    /**
     * @notice This function will open a 12 hour window to allow migration to a target address from a _from-source address
    */
    function allowMigrationFor12Hours(address _from) public {
        isAllowedToMigrateUntil[msg.sender] = block.timestamp + 12 hours;
        sourceAddressAllowedToOverwriteTo[_from] = msg.sender;
    }

    /**
     * @notice the modifier checks if an target-address allows migration
     */
    modifier isAllowedToMigrateTo(address _to) {
        require(isAllowedToMigrateUntil[_to] >= block.timestamp, "Migration to Address not allowed");
        require(sourceAddressAllowedToOverwriteTo[msg.sender] == _to, "Address is not allowed to migrate to target address");
        _;
    }

    function startMigrate(address _to) public isAllowedToMigrateTo(_to) {
        migrateTokens(_to);
        bool migrationComplete = migratePositions(_to);
        if(migrationComplete) {
            emit MigrationComplete(msg.sender, _to, block.timestamp);
        } else {
            emit MigrationIncomplete(msg.sender, _to, block.timestamp);
        }
    }

    /**
     * @notice To migrate the tokens we send it from the msg.sender address to _to and emit an event that TokenMigrationComplete
     * @dev the "if" is intentional, so that we can re-call the function as many times as we want, but it will only execute one time only
     */
    function migrateTokens(address _to) internal isAllowedToMigrateTo(_to) {
        if(tokensMigratedFrom[msg.sender] == false) {
            IERC20 token = IERC20(tokenAddress);
            uint balance = token.balanceOf(msg.sender);
            token.transferFrom(msg.sender, _to, balance);
            tokensMigratedFrom[msg.sender] = true;
            emit TokenMigrationComplete(msg.sender, _to, balance, block.timestamp);
        }
    }

    function migratePositions(address _to) internal isAllowedToMigrateTo(_to) returns (bool) {
        IMorpherState state = IMorpherState(stateAddress);

        for(uint i = 0; i < marketHashes.length; i++) {
            if(marketMigrated[marketHashes[i]] == false) {
                (uint longShares, uint shortShares, uint meanEntryPrice, uint meanEntrySpread, uint meanEntryLeverage, uint liquidationPrice) = state.getPosition(msg.sender, marketHashes[i]);
                if(longShares > 0 || shortShares > 0) {
                    state.setPosition(_to, marketHashes[i], block.timestamp, longShares, shortShares, meanEntryPrice, meanEntrySpread, meanEntryLeverage, liquidationPrice); //create a new position for the "to" address with the same parameters
                    state.setPosition(msg.sender, marketHashes[i], block.timestamp, 0,0,0,0,0,0); //delete the current position
                    marketMigrated[marketHashes[i]] = true; //avoid 
                    emit MarketMigrationComplete(marketHashes[i], msg.sender, _to, block.timestamp);
                    if(gasleft() < 50000 && i != (marketHashes.length - 1)) {
                        return false;
                    }
                }
            }
        }
        return true;

    }

}