//SPDX-License-Identifier: GPLv3
pragma solidity =0.8.15;

import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";

/// @custom:oz-upgrades-from contracts/prev/contracts/MorpherAccessControl.sol:MorpherAccessControl
contract MorpherAccessControl is AccessControlEnumerableUpgradeable {

    function initialize() public initializer {
        AccessControlEnumerableUpgradeable.__AccessControlEnumerable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

}
