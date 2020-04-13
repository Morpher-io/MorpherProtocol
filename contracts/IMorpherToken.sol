pragma solidity >=0.4.25 <0.6.0;

interface IMorpherToken {
    /**
     * Emits a {Transfer} event in ERC-20 token contract.
     */
    function emitTransfer(address _from, address _to, uint256 _amount) external;
}
