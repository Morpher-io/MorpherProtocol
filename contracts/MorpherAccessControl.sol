//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.11;

import "../lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlEnumerableUpgradeable.sol";

/// @custom:oz-upgrades-from contracts/prev/contracts/MorpherAccessControl.sol:MorpherAccessControl
contract MorpherAccessControl is AccessControlEnumerableUpgradeable {

    function initialize() public initializer {
        AccessControlEnumerableUpgradeable.__AccessControlEnumerable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function grantRoleBatch(bytes32 role, address[] calldata accounts) public onlyRole(getRoleAdmin(role))  {
        for(uint256 i = 0; i < accounts.length; i++) {
            grantRole(role, accounts[i]);
        }
    }

}
