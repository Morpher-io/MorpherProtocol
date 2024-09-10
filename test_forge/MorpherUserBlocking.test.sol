// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "./BaseSetup.sol";
import "../contracts/MorpherUserBlocking.sol";

contract MorpherUserBlockingTest is BaseSetup, MorpherUserBlocking {
	
	address _blocker = address(0xaabbcc);
	address _admin = address(0xffeedd);

	function setUp() public override {
		super.setUp();
		morpherAccessControl.grantRole(ADMINISTRATOR_ROLE, address(_admin));
		morpherAccessControl.grantRole(USERBLOCKINGADMIN_ROLE, address(_blocker));
	}

	function testBlockUser() public {
		address user = address(0x123456);
		bool blocked = morpherUserBlocking.userIsBlocked(user);
		assertEq(blocked, false);

		vm.expectRevert();
		morpherUserBlocking.setUserBlocked(user, true);

		vm.prank(_blocker);
		vm.expectEmit(true, true, true, true);
		emit ChangeUserBlocked(user, false, true);
		morpherUserBlocking.setUserBlocked(user, true);

		blocked = morpherUserBlocking.userIsBlocked(user);
		assertEq(blocked, true);

		vm.prank(_admin);
		vm.expectEmit(true, true, true, true);
		emit ChangeUserBlocked(user, true, false);
		morpherUserBlocking.setUserBlocked(user, false);

		blocked = morpherUserBlocking.userIsBlocked(user);
		assertEq(blocked, false);
	}
}
