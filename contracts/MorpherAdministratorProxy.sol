//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";

contract MorpherAdministratorProxy is Ownable {

    address public morpherStateAddress;

    constructor(address _morpherAdministrator, address _morpherStateAddress) Ownable() {
        transferOwnership(_morpherAdministrator);
        morpherStateAddress = _morpherStateAddress;
        
    }

    function bulkActivateMarkets(bytes32[] memory _marketHashes) public onlyOwner {
        for(uint i = 0; i < _marketHashes.length; i++) {
            bytes memory payload = abi.encodeWithSignature("activateMarket(bytes32)", _marketHashes[i]);
            (bool success, ) = morpherStateAddress.call(payload);
            require(success,  "MorpherAdministratorProxy: Failed to activate Market");
        }
    }

    fallback() external payable onlyOwner {
        (bool success, ) = morpherStateAddress.call{value: msg.value}(msg.data);
        require(success, "MorpherAdministratorProxy: Failed to forward call");
    }
    receive() external payable onlyOwner {
        revert("MorpherAdministratorProxy: No ETH transfers supported");
    }
}