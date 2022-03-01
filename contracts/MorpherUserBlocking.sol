pragma solidity 0.5.16;

import "./MorpherState.sol";


contract MorpherUserBlocking {
    mapping(address => bool) public userIsBlocked;
    MorpherState state;

    address public allowedToAddBlockedUsersAddress;

    event ChangeUserBlocked(address _user, bool _oldIsBlocked, bool _newIsBlocked);
    event ChangedAddressAllowedToAddBlockedUsersAddress(address _oldAddress, address _newAddress);

    constructor(address _state, address _allowedToAddBlockedUsersAddress) public {
        state = MorpherState(_state);
        emit ChangedAddressAllowedToAddBlockedUsersAddress(address(0), _allowedToAddBlockedUsersAddress);
        allowedToAddBlockedUsersAddress = _allowedToAddBlockedUsersAddress;
    }

    modifier onlyAdministrator() {
        require(msg.sender == state.getAdministrator(), "UserBlocking: Only Administrator can call this function");
        _;
    }

    function setAllowedToAddBlockedUsersAddress(address _newAddress) public onlyAdministrator {
        emit ChangedAddressAllowedToAddBlockedUsersAddress(allowedToAddBlockedUsersAddress, _newAddress);
        allowedToAddBlockedUsersAddress = _newAddress;
    }

    function setUserBlocked(address _user, bool _isBlocked) public onlyAdministrator {
        emit ChangeUserBlocked(_user, userIsBlocked[_user], _isBlocked);
        userIsBlocked[_user] = _isBlocked;
    }
}