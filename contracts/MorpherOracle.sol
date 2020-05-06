pragma solidity 0.5.16;

import "./Ownable.sol";
import "./MorpherTradeEngine.sol";

// ----------------------------------------------------------------------------------
// Morpher Oracle contract
// The oracle initates a new trade by calling trade engine and requesting a new orderId.
// An event is fired by the contract notifying the oracle operator to query a price/liquidation unchecked
// for a market/user and return the information via the callback function. Since calling
// the callback function requires gas, the user must send a fixed amount of Ether when
// creating their order.
// ----------------------------------------------------------------------------------

contract MorpherOracle is Ownable {

    MorpherTradeEngine tradeEngine;

    bool public paused;

    uint256 public gasForCallback;
    address payable public callBackCollectionAddress;

    mapping(address => bool) public callBackAddress;

// ----------------------------------------------------------------------------------
// Events
// ----------------------------------------------------------------------------------
    event OrderCreated(
        bytes32 indexed _orderId,
        address indexed _address,
        bytes32 indexed _marketId,
        bool _tradeAmountGivenInShares,
        uint256 _tradeAmount,
        bool _tradeDirection,
        uint256 _orderLeverage
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
        bool _tradeAmountGivenInShares,
        uint256 _tradeAmount,
        bool _tradeDirection,
        uint256 _orderLeverage
        );

    event OrderCancelled(
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

    modifier onlyOracleOperator {
        require(isCallbackAddress(msg.sender), "MorpherOracle: Only the oracle operator can call this function.");
        _;
    }

    modifier notPaused {
        require(paused == false, "MorpherOracle: Oracle paused, aborting");
        _;
    }

   constructor(address _tradeEngineAddress, address _callBackAddress, address payable _gasCollectionAddress, uint256 _gasForCallback, address _coldStorageOwnerAddress) public {
        setTradeEngineAddress(_tradeEngineAddress);
        enableCallbackAddress(_callBackAddress);
        setCallbackCollectionAddress(_gasCollectionAddress);
        setGasForCallback(_gasForCallback);
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

    function setGasForCallback(uint256 _gasForCallback) public onlyOwner {
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

// ----------------------------------------------------------------------------------
// emitOrderFailed
// Can be called by Oracle Operator to notifiy user of failed order
// ----------------------------------------------------------------------------------
    function emitOrderFailed(
        bytes32 _orderId,
        address _address,
        bytes32 _marketId,
        bool _tradeAmountGivenInShares,
        uint256 _tradeAmount,
        bool _tradeDirection,
        uint256 _orderLeverage
    ) public onlyOracleOperator {
        emit OrderFailed(
            _orderId,
            _address,
            _marketId,
            _tradeAmountGivenInShares,
            _tradeAmount,
            _tradeDirection,
            _orderLeverage);
    }

// ----------------------------------------------------------------------------------
// createOrder(bytes32  _marketId, bool _tradeAmountGivenInShares, uint256 _tradeAmount, bool _tradeDirection, uint256 _orderLeverage)
// Request a new orderId from trade engine and fires event for price/liquidation check request.
// ----------------------------------------------------------------------------------
    function createOrder(
        bytes32 _marketId,
        bool _tradeAmountGivenInShares,
        uint256 _tradeAmount,
        bool _tradeDirection,
        uint256 _orderLeverage
        ) public payable notPaused returns (bytes32 _orderId) {
        if (gasForCallback > 0) {
            require(msg.value >= gasForCallback, "MorpherOracle: Must transfer gas costs for Oracle Callback function.");
            callBackCollectionAddress.transfer(msg.value);
        }
        _orderId = tradeEngine.requestOrderId(msg.sender, _marketId, _tradeAmountGivenInShares, _tradeAmount, _tradeDirection, _orderLeverage);
        emit OrderCreated(
            _orderId,
            msg.sender,
            _marketId,
            _tradeAmountGivenInShares,
            _tradeAmount,
            _tradeDirection,
            _orderLeverage
            );
        return _orderId;
    }

// ----------------------------------------------------------------------------------
// cancelOrder(bytes32  _orderId)
// Users can cancel their own orders before the _callback has been executed
// ----------------------------------------------------------------------------------
    function cancelOrder(bytes32 _orderId) public {
        tradeEngine.cancelOrder(_orderId, msg.sender);
        emit OrderCancelled(
            _orderId,
            msg.sender
            );
    }

// ----------------------------------------------------------------------------------
// Setter/getter functions for pausing the Oracle contract
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
        ) public notPaused payable returns (bytes32 _orderId) {
        if (gasForCallback > 0) {
            require(msg.value >= gasForCallback, "MorpherOracle: Must transfer gas costs for Oracle Callback function.");
            callBackCollectionAddress.transfer(msg.value);
        }
        _orderId = tradeEngine.requestOrderId(_address, _marketId, true, 0, true, 10**8);
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
        uint256 _spread,
        uint256 _liquidationTimestamp,
        uint256 _timeStamp
        ) public onlyOracleOperator notPaused returns (uint256 _newLongShares, uint256 _newShortShares, uint256 _newMeanEntry, uint256 _newMeanSpread, uint256 _newMeanLeverage, uint256 _liquidationPrice)  {
        (
            _newLongShares,
            _newShortShares,
            _newMeanEntry,
            _newMeanSpread,
            _newMeanLeverage,
            _liquidationPrice
        ) = tradeEngine.processOrder(_orderId, _price, _spread, _liquidationTimestamp, _timeStamp);
        emit OrderProcessed(
            _orderId,
            _price,
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
        return (_newLongShares, _newShortShares, _newMeanEntry, _newMeanSpread, _newMeanLeverage, _liquidationPrice);
    }

// ----------------------------------------------------------------------------------
// Auxiliary function to hash a string market name i.e.
// "CRYPTO_BTC" => 0x0bc89e95f9fdaab7e8a11719155f2fd638cb0f665623f3d12aab71d1a125daf9;
// ----------------------------------------------------------------------------------
    function stringToHash(string memory _source) public pure returns (bytes32 _result) {
        return keccak256(abi.encodePacked(_source));
    }
}
