//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library CheckContract {

    function hasFunction(address _target) public returns (bool) {
        bool success;
        bytes memory data = abi.encodeWithSelector(FUNC_SELECTOR);
    
        assembly {
            success := call(
                gas(),            // gas remaining
                _target,         // destination address
                0,              // no ether
                add(data, 32),  // input buffer (starts after the first 32 bytes in the `data` array)
                mload(data),    // input length (loaded from the first 32 bytes in the `data` array)
                0,              // output buffer
                0               // output length
            )
        }

        return success;
    }
    
}