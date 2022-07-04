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

    address public stateAddress;

    constructor(address _morpherStateAddress) public {
        stateAddress = _morpherStateAddress;
    }
    
    //this holds a source->target address, so that only the old source can overwrite a new target address
    mapping(address => address) public sourceAddressAllowedToOverwriteTo;
    //this one is to check if the morpherWallet address has started a migration process. UX wise it should be impossible to do anything until it's completed
    mapping(address => address) public destinationAddressAllowsOverwriting;

    //this mapping is set by the admin. It is here to let the backend do another sanity check that the user is really the user (formatic from => zerowallet to)
    mapping(address => address) public ownerSetMigrationAllowance;


    //this holds a boolean if the market is already migrated or not for a specific address
    mapping(bytes32 => mapping(address => bool)) marketMigrated;

    //this holds a boolean for successful token migration from an address away (source address bound)
    mapping(address => bool) tokensMigratedFrom;

    //this is the index for running through the market hashes array. So when a migration is incomplete that at the next time it calls "startMigrate" the for-loop won't start from scratch
    mapping(address => uint) indexMarketHash;

    //this mapping tells you if the migration process has started
    mapping(address => bool) public sourceAddressMigrationStarted;
    mapping(address => bool) public sourceAddressMigrationFinished;

    event TokenMigrationComplete(address _from, address _to, uint _amount, uint _timestamp);
    event MarketMigrationComplete(bytes32 _marketId, address _from, address _to, uint _timestamp);

    event MigrationIncomplete(address _from, address _to, uint _timestamp);
    event MigrationComplete(address _from, address _to, uint _timestamp);

    event MigrationPermissionGiven(address _from, address _to, uint _timestamp);

    mapping(bytes32 => uint) marketHashId;
    bytes32[] marketHashes;


    function addMarketHashes(bytes32[] memory _marketHashes) public onlyOwner {
        for(uint i = 0; i < _marketHashes.length; i++) {
            if(marketHashId[_marketHashes[i]] == 0) {
                marketHashes.push(_marketHashes[i]);
                marketHashId[_marketHashes[i]] = marketHashes.length - 1;
            }
        }
    }

    /**
     * @notice This function will allow migration to a target address from a _from-source address
    */
    function allowMigrationFrom(address _from) public {
        require(destinationAddressAllowsOverwriting[msg.sender] == address(0), "cannot split address migration");
        sourceAddressAllowedToOverwriteTo[_from] = msg.sender;
        destinationAddressAllowsOverwriting[msg.sender] = _from;
        emit MigrationPermissionGiven(_from, msg.sender, block.timestamp);
    }

    /**
    * @notice This modifier and the function below are for the backend to set a source and destination address. The user needs to be a registered user in our signup/login flow.
    */
   function ownerConfirmMigrationAddresses(address _from, address _to) public onlyOwner {
        ownerSetMigrationAllowance[_from] = _to;
    }

    /**
     * @notice the modifier checks if an target-address allows migration
     */
    modifier isAllowedToMigrateTo(address _to) {
        require(sourceAddressAllowedToOverwriteTo[msg.sender] == _to, "Address is not allowed to migrate to target address");
        require(ownerSetMigrationAllowance[msg.sender] == _to, "Address is not whitelisted by backend");
        _;
    }

    function startMigrate(address _to) public isAllowedToMigrateTo(_to) {
        sourceAddressMigrationStarted[msg.sender] = true;
        migrateTokens(_to);
        bool migrationComplete = migratePositions(_to);
        if(migrationComplete) {
            sourceAddressMigrationFinished[msg.sender] = true;
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
            IMorpherState state = IMorpherState(stateAddress);
            uint balance = state.balanceOf(msg.sender);
            state.transfer(msg.sender, _to, balance);
            tokensMigratedFrom[msg.sender] = true;
            emit TokenMigrationComplete(msg.sender, _to, balance, block.timestamp);
        }
    }

    function migratePositions(address _to) internal isAllowedToMigrateTo(_to) returns (bool) {
        IMorpherState state = IMorpherState(stateAddress);

        for(uint i = indexMarketHash[msg.sender]; i < marketHashes.length; i++) {
            //if(marketMigrated[marketHashes[i]][_to] == false) {
                if(gasleft() < 500000) { //stop if there's not enough gas to write the next transaction
                    indexMarketHash[msg.sender] = i;
                    return false;
                }
            
                (uint longShares, uint shortShares, uint meanEntryPrice, uint meanEntrySpread, uint meanEntryLeverage, uint liquidationPrice) = state.getPosition(msg.sender, marketHashes[i]);
                if(longShares > 0 || shortShares > 0) {
                    // state.setPosition(_to, marketHashes[i], block.timestamp, longShares, shortShares, meanEntryPrice, meanEntrySpread, meanEntryLeverage, liquidationPrice); //create a new position for the "to" address with the same parameters
                    state.setPosition(_to, marketHashes[i], state.getLastUpdated(msg.sender, marketHashes[i]), longShares, shortShares, meanEntryPrice, meanEntrySpread, meanEntryLeverage, liquidationPrice); //create a new position for the "to" address with the same parameters
                    state.setPosition(msg.sender, marketHashes[i], block.timestamp, 0,0,0,0,0,0); //delete the current position   
                    emit MarketMigrationComplete(marketHashes[i], msg.sender, _to, block.timestamp);  
                }
            //    marketMigrated[marketHashes[i]][_to] = true; //avoid
            //}    
        }
        return true;
    }

}