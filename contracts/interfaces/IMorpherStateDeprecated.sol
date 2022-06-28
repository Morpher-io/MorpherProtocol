//SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

interface IMorpherStateDeprecated {
    function transfer(address from, address to, uint amount) external;
    function mint(address to, uint amount) external;
    function burn(address from, uint amount) external;

}