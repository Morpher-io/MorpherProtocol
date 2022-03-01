//SPDX-License-Identifier: GPLv3
pragma solidity 0.8.10;

import "./MorpherState.sol";


contract MorpherUserBlocking {
    mapping(address => bool) public userIsBlocked;
    MorpherState state;

    event ChangeUserBlocked(address _user, bool _oldIsBlocked, bool _newIsBlocked);

    constructor(address _state) {
        state = MorpherState(_state);
    }

    modifier onlyAdministrator() {
        require(msg.sender == state.getAdministrator(), "UserBlocking: Only Administrator can call this function");
        _;
    }

    function setUserBlocked(address _user, bool _isBlocked) public onlyAdministrator {
        emit ChangeUserBlocked(_user, userIsBlocked[_user], _isBlocked);
        userIsBlocked[_user] = _isBlocked;
    }
}