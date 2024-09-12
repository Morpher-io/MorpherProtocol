// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "./BaseSetup.sol";

contract MorpherAccessControlBaseTest is BaseSetup {

    function setUp() public override {
        super.setUp();
    }

    function testHasRole() public {
        assertEq(
            morpherAccessControl.hasRole(
                morpherState.ADMINISTRATOR_ROLE(),
                address(this)
            ),
            false
        );

        morpherAccessControl.grantRole(
            morpherState.ADMINISTRATOR_ROLE(),
            address(this)
        );

        assertEq(
            morpherAccessControl.hasRole(
                morpherState.ADMINISTRATOR_ROLE(),
                address(this)
            ),
            true
        );
    }
}
