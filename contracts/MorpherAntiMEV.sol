//SPDX-License-Identifier: MIT

pragma solidity 0.8.11;


import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

/**
 * The idea here is that a sandwich attack is denied by now allowing transfers of tokens for N blocks
 * 
 * It's for very low volume tokens.
 * 
 * It can then only allow 1 transaction per N blocks and deny the rest which makes it unattractive for a sandwich attack.
 * 
 */
abstract contract MorpherAntiMEVUpgradeable is ERC20Upgradeable {
    uint256 nextAllowedBlock;
    uint256 constant NO_TX_FOR_N_BLOCKS = 2;


    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20Upgradeable) {
        require(block.number >= nextAllowedBlock, "MorpherAntiMEV: Transfer denied");

        nextAllowedBlock = block.number + NO_TX_FOR_N_BLOCKS;

        super._beforeTokenTransfer(from, to, amount);
    }


    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
