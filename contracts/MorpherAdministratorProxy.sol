pragma solidity 0.5.16;

import "./Ownable.sol";

contract MorpherAdministratorProxy is Ownable {

    address public morpherStateAddress;

    constructor(address _morpherAdministrator, address _morpherStateAddress) public {
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

    function () external payable onlyOwner {
        (bool success, ) = morpherStateAddress.call.value(msg.value)(msg.data);
        require(success, "MorpherAdministratorProxy: Failed to forward call");
    }
}