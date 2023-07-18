//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Array function to delete element at index and re-organize the array
// so that there are no gaps between the elements.
library Array {
    function remove(uint[] storage arr, uint index) public {
        // Move the last element into the place to delete
        require(arr.length > 0, "Can't remove from empty array");
        arr[index] = arr[arr.length - 1];
        arr.pop();
    }

    function remove(address[] storage arr, uint index) public {
        // Move the last element into the place to delete
        require(arr.length > 0, "Can't remove from empty array");
        arr[index] = arr[arr.length - 1];
        arr.pop();
    }

    function indexOf(address[] storage arr, address elem) public view returns(uint) {
        for(uint i = 0; i < arr.length; i++) {
            if(arr[i] == elem) {
                return i;
            }
        }
        
        revert("Element not found in Array");
    }
    
    function includes(address[] storage arr, address elem) public view returns(bool) {
        for(uint i = 0; i < arr.length; i++) {
            if(arr[i] == elem) {
                return true;
            }
        }
        
        return false;
    }
}