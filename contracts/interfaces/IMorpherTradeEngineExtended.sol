//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.15;

import "./IMorpherTradeEngine.sol"; // Assuming this base interface exists

interface IMorpherTradeEngineExtended is IMorpherTradeEngine {
    struct CreateOrderParams { // Replicating for clarity, could be imported if visible
        bytes32 _marketId;
        uint256 _closeSharesAmount;
        uint256 _openMPHTokenAmount;
        bool _tradeDirection;
        uint256 _orderLeverage;
        uint256 _onlyIfPriceAbove;
        uint256 _onlyIfPriceBelow;
        uint256 _goodUntil;
        uint256 _goodFrom;
    }

    function requestReferredOrderId(
        address trader,
        CreateOrderParams calldata params,
        address beneficiaryAddress
    ) external returns (bytes32 orderId);

    function getDeactivatedMarketPrice(bytes32 _marketId) external view returns (uint256); // From base MorpherOracle
}
