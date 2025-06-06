//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.15;

import "./IMorpherTradeEngine.sol"; // Assuming this base interface exists

interface IMorpherTradeEngineExtended is IMorpherTradeEngine {
    function markOrderAsReferred(bytes32 orderId) external;

    function getDeactivatedMarketPrice(bytes32 _marketId) external view returns (uint256); // From base MorpherOracle // Retaining as it's part of extended functionality used by MorpherOracle
    // Note: If getDeactivatedMarketPrice is only used by MorpherOracle and not MRO,
    // it could potentially be moved to a more specific interface or kept if MRO might need it.
    // For now, keeping it as it was present.
}
