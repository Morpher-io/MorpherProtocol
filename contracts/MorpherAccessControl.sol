//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.20; // Update pragma if needed

// --- Use v5 imports ---
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/access/AccessControlUpgradeable.sol";

/// @custom:oz-upgrades-from contracts/prev/contracts/MorpherAccessControl.sol:MorpherAccessControl // Keep or update reference
contract MorpherAccessControl is AccessControlUpgradeable, UUPSUpgradeable { // Inherit both

    // --- Define Proxy Updater Role ---
    bytes32 public constant PROXYUPDATER_ROLE = keccak256("PROXYUPDATER_ROLE");

    // --- Remove __gap variable if it existed ---

    // --- Initializer ---
    function initialize() public initializer {
        // Call initializers for all parent contracts
        __AccessControl_init();
        __UUPSUpgradeable_init(); // Initialize UUPS

        // Grant deployer admin role AND proxy updater role
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(PROXYUPDATER_ROLE, _msgSender()); // Grant deployer updater role initially
    }

    // --- Implement _authorizeUpgrade ---
    // Only allow the PROXYUPDATER_ROLE to upgrade this contract
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(PROXYUPDATER_ROLE) // Restrict upgrade permission
    {}

    // --- grantRoleBatch remains the same ---
    function grantRoleBatch(bytes32 role, address[] calldata accounts) public virtual onlyRole(getRoleAdmin(role))  {
        for(uint256 i = 0; i < accounts.length; i++) {
            grantRole(role, accounts[i]);
        }
    }

}
