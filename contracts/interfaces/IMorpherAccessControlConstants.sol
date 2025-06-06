//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.15;

interface IMorpherAccessControlConstants {
    function PROXYUPDATER_ROLE() external view returns (bytes32);
    function ADMINISTRATOR_ROLE() external view returns (bytes32);
    function PAUSER_ROLE() external view returns (bytes32);
    function hasRole(bytes32 role, address account) external view returns (bool);
}
