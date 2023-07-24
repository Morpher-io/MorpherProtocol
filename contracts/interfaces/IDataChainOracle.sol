//SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

interface IDataChainOracle {
    function getTotalPriceForRequestedProviders(address[] memory requestedProviders) external view returns(uint);
    function getOracleData(uint256 requestId, bytes32 identifier, address[] memory requestedProviders) external payable;
}