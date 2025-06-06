//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.15;

interface IMorpherStateForAccessControl {
    function morpherAccessControlAddress() external view returns (address);
    function morpherTradeEngineAddress() external view returns (address); // Keep if MRO gets MTE address via State
    function morpherTokenAddress() external view returns (address); // Keep if MRO gets Token address via State
    function getMarketActive(bytes32 _marketId) external view returns (bool _active); // From base MorpherOracle
}
