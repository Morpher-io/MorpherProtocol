//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.15;

interface IMorpherReferralOracle {
    function recordReferralOpen(
        bytes32 orderId,
        address traderAddress,
        bytes32 marketId,
        uint256 initialInvestmentValue
    ) external;

    function processReferralClose(
        address traderAddress,
        bytes32 marketId,
        uint256 finalPayoutValue
    ) external;
}
