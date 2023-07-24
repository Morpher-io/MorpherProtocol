//SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

interface CallbackableContract {
    function __callback(uint256, uint256) external;
}