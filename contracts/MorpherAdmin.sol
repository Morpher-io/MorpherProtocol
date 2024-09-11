//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.15;

import "./MorpherAccessControl.sol";
import "./MorpherState.sol";
import "./MorpherTradeEngine.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// ----------------------------------------------------------------------------------
// Administrator of the Morpher platform
// ----------------------------------------------------------------------------------

contract MorpherAdmin is Initializable {
    MorpherState state;

    bytes32 constant ADMINISTRATOR_ROLE = keccak256("ADMINISTRATOR_ROLE");

    event AdminLiquidationOrderCreated(
        bytes32 indexed _orderId,
        address indexed _address,
        bytes32 indexed _marketId,
        uint256 _closeSharesAmount,
        uint256 _openMPHTokenAmount,
        bool _tradeDirection,
        uint256 _orderLeverage
        );

 event AddressPositionMigrationComplete(address _owner, bytes32 _oldMarketId, bytes32 _newMarketId);
 event AllPositionMigrationsComplete(bytes32 _oldMarketId, bytes32 _newMarketId);
 event AllPositionMigrationIncomplete(bytes32 _oldMarketId, bytes32 _newMarketId, uint _maxIx);

// ----------------------------------------------------------------------------
// Precision of prices and leverage
// ----------------------------------------------------------------------------

    modifier onlyAdministrator {
        require(MorpherAccessControl(state.morpherAccessControlAddress()).hasRole(ADMINISTRATOR_ROLE, msg.sender), "Function can only be called by the Administrator.");
        _;
    }

    function initialize(address _stateAddress) initializer public {
        state = MorpherState(_stateAddress);
    }
    

// ----------------------------------------------------------------------------
// Administrative functions
// Set state address and maximum permitted leverage on platform
// ----------------------------------------------------------------------------
    function setMorpherState(address _stateAddress) public onlyAdministrator {
        state = MorpherState(_stateAddress);
    }

    function migratePositionsToNewMarket(bytes32 _oldMarketId, bytes32 _newMarketId) public onlyAdministrator {
        require(state.getMarketActive(_oldMarketId) == false, "Market must be paused to process market migration.");
        require(state.getMarketActive(_newMarketId) == false, "Market must be paused to process market migration.");

        uint256 maxMarketAddressIndex = MorpherTradeEngine(state.morpherTradeEngineAddress()).getMaxMappingIndex(_oldMarketId);
        address[] memory addresses = new address[](maxMarketAddressIndex);
        for (uint256 i = 1; i <= maxMarketAddressIndex; i++) { 
            addresses[i-1] = MorpherTradeEngine(state.morpherTradeEngineAddress()).getExposureMappingAddress(_oldMarketId, i); //changing on position delete
        }
        for(uint256 i = 0; i < addresses.length; i++) {
            address _address = addresses[i]; //normalize back to 0-based index
            MorpherTradeEngine.position memory position = MorpherTradeEngine(state.morpherTradeEngineAddress()).getPosition(_address, _oldMarketId);
            if(position.longShares > 0 || position.shortShares > 0) {
                MorpherTradeEngine(state.morpherTradeEngineAddress()).setPosition(_address, _newMarketId, block.timestamp, position.longShares, position.shortShares, position.meanEntryPrice, position.meanEntrySpread, position.meanEntryLeverage, position.liquidationPrice); //create a new position for the new market with the same parameters
                MorpherTradeEngine(state.morpherTradeEngineAddress()).setPosition(_address, _oldMarketId, block.timestamp, 0,0,0,0,0,0); //delete the current position   
                emit AddressPositionMigrationComplete(_address, _oldMarketId, _newMarketId);  
            } 

            if(gasleft() < 500000 && (i+1) < addresses.length) { //stop if there's not enough gas to write the next transaction
                emit AllPositionMigrationIncomplete(_oldMarketId, _newMarketId, i);
                return;
            }
        }

        emit AllPositionMigrationsComplete(_oldMarketId, _newMarketId);
    }

    /**
    * Bulk activates markets through a bytes32 array given as calldata
    * Only the Admin should be able to do this
    */
    function bulkActivateMarkets(bytes32[] memory _marketHashes) public onlyAdministrator {
        for(uint i = 0; i < _marketHashes.length; i++) {
            bytes memory payload = abi.encodeWithSignature("activateMarket(bytes32)", _marketHashes[i]);
            (bool success, ) = address(state).call(payload);
            require(success,  "MorpherAdministratorProxy: Failed to activate Market");
        }
    }



    
    // ----------------------------------------------------------------------------------
    // delistMarket(bytes32 _marketId)
    // Administrator closes out all existing positions on _marketId market at current prices
    // ----------------------------------------------------------------------------------
    function delistMarket(bytes32 _marketId, uint256 _fromIx, uint256 _toIx) public onlyAdministrator {
        require(state.getMarketActive(_marketId) == true, "Market must be active to process position liquidations.");
        // If no _fromIx and _toIx specified, do entire _list
        if (_fromIx == 0) {
            _fromIx = 1;
        }
        if (_toIx == 0) {
            _toIx = MorpherTradeEngine(state.morpherTradeEngineAddress()).getMaxMappingIndex(_marketId);
        }
        address _address;
        for (uint256 i = _fromIx; i <= _toIx; i++) {
            _address = MorpherTradeEngine(state.morpherTradeEngineAddress()).getExposureMappingAddress(_marketId, i);
            adminLiquidationOrder(_address, _marketId);
        }
    }

    // ----------------------------------------------------------------------------------
    // delistMarket(bytes32 _marketId)
    // Administrator closes out an existing positions on _marketId market at current price
    // ----------------------------------------------------------------------------------
    function adminLiquidationOrder(
        address _address,
        bytes32 _marketId
        ) public onlyAdministrator returns (bytes32 _orderId) {
            MorpherTradeEngine.position memory position = MorpherTradeEngine(state.morpherTradeEngineAddress()).getPosition(_address, _marketId);
            uint256 _positionLongShares = position.longShares;
            uint256 _positionShortShares = position.shortShares;
            if (_positionLongShares > 0) {
                _orderId = MorpherTradeEngine(state.morpherTradeEngineAddress()).requestOrderId(_address, _marketId, _positionLongShares, 0, false, 10**8);
                emit AdminLiquidationOrderCreated(_orderId, _address, _marketId, _positionLongShares, 0, false, 10**8);
            }
            if (_positionShortShares > 0) {
                _orderId = MorpherTradeEngine(state.morpherTradeEngineAddress()).requestOrderId(_address, _marketId, _positionShortShares, 0, true, 10**8);
                emit AdminLiquidationOrderCreated(_orderId, _address, _marketId, _positionShortShares, 0, true, 10**8);
            }
            return _orderId;
    }

// ----------------------------------------------------------------------------------
// payOperatingReward()
// Calls paying of operating reward in state
// ----------------------------------------------------------------------------------
    // function payOperatingReward() public view {
    //     uint256 _lastRewardTime = state.lastRewardTime();
    //     if (block.timestamp > _lastRewardTime) {
    //         for (uint256 i = 1; i <= block.timestamp - state.lastRewardTime() / 86400; i++) {
    //             state.payOperatingReward();
    //         }
    //     } 
    // }

// ----------------------------------------------------------------------------------
// stockDividends()
// May want to add support for dividends later
// ----------------------------------------------------------------------------------
/*    function stockDividends(bytes32 _marketId, uint256 _fromIx, uint256 _toIx, uint256 _meanEntryUp, uint256 _meanEntryDown) public onlyOracle returns (bool _success){
    }
*/
}
