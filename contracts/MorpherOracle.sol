//SPDX-License-Identifier: GPLv3
pragma solidity 0.8.11;

import "./MorpherTradeEngine.sol";
import "./MorpherState.sol";
import "./MorpherAccessControl.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";


// ----------------------------------------------------------------------------------
// Morpher Oracle contract v 2.0
// The oracle initates a new trade by calling trade engine and requesting a new orderId.
// An event is fired by the contract notifying the oracle operator to query a price/liquidation unchecked
// for a market/user and return the information via the callback function. Since calling
// the callback function requires gas, the user must send a fixed amount of Ether when
// creating their order.
// ----------------------------------------------------------------------------------

contract MorpherOracle is Initializable, ContextUpgradeable, PausableUpgradeable {

    MorpherState state; // read only, Oracle doesn't need writing access to state

    bool public useWhiteList; //always false at the moment

    uint256 public gasForCallback;

    address payable public callBackCollectionAddress;

    mapping(address => bool) public callBackAddress;
    mapping(address => bool) public whiteList;
    
    mapping(bytes32 => uint256) public priceBelow;
    mapping(bytes32 => uint256) public priceAbove;
    mapping(bytes32 => uint256) public goodFrom;
    mapping(bytes32 => uint256) public goodUntil;

    mapping(bytes32 => bool) public orderCancellationRequested;

    /**
     * ROLES KNOWN TO ORACLE
     */
    bytes32 constant public ADMINISTRATOR_ROLE = keccak256("ADMINISTRATOR_ROLE");
    bytes32 constant public ORACLEOPERATOR_ROLE = keccak256("ORACLEOPERATOR_ROLE"); //used for callbacks from API
    bytes32 constant public PAUSER_ROLE = keccak256("PAUSER_ROLE"); //can pause oracle

// ----------------------------------------------------------------------------------
// Events
// ----------------------------------------------------------------------------------
    event OrderCreated(
        bytes32 indexed _orderId,
        address indexed _address,
        bytes32 indexed _marketId,
        uint256 _closeSharesAmount,
        uint256 _openMPHTokenAmount,
        bool _tradeDirection,
        uint256 _orderLeverage,
        uint256 _onlyIfPriceBelow,
        uint256 _onlyIfPriceAbove,
        uint256 _goodFrom,
        uint256 _goodUntil
        );

    event LiquidationOrderCreated(
        bytes32 indexed _orderId,
        address _sender,
        address indexed _address,
        bytes32 indexed _marketId

        );

    event OrderProcessed(
        bytes32 indexed _orderId,
        uint256 _price,
        uint256 _unadjustedMarketPrice,
        uint256 _spread,
        uint256 _positionLiquidationTimestamp,
        uint256 _timeStamp,
        uint256 _newLongShares,
        uint256 _newShortShares,
        uint256 _newMeanEntry,
        uint256 _newMeanSprad,
        uint256 _newMeanLeverage,
        uint256 _liquidationPrice
        );

    event OrderFailed(
        bytes32 indexed _orderId,
        address indexed _address,
        bytes32 indexed _marketId,
        uint256 _closeSharesAmount,
        uint256 _openMPHTokenAmount,
        bool _tradeDirection,
        uint256 _orderLeverage,
        uint256 _onlyIfPriceBelow,
        uint256 _onlyIfPriceAbove,
        uint256 _goodFrom,
        uint256 _goodUntil
        );

    event OrderCancelled(
        bytes32 indexed _orderId,
        address indexed _sender,
        address indexed _oracleAddress
        );
    
    event AdminOrderCancelled(
        bytes32 indexed _orderId,
        address indexed _sender,
        address indexed _oracleAddress
        );

    event OrderCancellationRequestedEvent(
        bytes32 indexed _orderId,
        address indexed _sender
        );

    event CallbackAddressEnabled(
        address indexed _address
        );

    event CallbackAddressDisabled(
        address indexed _address
        );

    event OraclePaused(
        bool _paused
        );
        
    event CallBackCollectionAddressChange(
        address _address
        );

    event SetGasForCallback(
        uint256 _gasForCallback
        );

    event LinkTradeEngine(
        address _address
        );

    event LinkMorpherState(
        address _address
        );

    event SetUseWhiteList(
        bool _useWhiteList
        );

    event AddressWhiteListed(
        address _address
        );

    event AddressBlackListed(
        address _address
        );

    event AdminLiquidationOrderCreated(
        bytes32 indexed _orderId,
        address indexed _address,
        bytes32 indexed _marketId,
        uint256 _closeSharesAmount,
        uint256 _openMPHTokenAmount,
        bool _tradeDirection,
        uint256 _orderLeverage
        );

    /**
     * Delisting markets is a function that stops when gas is running low
     * if it reached all positions it will emit "DelistMarketComplete"
     * otherwise it needs to be re-run.
     */
    event DelistMarketIncomplete(bytes32 _marketId, uint256 _processedUntilIndex);
    event DelistMarketComplete(bytes32 _marketId);
    event LockedPriceForClosingPositions(bytes32 _marketId, uint256 _price);


    modifier onlyRole(bytes32 role) {
        require(MorpherAccessControl(state.morpherAccessControlAddress()).hasRole(role, _msgSender()), "MorpherOracle: Permission denied.");
        _;
    }

   function initialize(address _morpherState, address payable _gasCollectionAddress, uint256 _gasForCallback) public initializer{
        ContextUpgradeable.__Context_init();
        PausableUpgradeable.__Pausable_init();

        state = MorpherState(_morpherState);
        
        setCallbackCollectionAddress(_gasCollectionAddress);
        setGasForCallback(_gasForCallback);
    }

// ----------------------------------------------------------------------------------
// Setter/getter functions for trade engine address, oracle operator (callback) address,
// and prepaid gas limit for callback function
// ----------------------------------------------------------------------------------

    function setStateAddress(address _address) public onlyRole(ADMINISTRATOR_ROLE) {
        state = MorpherState(_address);
        emit LinkMorpherState(_address);
    }

    function overrideGasForCallback(uint256 _gasForCallback) public onlyRole(ADMINISTRATOR_ROLE) {
        gasForCallback = _gasForCallback;
        emit SetGasForCallback(_gasForCallback);
    }
    
    function setGasForCallback(uint256 _gasForCallback) private {
        gasForCallback = _gasForCallback;
        emit SetGasForCallback(_gasForCallback);
    }

    function setCallbackCollectionAddress(address payable _address) public onlyRole(ADMINISTRATOR_ROLE) {
        callBackCollectionAddress = _address;
        emit CallBackCollectionAddressChange(_address);
    }

// ----------------------------------------------------------------------------------
// emitOrderFailed
// Can be called by Oracle Operator to notifiy user of failed order
// ----------------------------------------------------------------------------------
    function emitOrderFailed(
        bytes32 _orderId,
        address _address,
        bytes32 _marketId,
        uint256 _closeSharesAmount,
        uint256 _openMPHTokenAmount,
        bool _tradeDirection,
        uint256 _orderLeverage,
        uint256 _onlyIfPriceBelow,
        uint256 _onlyIfPriceAbove,
        uint256 _goodFrom,
        uint256 _goodUntil
    ) public onlyRole(ORACLEOPERATOR_ROLE) {
        emit OrderFailed(
            _orderId,
            _address,
            _marketId,
            _closeSharesAmount,
            _openMPHTokenAmount,
            _tradeDirection,
            _orderLeverage,
            _onlyIfPriceBelow,
            _onlyIfPriceAbove,
            _goodFrom,
            _goodUntil);
    }

// ----------------------------------------------------------------------------------
// createOrder(bytes32  _marketId, bool _tradeAmountGivenInShares, uint256 _tradeAmount, bool _tradeDirection, uint256 _orderLeverage)
// Request a new orderId from trade engine and fires event for price/liquidation check request.
// ----------------------------------------------------------------------------------
    function createOrder(
        bytes32 _marketId,
        uint256 _closeSharesAmount,
        uint256 _openMPHTokenAmount,
        bool _tradeDirection,
        uint256 _orderLeverage,
        uint256 _onlyIfPriceAbove,
        uint256 _onlyIfPriceBelow,
        uint256 _goodUntil,
        uint256 _goodFrom
        ) public payable whenNotPaused returns (bytes32 _orderId) {
        if (gasForCallback > 0) {
            require(msg.value >= gasForCallback, "MorpherOracle: Must transfer gas costs for Oracle Callback function.");
            callBackCollectionAddress.transfer(msg.value);
        }
        _orderId = MorpherTradeEngine(state.morpherTradeEngineAddress()).requestOrderId(_msgSender(), _marketId, _closeSharesAmount, _openMPHTokenAmount, _tradeDirection, _orderLeverage);

        //if the market was deactivated, and the trader didn't fail yet, then we got an orderId to close the position with a locked in price
        if(state.getMarketActive(_marketId) == false) {

            //price will come from the position where price is stored forever
            MorpherTradeEngine(state.morpherTradeEngineAddress()).processOrder(_orderId, MorpherTradeEngine(state.morpherTradeEngineAddress()).getDeactivatedMarketPrice(_marketId), 0, 0, block.timestamp * (1000));
            
            emit OrderProcessed(
                _orderId,
                MorpherTradeEngine(state.morpherTradeEngineAddress()).getDeactivatedMarketPrice(_marketId),
                0,
                0,
                0,
                block.timestamp * (1000),
                0,
                0,
                0,
                0,
                0,
                0
                );
        } else {
            priceAbove[_orderId] = _onlyIfPriceAbove;
            priceBelow[_orderId] = _onlyIfPriceBelow;
            goodFrom[_orderId]   = _goodFrom;
            goodUntil[_orderId]  = _goodUntil;
            emit OrderCreated(
                _orderId,
                _msgSender(),
                _marketId,
                _closeSharesAmount,
                _openMPHTokenAmount,
                _tradeDirection,
                _orderLeverage,
                _onlyIfPriceBelow,
                _onlyIfPriceAbove,
                _goodFrom,
                _goodUntil
                );
        }

        return _orderId;
    }

    function initiateCancelOrder(bytes32 _orderId) public {
        MorpherTradeEngine _tradeEngine = MorpherTradeEngine(state.morpherTradeEngineAddress());
        require(orderCancellationRequested[_orderId] == false, "MorpherOracle: Order was already canceled.");
        (address userId, , , , , , ) = _tradeEngine.getOrder(_orderId);
        require(userId == _msgSender(), "MorpherOracle: Only the user can request an order cancellation.");
        orderCancellationRequested[_orderId] = true;
        emit OrderCancellationRequestedEvent(_orderId, _msgSender());
    }

    // ----------------------------------------------------------------------------------
    // cancelOrder(bytes32  _orderId)
    // User or Administrator can cancel their own orders before the _callback has been executed
    // ----------------------------------------------------------------------------------
    function cancelOrder(bytes32 _orderId) public onlyRole(ORACLEOPERATOR_ROLE) {
        require(orderCancellationRequested[_orderId] == true, "MorpherOracle: Order-Cancellation was not requested.");
        MorpherTradeEngine _tradeEngine = MorpherTradeEngine(state.morpherTradeEngineAddress());
        (address userId, , , , , , ) = _tradeEngine.getOrder(_orderId);
        _tradeEngine.cancelOrder(_orderId, userId);
        clearOrderConditions(_orderId);
        emit OrderCancelled(
            _orderId,
            userId,
            _msgSender()
            );
    }
    
    // ----------------------------------------------------------------------------------
    // adminCancelOrder(bytes32  _orderId)
    // Administrator can cancel before the _callback has been executed to provide an updateOrder functionality
    // ----------------------------------------------------------------------------------
    function adminCancelOrder(bytes32 _orderId) public onlyRole(ORACLEOPERATOR_ROLE) {
        MorpherTradeEngine _tradeEngine = MorpherTradeEngine(state.morpherTradeEngineAddress());
        (address userId, , , , , , ) = _tradeEngine.getOrder(_orderId);
        _tradeEngine.cancelOrder(_orderId, userId);
        clearOrderConditions(_orderId);
        emit AdminOrderCancelled(
            _orderId,
            userId,
            _msgSender()
            );
    }

// ------------------------------------------------------------------------
// checkOrderConditions(bytes32 _orderId, uint256 _price)
// Checks if callback satisfies the order conditions
// ------------------------------------------------------------------------
    function checkOrderConditions(bytes32 _orderId, uint256 _price) public view returns (bool _conditionsMet) {
        _conditionsMet = true;
        if (block.timestamp > goodUntil[_orderId] && goodUntil[_orderId] > 0) {
            _conditionsMet = false;
        }
        if (block.timestamp < goodFrom[_orderId] && goodFrom[_orderId] > 0) {
            _conditionsMet = false;
        }

        if(priceAbove[_orderId] > 0 && priceBelow[_orderId] > 0) {
            if(_price < priceAbove[_orderId] && _price > priceBelow[_orderId]) {
                _conditionsMet = false;
            }
        } else {
            if (_price < priceAbove[_orderId] && priceAbove[_orderId] > 0) {
                _conditionsMet = false;
            }
            if (_price > priceBelow[_orderId] && priceBelow[_orderId] > 0) {
                _conditionsMet = false;
            }
        }
        
        return _conditionsMet;
    }

// ----------------------------------------------------------------------------------
// Deletes parameters of cancelled or processed orders
// ----------------------------------------------------------------------------------
    function clearOrderConditions(bytes32 _orderId) internal {
        priceAbove[_orderId] = 0;
        priceBelow[_orderId] = 0;
        goodFrom[_orderId]   = 0;
        goodUntil[_orderId]  = 0;
    }

    function pause() public virtual onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public virtual onlyRole(PAUSER_ROLE) {
        _unpause();
    }

// ----------------------------------------------------------------------------------
// createLiquidationOrder(address _address, bytes32 _marketId)
// Checks if position has been liquidated since last check. Requires gas for callback
// function. Anyone can issue a liquidation order for any other address and market.
// ----------------------------------------------------------------------------------
    function createLiquidationOrder(
        address _address,
        bytes32 _marketId
        ) public whenNotPaused onlyRole(ORACLEOPERATOR_ROLE) payable returns (bytes32 _orderId) {
        if (gasForCallback > 0) {
            require(msg.value >= gasForCallback, "MorpherOracle: Must transfer gas costs for Oracle Callback function.");
            callBackCollectionAddress.transfer(msg.value);
        }
        _orderId = MorpherTradeEngine(state.morpherTradeEngineAddress()).requestOrderId(_address, _marketId, 0, 0, true, 10**8);
        emit LiquidationOrderCreated(_orderId, _msgSender(), _address, _marketId);
        return _orderId;
    }

// ----------------------------------------------------------------------------------
// __callback(bytes32 _orderId, uint256 _price, uint256 _spread, uint256 _liquidationTimestamp, uint256 _timeStamp)
// Called by the oracle operator. Writes price/spread/liquidiation check to the blockchain.
// Trade engine processes the order and updates the portfolio in state if successful.
// ----------------------------------------------------------------------------------
    function __callback(
        bytes32 _orderId,
        uint256 _price,
        uint256 _unadjustedMarketPrice,
        uint256 _spread,
        uint256 _liquidationTimestamp,
        uint256 _timeStamp,
        uint256 _gasForNextCallback
        ) public onlyRole(ORACLEOPERATOR_ROLE) whenNotPaused returns (MorpherTradeEngine.position memory createdPosition)  {
        
        require(checkOrderConditions(_orderId, _price), 'MorpherOracle Error: Order Conditions are not met');
       
       createdPosition = MorpherTradeEngine(state.morpherTradeEngineAddress()).processOrder(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp);
        
        clearOrderConditions(_orderId);
        emit OrderProcessed(
            _orderId,
            _price,
            _unadjustedMarketPrice,
            _spread,
            _liquidationTimestamp,
            _timeStamp,
            createdPosition.longShares,
            createdPosition.shortShares,
            createdPosition.meanEntryPrice,
            createdPosition.meanEntrySpread,
            createdPosition.meanEntryLeverage,
            createdPosition.liquidationPrice
            );
        setGasForCallback(_gasForNextCallback);
        return createdPosition;
    }

// ----------------------------------------------------------------------------------
// delistMarket(bytes32 _marketId)
// Administrator closes out all existing positions on _marketId market at current prices
// ----------------------------------------------------------------------------------

    uint delistMarketFromIx;
    function delistMarket(bytes32 _marketId, bool _startFromScratch) public onlyRole(ADMINISTRATOR_ROLE) {
        require(state.getMarketActive(_marketId) == true, "Market must be active to process position liquidations.");
        // If no _fromIx and _toIx specified, do entire _list
        if (_startFromScratch) {
            delistMarketFromIx = 0;
        }
        
        uint _toIx = MorpherTradeEngine(state.morpherTradeEngineAddress()).getMaxMappingIndex(_marketId);
        
        address _address;
        for (uint256 i = delistMarketFromIx; i <= _toIx; i++) {
             if(gasleft() < 250000 && i != _toIx) { //stop if there's not enough gas to write the next transaction
                delistMarketFromIx = i;
                emit DelistMarketIncomplete(_marketId, _toIx);
                return;
            } 
            
            _address = MorpherTradeEngine(state.morpherTradeEngineAddress()).getExposureMappingAddress(_marketId, i);
            adminLiquidationOrder(_address, _marketId);
            
        }
        emit DelistMarketComplete(_marketId);
    }


// ----------------------------------------------------------------------------------
// adminLiquidationOrder(address _address, bytes32 _marketId)
// Administrator closes out an existing position of _address on _marketId market at current price
// ----------------------------------------------------------------------------------
    function adminLiquidationOrder(
        address _address,
        bytes32 _marketId
        ) public onlyRole(ADMINISTRATOR_ROLE) returns (bytes32 _orderId) {
            MorpherTradeEngine.position memory position = MorpherTradeEngine(state.morpherTradeEngineAddress()).getPosition(_address, _marketId);
            
            if (position.longShares > 0) {
                _orderId = MorpherTradeEngine(state.morpherTradeEngineAddress()).requestOrderId(_address, _marketId, position.longShares, 0, false, 10**8);
                emit AdminLiquidationOrderCreated(_orderId, _address, _marketId, position.longShares, 0, false, 10**8);
            }
            if (position.shortShares > 0) {
                _orderId = MorpherTradeEngine(state.morpherTradeEngineAddress()).requestOrderId(_address, _marketId, position.shortShares, 0, true, 10**8);
                emit AdminLiquidationOrderCreated(_orderId, _address, _marketId, position.shortShares, 0, true, 10**8);
            }
            return _orderId;
    }
    

}

