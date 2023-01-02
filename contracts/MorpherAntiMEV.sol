//SPDX-License-Identifier: MIT

pragma solidity 0.8.11;


import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

/**
 * The idea here is that a sandwich attack is denied by not allowing a different tx.gasprice in the same block
 * 
 * Sandwich attachs usually work this way:
 * 
 * TX1: Malicious BUY 1000 Token @ 123 price
 * TX2: Rightfully BUY 1000 Token @ 123 + TX1 slippaged price
 * TX3: Malicious SELL 1000 Token @ 123 + TX2 slippage buy
 * 
 * resulting in a sell at an increased price.
 * 
 * The idea is to allow only 1 tx with the same from or to address in the same block to make a transfer
 * 
 * It's for small volume tokens only who are suffering from sandwich attacks
 * 
 */
abstract contract MorpherAntiMEVUpgradeable is ERC20Upgradeable {
    mapping(uint256 => mapping(address => uint256)) gasPerBlockAddress;


    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20Upgradeable) {
        require((gasPerBlockAddress[block.number][from] == 0 || gasPerBlockAddress[block.number][from] == tx.gasprice) && (gasPerBlockAddress[block.number][to] == 0 || gasPerBlockAddress[block.number][to] == tx.gasprice), "MorpherAntiMEV: Transfer denied");

        gasPerBlockAddress[block.number][from] = tx.gasprice;
        gasPerBlockAddress[block.number][to] = tx.gasprice;

        super._beforeTokenTransfer(from, to, amount);
    }


    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
