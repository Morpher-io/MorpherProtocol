// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "../../lib/openzeppelin-contracts-upgradable-5/contracts/proxy/utils/UUPSUpgradeable.sol";
import {MorpherAccessControl} from "../../contracts/MorpherAccessControl.sol";
import {Initializable} from "../../lib/openzeppelin-contracts-upgradable-5/contracts/proxy/utils/Initializable.sol";

// A minimal V2 implementation for upgrade testing.
// It must inherit UUPSUpgradeable and implement _authorizeUpgrade.
contract MorpherTokenV2 is Initializable, UUPSUpgradeable {
    uint256 public version;
    address public accessControl; // Store AC address for authz

    // Reinitializer gap to match MorpherToken's initializer history
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // Use a reinitializer with a version number higher than V1's initializer
    function initializeV2(address _accessControl) public reinitializer(2) {
         // No need to call __UUPSUpgradeable_init again if inherited storage is sufficient
         accessControl = _accessControl;
         version = 2;
    }

    function getVersion() public pure returns (uint256) {
        return 2;
    }

    // This MUST match the authorization logic intended for upgrades
    function _authorizeUpgrade(address /** unusued */)
        internal
        view
        override
    {
        require(accessControl != address(0), "AC not set");
        require(
            MorpherAccessControl(accessControl).hasRole(
                MorpherAccessControl(accessControl).PROXYUPDATER_ROLE(),
                msg.sender
            ),
            "V2: Caller is not the proxy updater" // Differentiate revert message
        );
    }
}
