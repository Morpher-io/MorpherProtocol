//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.20; // Update pragma if needed

// --- Updated Imports ---
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ContextUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/utils/ContextUpgradeable.sol";
import "./MorpherAccessControl.sol"; // Use adapted v5 interface/contract
import "./MorpherState.sol"; // Use adapted v5 interface/contract


contract MorpherUserBlocking is UUPSUpgradeable, ContextUpgradeable { // --- Inherit UUPSUpgradeable ---

    // --- Remove __gap variable if present ---

    mapping(address => bool) public userIsBlocked;
    MorpherState public state; // Make state public for easier access in modifier/authz

    // Role constants can be fetched from AccessControl if needed, or kept here for clarity
    bytes32 public constant ADMINISTRATOR_ROLE = keccak256("ADMINISTRATOR_ROLE");
    bytes32 public constant USERBLOCKINGADMIN_ROLE = keccak256("USERBLOCKINGADMIN_ROLE");

    event ChangeUserBlocked(address _user, bool _oldIsBlocked, bool _newIsBlocked);
    event ChangedAddressAllowedToAddBlockedUsersAddress(address _oldAddress, address _newAddress); // This event seems unused?

    // --- Initializer ---
    function initialize(address _stateAddress) public initializer {
        __UUPSUpgradeable_init();
        state = MorpherState(_stateAddress);
    }

    // --- Implement _authorizeUpgrade ---
    function _authorizeUpgrade(address /** unused */)
        internal
        view
        override
    {
        address accessControlAddress = state.morpherAccessControlAddress();
        require(accessControlAddress != address(0), "UserBlocking: AccessControl not set");
        // Check if the sender has the PROXYUPDATER_ROLE defined in MorpherAccessControl
        require(
            MorpherAccessControl(accessControlAddress).hasRole(
                MorpherAccessControl(accessControlAddress).PROXYUPDATER_ROLE(), // Get role hash from AC
                _msgSender()
            ),
            "UserBlocking: Caller is not the proxy updater"
        );
    }

    // --- Modifiers (check state and accessControlAddress validity) ---
    modifier onlyAdministrator() {
        address accessControlAddress = state.morpherAccessControlAddress();
        require(accessControlAddress != address(0), "UserBlocking: AccessControl not set");
        require(MorpherAccessControl(accessControlAddress).hasRole(ADMINISTRATOR_ROLE, _msgSender()), "UserBlocking: Only Administrator can call this function");
        _;
    }

    modifier onlyAllowedUsers() {
        address accessControlAddress = state.morpherAccessControlAddress();
        require(accessControlAddress != address(0), "UserBlocking: AccessControl not set");
        require(MorpherAccessControl(accessControlAddress).hasRole(ADMINISTRATOR_ROLE, _msgSender()) || MorpherAccessControl(accessControlAddress).hasRole(USERBLOCKINGADMIN_ROLE, _msgSender()), "UserBlocking: Only White-Listed Users can call this function");
        _;
    }

    function setUserBlocked(address _user, bool _isBlocked) public onlyAllowedUsers {
        emit ChangeUserBlocked(_user, userIsBlocked[_user], _isBlocked);
        userIsBlocked[_user] = _isBlocked;
    }
}
