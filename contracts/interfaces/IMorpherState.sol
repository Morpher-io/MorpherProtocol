//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.15;

interface IMorpherState {
    function morpherAccessControlAddress() external view returns (address);
    function morpherTradeEngineAddress() external view returns (address);
    function morpherTokenAddress() external view returns (address);
    function getMarketActive(bytes32 _marketId) external view returns (bool _active);
}
