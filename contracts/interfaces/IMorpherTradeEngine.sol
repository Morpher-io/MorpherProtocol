//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.15;

interface IMorpherTradeEngine {
    // This struct must match the one in MorpherTradeEngine.sol
    // as processOrder returns this struct type.
    struct position {
        uint256 lastUpdated;
        uint256 longShares;
        uint256 shortShares;
        uint256 meanEntryPrice;
        uint256 meanEntrySpread;
        uint256 meanEntryLeverage;
        uint256 liquidationPrice;
        bytes32 positionHash;
    }

    function requestOrderId(
        address _address,
        bytes32 _marketId,
        uint256 _closeSharesAmount,
        uint256 _openMPHTokenAmount,
        bool _tradeDirection,
        uint256 _orderLeverage
    ) external returns (bytes32 _orderId);

    function getDeactivatedMarketPrice(bytes32 _marketId) external view returns (uint256);

    function processOrder(
        bytes32 _orderId,
        uint256 _marketPrice,
        uint256 _marketSpread,
        uint256 _liquidationTimestamp,
        uint256 _timeStampInMS 
    ) external returns (position memory createdPosition);

    function getOrder(
        bytes32 _orderId
    ) external view returns (
        address _userId,
        bytes32 _marketId,
        uint256 _closeSharesAmount,
        uint256 _openMPHTokenAmount,
        uint256 _marketPrice,
        uint256 _marketSpread,
        uint256 _orderLeverage
    );
    
    function cancelOrder(bytes32 _orderId, address _address) external;
}
