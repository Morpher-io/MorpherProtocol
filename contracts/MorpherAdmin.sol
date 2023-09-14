pragma solidity 0.5.16;

import "./SafeMath.sol";
import "./MorpherState.sol";
import "./MorpherTradeEngine.sol";

// ----------------------------------------------------------------------------------
// Administrator of the Morpher platform
// ----------------------------------------------------------------------------------

contract MorpherAdmin {
    MorpherState state;
    MorpherTradeEngine tradeEngine;
    using SafeMath for uint256;

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
        require(msg.sender == state.getAdministrator(), "Function can only be called by the Administrator.");
        _;
    }
    
    constructor(address _stateAddress, address _tradeEngine) public {
        state = MorpherState(_stateAddress);
        tradeEngine = MorpherTradeEngine(_tradeEngine);
    }

// ----------------------------------------------------------------------------
// Administrative functions
// Set state address and maximum permitted leverage on platform
// ----------------------------------------------------------------------------
    function setMorpherState(address _stateAddress) public onlyAdministrator {
        state = MorpherState(_stateAddress);
    }

    function setMorpherTradeEngine(address _tradeEngine) public onlyAdministrator {
        tradeEngine = MorpherTradeEngine(_tradeEngine);
    }

    function migratePositionsToNewMarket(bytes32 _oldMarketId, bytes32 _newMarketId) public onlyAdministrator {
        require(state.getMarketActive(_oldMarketId) == false, "Market must be paused to process market migration.");
        require(state.getMarketActive(_newMarketId) == false, "Market must be paused to process market migration.");

        uint256 maxMarketAddressIndex = state.getMaxMappingIndex(_oldMarketId);
        address[] memory addresses = new address[](maxMarketAddressIndex);
        for (uint256 i = 1; i <= maxMarketAddressIndex; i++) { 
            addresses[i-1] = state.getExposureMappingAddress(_oldMarketId, i); //changing on position delete
        }
        for(uint256 i = 0; i < addresses.length; i++) {
            address _address = addresses[i]; //normalize back to 0-based index
            (uint longShares, uint shortShares, uint meanEntryPrice, uint meanEntrySpread, uint meanEntryLeverage, uint liquidationPrice) = state.getPosition(_address, _oldMarketId);
            if(longShares > 0 || shortShares > 0) {
                state.setPosition(_address, _newMarketId, block.timestamp, longShares, shortShares, meanEntryPrice, meanEntrySpread, meanEntryLeverage, liquidationPrice); //create a new position for the new market with the same parameters
                state.setPosition(_address, _oldMarketId, block.timestamp, 0,0,0,0,0,0); //delete the current position   
                emit AddressPositionMigrationComplete(_address, _oldMarketId, _newMarketId);  
            } 

            if(gasleft() < 500000 && (i+1) < addresses.length) { //stop if there's not enough gas to write the next transaction
                emit AllPositionMigrationIncomplete(_oldMarketId, _newMarketId, i);
                return;
            }
        }

        emit AllPositionMigrationsComplete(_oldMarketId, _newMarketId);
    }

    event TokenMigrationComplete(address _from, address _to, uint _amount, uint _timestamp);
    event MarketMigrationComplete(bytes32 _marketId, address _from, address _to, uint _timestamp);

    /**
     * @notice To migrate the tokens we send it from the msg.sender address to _to and emit an event that TokenMigrationComplete
     * @dev the "if" is intentional, so that we can re-call the function as many times as we want, but it will only execute one time only
     */
    function migrateTokens(address _from, address _to) external onlyAdministrator() {
        
        uint balance = state.balanceOf(_from);
        state.transfer(_from, _to, balance);
        emit TokenMigrationComplete(_from, _to, balance, block.timestamp);
    }

    function migratePositions(address _from, address _to, bytes32 marketId) public  onlyAdministrator() returns (bool) {
        
        (uint longShares, uint shortShares, uint meanEntryPrice, uint meanEntrySpread, uint meanEntryLeverage, uint liquidationPrice) = state.getPosition(_from, marketId);
        if(longShares > 0 || shortShares > 0) {
            state.setPosition(_to, marketId, state.getLastUpdated(_from, marketId), longShares, shortShares, meanEntryPrice, meanEntrySpread, meanEntryLeverage, liquidationPrice); //create a new position for the "to" address with the same parameters
            state.setPosition(_from, marketId, block.timestamp, 0,0,0,0,0,0); //delete the current position   
            emit MarketMigrationComplete(marketId, _from, _to, block.timestamp);  
        }
        return true;
    }


