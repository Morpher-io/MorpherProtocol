//SPDX-License-Identifier: GPLv3
pragma solidity 0.8.11;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./MorpherState.sol";


contract MorpherUserBlocking is Initializable {

    mapping(address => bool) public userIsBlocked;
    MorpherState state;

    address public allowedToAddBlockedUsersAddress;

    event ChangeUserBlocked(address _user, bool _oldIsBlocked, bool _newIsBlocked);
    event ChangedAddressAllowedToAddBlockedUsersAddress(address _oldAddress, address _newAddress);

    function initialize(address _state, address _allowedToAddBlockedUsersAddress) public initializer {
        state = MorpherState(_state);
        emit ChangedAddressAllowedToAddBlockedUsersAddress(address(0), _allowedToAddBlockedUsersAddress);
        allowedToAddBlockedUsersAddress = _allowedToAddBlockedUsersAddress;
    }

    modifier onlyAdministrator() {
        require(msg.sender == state.getAdministrator(), "UserBlocking: Only Administrator can call this function");
        _;
    }

    modifier onlyAllowedUsers() {
        require(msg.sender == state.getAdministrator() || msg.sender == allowedToAddBlockedUsersAddress, "UserBlocking: Only White-Listed Users can call this function");
        _;
    }

    function setAllowedToAddBlockedUsersAddress(address _newAddress) public onlyAdministrator {
        emit ChangedAddressAllowedToAddBlockedUsersAddress(allowedToAddBlockedUsersAddress, _newAddress);
        allowedToAddBlockedUsersAddress = _newAddress;
    }

    function setUserBlocked(address _user, bool _isBlocked) public onlyAllowedUsers {
        emit ChangeUserBlocked(_user, userIsBlocked[_user], _isBlocked);
        userIsBlocked[_user] = _isBlocked;
    }
}