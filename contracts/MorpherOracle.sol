pragma solidity 0.5.16;

import "./Ownable.sol";
import "./MorpherTradeEngine.sol";
import "./MorpherState.sol";
import "./SafeMath.sol";
import "./MorpherPoolShareManager.sol";

// ----------------------------------------------------------------------------------
// Morpher Oracle contract v 2.0
// The oracle initates a new trade by calling trade engine and requesting a new orderId.
// An event is fired by the contract notifying the oracle operator to query a price/liquidation unchecked
// for a market/user and return the information via the callback function. Since calling
// the callback function requires gas, the user must send a fixed amount of Ether when
// creating their order.
// ----------------------------------------------------------------------------------

contract MorpherOracle is Ownable {

    MorpherTradeEngine tradeEngine;
    MorpherState state; // read only, Oracle doesn't need writing access to state
    MorpherPoolShareManager psManager;

    using SafeMath for uint256;

    bool public paused;
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
 * User deposits => userPaidBNB + deposit => gets AAPL
 * User converts AAPL back to BNB: userRetrievableBNB + withdrawal Amount
 * User withdraws BNB: userRetrievedBNB + BNB
 * Total Realized Return: userRetrievedBNB - userPaidBNB / userPaidBNB (or so)

 NOT IN USE YET
 */
    uint256 public balanceBNB;
    mapping(address => uint256) public userPaidBNB;
    mapping(address => uint256) public userRetrievableBNB;
    mapping(address => uint256) public userRetrievedBNB;

// ----------------------------------------------------------------------------------
// Events
// ----------------------------------------------------------------------------------
    event OrderCreated(
        bytes32 indexed _orderId,
        address indexed _address,
        bytes32 indexed _marketId,
        uint256 _closeSharesAmount,
        uint256 _openBNBAmount,
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


    modifier onlyOracleOperator {
        require(isCallbackAddress(msg.sender), "MorpherOracle: Only the oracle operator can call this function.");
        _;
    }

    modifier onlyAdministrator {
        require(msg.sender == state.getAdministrator(), "Function can only be called by the Administrator.");
        _;
    }

    modifier notPaused {
        require(paused == false, "MorpherOracle: Oracle paused, aborting");
        _;
    }

   constructor(address _tradeEngineAddress, address _morpherState, address _callBackAddress, address payable _gasCollectionAddress, uint256 _gasForCallback, address _coldStorageOwnerAddress, address _morpherPoolShareManagerAddress) public {
        setTradeEngineAddress(_tradeEngineAddress);
        setStateAddress(_morpherState);
        enableCallbackAddress(_callBackAddress);
        setCallbackCollectionAddress(_gasCollectionAddress);
        setGasForCallback(_gasForCallback);
        psManager = MorpherPoolShareManager(_morpherPoolShareManagerAddress);
        transferOwnership(_coldStorageOwnerAddress);
    }

// ----------------------------------------------------------------------------------
// Setter/getter functions for trade engine address, oracle operator (callback) address,
// and prepaid gas limit for callback function
// ----------------------------------------------------------------------------------
    function setTradeEngineAddress(address _address) public onlyOwner {
        tradeEngine = MorpherTradeEngine(_address);
        emit LinkTradeEngine(_address);
    }

    function setStateAddress(address _address) public onlyOwner {
        state = MorpherState(_address);
        emit LinkMorpherState(_address);
    }

    function overrideGasForCallback(uint256 _gasForCallback) public onlyOwner {
        gasForCallback = _gasForCallback;
        emit SetGasForCallback(_gasForCallback);
    }
    
    function setGasForCallback(uint256 _gasForCallback) private {
        gasForCallback = _gasForCallback;
        emit SetGasForCallback(_gasForCallback);
    }

    function enableCallbackAddress(address _address) public onlyOwner {
        callBackAddress[_address] = true;
        emit CallbackAddressEnabled(_address);
    }

    function disableCallbackAddress(address _address) public onlyOwner {
        callBackAddress[_address] = false;
        emit CallbackAddressDisabled(_address);
    }

    function isCallbackAddress(address _address) public view returns (bool _isCallBackAddress) {
        return callBackAddress[_address];
    }

    function setCallbackCollectionAddress(address payable _address) public onlyOwner {
        callBackCollectionAddress = _address;
        emit CallBackCollectionAddressChange(_address);
    }

    function getAdministrator() public view returns(address _administrator) {
        return state.getAdministrator();
    }

// ----------------------------------------------------------------------------------
// Oracle Owner can use a whitelist and authorize individual addresses
// ----------------------------------------------------------------------------------
    function setUseWhiteList(bool _useWhiteList) public onlyOracleOperator {
        require(false, "MorpherOracle: Cannot use this functionality in the oracle at the moment");
        useWhiteList = _useWhiteList;
        emit SetUseWhiteList(_useWhiteList);
    }

    function setWhiteList(address _whiteList) public onlyOracleOperator {
        whiteList[_whiteList] = true;
        emit AddressWhiteListed(_whiteList);
    }

    function setBlackList(address _blackList) public onlyOracleOperator {
        whiteList[_blackList] = false;
        emit AddressBlackListed(_blackList);
    }

    function isWhiteListed(address _address) public view returns (bool _whiteListed) {
        if (useWhiteList == false ||  whiteList[_address] == true) {
            _whiteListed = true;
        }
        return(_whiteListed);
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
    ) public onlyOracleOperator {
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
        bool _tradeDirection,
        uint256 _orderLeverage,
        uint256 _onlyIfPriceAbove,
        uint256 _onlyIfPriceBelow,
        uint256 _goodUntil,
        uint256 _goodFrom
        ) public payable notPaused returns (bytes32 _orderId) {
        require(isWhiteListed(msg.sender),"MorpherOracle: Address not eligible to create an order.");
        if (gasForCallback > 0) {
            require(msg.value >= gasForCallback, "MorpherOracle: Must transfer gas costs for Oracle Callback function.");
            callBackCollectionAddress.transfer(gasForCallback);
        }
        //openBNBAmount and extend order struct
        _orderId = tradeEngine.requestOrderId(msg.sender, _marketId, _closeSharesAmount, msg.value.sub(gasForCallback), _tradeDirection, _orderLeverage);
        

        //if the market was deactivated, and the trader didn't fail yet, then we got an orderId to close the position with a locked in price
        if(state.getMarketActive(_marketId) == false) {

            //price will come from the position where price is stored forever
            tradeEngine.processOrder(_orderId, tradeEngine.getDeactivatedMarketPrice(_marketId), 0, 0, now.mul(1000));
            
            emit OrderProcessed(
                _orderId,
                tradeEngine.getDeactivatedMarketPrice(_marketId),
                0,
                0,
                0,
                now.mul(1000),
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
                msg.sender,
                _marketId,
                _closeSharesAmount,
                msg.value.sub(gasForCallback),
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
        require(orderCancellationRequested[_orderId] == false, "MorpherOracle: Order was already canceled.");
        (address userId, , , , , , ) = tradeEngine.getOrder(_orderId);
        require(userId == msg.sender, "MorpherOracle: Only the user can request an order cancellation.");
        orderCancellationRequested[_orderId] = true;
        emit OrderCancellationRequestedEvent(_orderId, msg.sender);

    }
    // ----------------------------------------------------------------------------------
    // cancelOrder(bytes32  _orderId)
    // User or Administrator can cancel their own orders before the _callback has been executed
    // ----------------------------------------------------------------------------------
    function cancelOrder(bytes32 _orderId) public onlyOracleOperator {
        require(orderCancellationRequested[_orderId] == true, "MorpherOracle: Order-Cancellation was not requested.");
        (address userId, , , , , , ) = tradeEngine.getOrder(_orderId);
        tradeEngine.cancelOrder(_orderId, userId);
        clearOrderConditions(_orderId);
        emit OrderCancelled(
            _orderId,
            userId,
            msg.sender
            );
    }
    
    // ----------------------------------------------------------------------------------
    // adminCancelOrder(bytes32  _orderId)
    // Administrator can cancel before the _callback has been executed to provide an updateOrder functionality
    // ----------------------------------------------------------------------------------
    function adminCancelOrder(bytes32 _orderId) public onlyOracleOperator {
        (address userId, , , , , , ) = tradeEngine.getOrder(_orderId);
        tradeEngine.cancelOrder(_orderId, userId);
        clearOrderConditions(_orderId);
        emit AdminOrderCancelled(
            _orderId,
            userId,
            msg.sender
            );
    }

// ------------------------------------------------------------------------
// checkOrderConditions(bytes32 _orderId, uint256 _price)
// Checks if callback satisfies the order conditions
// ------------------------------------------------------------------------
    function checkOrderConditions(bytes32 _orderId, uint256 _price) public view returns (bool _conditionsMet) {
        _conditionsMet = true;
        if (now > goodUntil[_orderId] && goodUntil[_orderId] > 0) {
            _conditionsMet = false;
        }
        if (now < goodFrom[_orderId] && goodFrom[_orderId] > 0) {
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

// ----------------------------------------------------------------------------------
// Pausing/unpausing the Oracle contract
// ----------------------------------------------------------------------------------
    function pauseOracle() public onlyOwner {
        paused = true;
        emit OraclePaused(true);
    }

    function unpauseOracle() public onlyOwner {
        paused = false;
        emit OraclePaused(false);
    }

// ----------------------------------------------------------------------------------
// createLiquidationOrder(address _address, bytes32 _marketId)
// Checks if position has been liquidated since last check. Requires gas for callback
// function. Anyone can issue a liquidation order for any other address and market.
// ----------------------------------------------------------------------------------
    function createLiquidationOrder(
        address _address,
        bytes32 _marketId
        ) public notPaused onlyOracleOperator payable returns (bytes32 _orderId) {
        if (gasForCallback > 0) {
            require(msg.value >= gasForCallback, "MorpherOracle: Must transfer gas costs for Oracle Callback function.");
            callBackCollectionAddress.transfer(msg.value);
        }
        _orderId = tradeEngine.requestOrderId(_address, _marketId, 0, 0, true, 10**8);
        emit LiquidationOrderCreated(_orderId, msg.sender, _address, _marketId);
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
        uint256 _gasForNextCallback,
        uint256 _totalPoolShares,
        uint256 _lastKnownTxCountToBackend
        ) public onlyOracleOperator notPaused {
        
        require(checkOrderConditions(_orderId, _price), 'MorpherOracle Error: Order Conditions are not met');
       
        //mint the tokenAmount based on BNB and totalPoolShares
        //update the order object with _openMPHTokenAmount
        //fire a deposit event if mphTokenAmount > 0
        mintAndSetPoolShares(_orderId, _totalPoolShares, _lastKnownTxCountToBackend);

        //stack too deep
        runCallback(_orderId, _price, _unadjustedMarketPrice, _spread, _liquidationTimestamp, _timeStamp);

        //convert all available MPH/PS from user to BNB based on _totalPoolShares
        //stack to deep
        payoutBNB(_orderId, _totalPoolShares, _lastKnownTxCountToBackend);
        
        clearOrderConditions(_orderId);
        
        setGasForCallback(_gasForNextCallback);

    }

    function mintAndSetPoolShares(bytes32 _orderId, uint _totalPoolShares, uint _lastKnownTxCountToBackend) private {
        (address userId, , , , , , ) = tradeEngine.getOrder(_orderId);
        uint mphPoolShareAmount = psManager.mintPoolShares(userId, _totalPoolShares, _lastKnownTxCountToBackend, tradeEngine.getOpenBNBAmount(_orderId));
        tradeEngine.setOpenMPHAmount(_orderId, mphPoolShareAmount);
    }

    function runCallback(bytes32 _orderId,
        uint256 _price,
        uint256 _unadjustedMarketPrice,
        uint256 _spread,
        uint256 _liquidationTimestamp,
        uint256 _timeStamp) private {
(
                uint _newLongShares,
                uint _newShortShares,
                uint _newMeanEntry,
                uint _newMeanSpread,
                uint _newMeanLeverage,
                uint _liquidationPrice
            ) = tradeEngine.processOrder(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp);
            emit OrderProcessed(
                _orderId,
                _price,
                _unadjustedMarketPrice,
                _spread,
                _liquidationTimestamp,
                _timeStamp,
                _newLongShares,
                _newShortShares,
                _newMeanEntry,
                _newMeanSpread,
                _newMeanLeverage,
                _liquidationPrice
                );

        }

    function payoutBNB(bytes32 _orderId, uint256 _totalPoolShares, uint256 _lastKnownTxCountToBackend) private {
        (address userId, , , , , , ) = tradeEngine.getOrder(_orderId);
        uint256 bnbAmount = psManager.burnPoolShares(userId, _totalPoolShares, _lastKnownTxCountToBackend);
        address payable payoutAddress = address(uint160(userId));
        payoutAddress.transfer(bnbAmount);
    }

// ----------------------------------------------------------------------------------
// delistMarket(bytes32 _marketId)
// Administrator closes out all existing positions on _marketId market at current prices
// ----------------------------------------------------------------------------------

    uint delistMarketFromIx = 0;
    function delistMarket(bytes32 _marketId, bool _startFromScratch) public onlyAdministrator {
        require(state.getMarketActive(_marketId) == true, "Market must be active to process position liquidations.");
        // If no _fromIx and _toIx specified, do entire _list
        if (_startFromScratch) {
            delistMarketFromIx = 0;
        }
        
        uint _toIx = state.getMaxMappingIndex(_marketId);
        
        address _address;
        for (uint256 i = delistMarketFromIx; i <= _toIx; i++) {
             if(gasleft() < 250000 && i != _toIx) { //stop if there's not enough gas to write the next transaction
                delistMarketFromIx = i;
                emit DelistMarketIncomplete(_marketId, _toIx);
                return;
            } 
            
            _address = state.getExposureMappingAddress(_marketId, i);
            adminLiquidationOrder(_address, _marketId);
            
        }
        emit DelistMarketComplete(_marketId);
    }

    /**
     * Course of action would be:
     * 1. de-activate market through state
     * 2. set the Deactivated Market Price
     * 3. let users still close their positions
     */
    function setDeactivatedMarketPrice(bytes32 _marketId, uint256 _price) public onlyAdministrator {
        tradeEngine.setDeactivatedMarketPrice(_marketId, _price);
        emit LockedPriceForClosingPositions(_marketId, _price);

    }

// ----------------------------------------------------------------------------------
// adminLiquidationOrder(address _address, bytes32 _marketId)
// Administrator closes out an existing position of _address on _marketId market at current price
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
// Auxiliary function to hash a string market name i.e.
// "CRYPTO_BTC" => 0x0bc89e95f9fdaab7e8a11719155f2fd638cb0f665623f3d12aab71d1a125daf9;
// ----------------------------------------------------------------------------------
    function stringToHash(string memory _source) public pure returns (bytes32 _result) {
        return keccak256(abi.encodePacked(_source));
    }
}
