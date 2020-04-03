pragma solidity 0.5.16;

interface IMorpherToken {
    /**
     * Emits a {Transfer} event in ERC-20 token contract.
     */
    function emitTransfer(address _from, address _to, uint256 _amount) external;
}