// ----------------------------------------------------------------------------------
// stockSplits(bytes32 _marketId, uint256 _fromIx, uint256 _toIx, uint256 _nominator, uint256 _denominator)
// Experimental and untested
// ----------------------------------------------------------------------------------

    function stockSplits(bytes32 _marketId, uint256 _fromIx, uint256 _toIx, uint256 _nominator, uint256 _denominator) public onlyAdministrator {
        require(state.getMarketActive(_marketId) == false, "Market must be paused to process stock splits.");
        // If no _fromIx and _toIx specified, do entire _list
        if (_fromIx == 0) {
            _fromIx = 1;
        }
        if (_toIx == 0) {
            _toIx = state.getMaxMappingIndex(_marketId);
        }
        uint256 _positionLongShares;
        uint256 _positionShortShares;
        uint256 _positionAveragePrice;
        uint256 _positionAverageSpread;
        uint256 _positionAverageLeverage;
        uint256 _liquidationPrice;
        address _address;
        
        for (uint256 i = _fromIx; i <= _toIx; i++) {
             // GET position from state
             // multiply with nominator, divide by denominator (longShares/shortShares/meanEntry/meanSpread)
             // Write back to state
            _address = state.getExposureMappingAddress(_marketId, i);
            (_positionLongShares, _positionShortShares, _positionAveragePrice, _positionAverageSpread, _positionAverageLeverage, _liquidationPrice) = state.getPosition(_address, _marketId);
            _positionLongShares      = _positionLongShares.mul(_denominator).div(_nominator);
            _positionShortShares     = _positionShortShares.mul(_denominator).div(_nominator);
            _positionAveragePrice    = _positionAveragePrice.mul(_nominator).div(_denominator);
            _positionAverageSpread   = _positionAverageSpread.mul(_nominator).div(_denominator);
            if (_positionShortShares > 0) {
                _liquidationPrice    = getLiquidationPriceInternal(false, _address, _marketId);
            } else {
                _liquidationPrice    = getLiquidationPriceInternal(true, _address, _marketId);
            }               
            state.setPosition(_address, _marketId, now, _positionLongShares, _positionShortShares, _positionAveragePrice, _positionAverageSpread, _positionAverageLeverage, _liquidationPrice);   
        }
    }

// ----------------------------------------------------------------------------------
// contractRolls(bytes32 _marketId, uint256 _fromIx, uint256 _toIx, uint256 _rollUp, uint256 _rollDown)
// Experimental and untested
// ----------------------------------------------------------------------------------
    function contractRolls(bytes32 _marketId, uint256 _fromIx, uint256 _toIx, uint256 _rollUp, uint256 _rollDown) public onlyAdministrator {
        // If no _fromIx and _toIx specified, do entire _list
        // dividends set meanEntry down, rolls either up or down
        require(state.getMarketActive(_marketId) == false, "Market must be paused to process rolls.");
        // If no _fromIx and _toIx specified, do entire _list
        if (_fromIx == 0) {
            _fromIx = 1;
        }
        if (_toIx == 0) {
            _toIx = state.getMaxMappingIndex(_marketId);
        }
        uint256 _positionLongShares;
        uint256 _positionShortShares;
        uint256 _positionAveragePrice;
        uint256 _positionAverageSpread;
        uint256 _positionAverageLeverage;
        uint256 _liquidationPrice;
        address _address;
        
        for (uint256 i = _fromIx; i <= _toIx; i++) {
            _address = state.getExposureMappingAddress(_marketId, i);
            (_positionLongShares, _positionShortShares, _positionAveragePrice, _positionAverageSpread, _positionAverageLeverage, _liquidationPrice) = state.getPosition(_address, _marketId);
            _positionAveragePrice    = _positionAveragePrice.add(_rollUp).sub(_rollDown);
            if (_positionShortShares > 0) {
                _liquidationPrice    = getLiquidationPriceInternal(false, _address, _marketId);
            } else {
                _liquidationPrice    = getLiquidationPriceInternal(true, _address, _marketId);
            }               
            state.setPosition(_address, _marketId, now, _positionLongShares, _positionShortShares, _positionAveragePrice, _positionAverageSpread, _positionAverageLeverage, _liquidationPrice);   
        }
    }

/**
 * Stack too deep error
 */
    function getLiquidationPriceInternal(bool isLong, address _userAddress, bytes32 _marketId) internal view returns (uint) {
        ( , , uint price, , uint leverage, ) = state.getPosition(_userAddress, _marketId);
        return tradeEngine.getLiquidationPrice(price, leverage, isLong, state.getLastUpdated(_userAddress, _marketId));
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
            _toIx = state.getMaxMappingIndex(_marketId);
        }
        address _address;
        for (uint256 i = _fromIx; i <= _toIx; i++) {
            _address = state.getExposureMappingAddress(_marketId, i);
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
            uint256 _positionLongShares = state.getLongShares(_address, _marketId);
            uint256 _positionShortShares = state.getShortShares(_address, _marketId);
            if (_positionLongShares > 0) {
                _orderId = tradeEngine.requestOrderId(_address, _marketId, _positionLongShares, 0, false, 10**8);
                emit AdminLiquidationOrderCreated(_orderId, _address, _marketId, _positionLongShares, 0, false, 10**8);
            }
            if (_positionShortShares > 0) {
                _orderId = tradeEngine.requestOrderId(_address, _marketId, _positionShortShares, 0, true, 10**8);
                emit AdminLiquidationOrderCreated(_orderId, _address, _marketId, _positionShortShares, 0, true, 10**8);
            }
            return _orderId;
    }

// ----------------------------------------------------------------------------------
// payOperatingReward()
// Calls paying of operating reward in state
// ----------------------------------------------------------------------------------
    function payOperatingReward() public view {
        if (state.mainChain() == true) {
            uint256 _lastRewardTime = state.lastRewardTime();
            if (now > _lastRewardTime) {
                for (uint256 i = 1; i <= now.sub(state.lastRewardTime()).div(86400); i++) {
                    state.payOperatingReward;
                }
            }
        }
    }

// ----------------------------------------------------------------------------------
// stockDividends()
// May want to add support for dividends later
// ----------------------------------------------------------------------------------
/*    function stockDividends(bytes32 _marketId, uint256 _fromIx, uint256 _toIx, uint256 _meanEntryUp, uint256 _meanEntryDown) public onlyOracle returns (bool _success){
    }
*/
}
