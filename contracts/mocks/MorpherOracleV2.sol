// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "../../lib/openzeppelin-contracts-upgradable-5/contracts/proxy/utils/UUPSUpgradeable.sol";
import {MorpherAccessControl} from "../MorpherAccessControl.sol";
import {Initializable} from "../../lib/openzeppelin-contracts-upgradable-5/contracts/proxy/utils/Initializable.sol";
import {MorpherState} from "../MorpherState.sol";

// A minimal V2 implementation for upgrade testing.
contract MorpherOracleV2 is Initializable, UUPSUpgradeable {
    uint256 public version;
    MorpherState public state; // Store state for authz

    // Reinitializer gap to match MorpherOracle's initializer history
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // Use a reinitializer with a version number higher than V1's initializer
    function initializeV2(address _stateAddress) public reinitializer(2) {
         state = MorpherState(_stateAddress);
         version = 2;
    }

    function getVersion() public pure returns (uint256) {
        return 2;
    }

    // This MUST match the authorization logic intended for upgrades
    function _authorizeUpgrade(address newImplementation)
        internal
        override
    {
        address accessControlAddress = state.morpherAccessControlAddress();
        require(accessControlAddress != address(0), "V2: AC not set");
        require(
            MorpherAccessControl(accessControlAddress).hasRole(
                MorpherAccessControl(accessControlAddress).PROXYUPDATER_ROLE(),
                msg.sender
            ),
            "V2: Caller is not the proxy updater" // Differentiate revert message
        );
    }
}
