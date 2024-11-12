// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "./BaseSetup.sol";
import "../contracts/MorpherAirdrop.sol";

contract MorpherAirdropTest is BaseSetup {
	address _airdropAdmin = address(0x1234);
	address _coldStorageOwner = address(0x5678);

	event AirdropSent(
		address indexed _operator,
		address indexed _recipient,
		uint256 _amountClaimed,
		uint256 _amountAuthorized
	);
	event SetAirdropAuthorized(address indexed _recipient, uint256 _amountClaimed, uint256 _amountAuthorized);
	event Transfer(address indexed from, address indexed to, uint256 value);

	function setUp() public override {
		super.setUp();
		morpherAirdrop = new MorpherAirdrop(_airdropAdmin, address(morpherToken), _coldStorageOwner);
		morpherAccessControl.grantRole(morpherToken.TRANSFER_ROLE(), address(morpherAirdrop));
		morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(this));
		morpherToken.mint(address(morpherAirdrop), 10 ether);
	}

	function testAdminFunctions() public {	
		vm.expectRevert();
		morpherAirdrop.setAirdropAdmin(address(0x11));

		vm.expectRevert();
		morpherAirdrop.setMorpherTokenAddress(address(0x22));

		vm.prank(_coldStorageOwner);
		morpherAirdrop.setAirdropAdmin(address(0x11));

		vm.prank(_coldStorageOwner);
		morpherAirdrop.setMorpherTokenAddress(address(0x22));

		assertEq(morpherAirdrop.airdropAdmin(), address(0x11));
		assertEq(morpherAirdrop.morpherToken(), address(0x22));
	}

	function testCannotReceiveETH() public {
		vm.deal(address(0x11), 1 ether);
		vm.expectRevert();
		payable(morpherAirdrop).call{value: 1 ether}("");
	}

	function testUserClaimAirdrop() public {
		address user = address(0xabcdef);
		vm.prank(_coldStorageOwner);
		vm.expectRevert();
		morpherAirdrop.setAirdropAuthorized(user, 1 ether);

		vm.prank(_airdropAdmin);
		vm.expectEmit(true, true, true, true);
		emit SetAirdropAuthorized(user, 0, 1 ether);
		morpherAirdrop.setAirdropAuthorized(user, 1 ether);

		assertEq(morpherAirdrop.getAirdropAuthorized(user), 1 ether);
		assertEq(morpherAirdrop.getAirdropClaimed(user), 0);
		assertEq(morpherAirdrop.totalAirdropAuthorized(), 1 ether);
		assertEq(morpherAirdrop.totalAirdropClaimed(), 0);

		vm.prank(user);
		vm.expectEmit(true, true, true, true);
		emit Transfer(address(morpherAirdrop), user, 0.5 ether);
		vm.expectEmit(true, true, true, true);
		emit AirdropSent(user, user, 0.5 ether, 1 ether);
		morpherAirdrop.claimSomeAirdrop(0.5 ether);
		assertEq(morpherAirdrop.getAirdropClaimed(user), 0.5 ether);
		assertEq(morpherAirdrop.totalAirdropClaimed(), 0.5 ether);

		vm.prank(user);
		morpherAirdrop.claimAirdrop();
		assertEq(morpherAirdrop.getAirdropAuthorized(user), 1 ether);
		assertEq(morpherAirdrop.getAirdropClaimed(user), 1 ether);
		assertEq(morpherAirdrop.totalAirdropAuthorized(), 1 ether);
		assertEq(morpherAirdrop.totalAirdropClaimed(), 1 ether);
	}

	function testAdminSendAirdrop() public {
		address user = address(0xabcdef);
		
		vm.prank(_airdropAdmin);
		morpherAirdrop.setAirdropAuthorized(user, 1 ether);

		vm.prank(_airdropAdmin);
		vm.expectEmit(true, true, true, true);
		emit Transfer(address(morpherAirdrop), user, 0.5 ether);
		vm.expectEmit(true, true, true, true);
		emit AirdropSent(_airdropAdmin, user, 0.5 ether, 1 ether);
		morpherAirdrop.adminSendSomeAirdrop(user, 0.5 ether);
		assertEq(morpherAirdrop.getAirdropClaimed(user), 0.5 ether);
		assertEq(morpherAirdrop.totalAirdropClaimed(), 0.5 ether);

		vm.prank(_airdropAdmin);
		morpherAirdrop.adminSendAirdrop(user);
		(uint userClaimed, uint userAuthorized) = morpherAirdrop.getAirdrop(user);
		assertEq(userAuthorized, 1 ether);
		assertEq(userClaimed, 1 ether);
		assertEq(morpherAirdrop.totalAirdropAuthorized(), 1 ether);
		assertEq(morpherAirdrop.totalAirdropClaimed(), 1 ether);
	}

	function testAdminAuthorizeAndSendAirdrop() public {
		address user1 = address(0xabc);
		address user2 = address(0xdef);
		
		vm.prank(_airdropAdmin);
		morpherAirdrop.adminAuthorizeAndSend(user1, 2 ether);

		assertEq(morpherAirdrop.getAirdropAuthorized(user1), 2 ether);
		assertEq(morpherAirdrop.getAirdropClaimed(user1), 2 ether);
		assertEq(morpherAirdrop.totalAirdropAuthorized(), 2 ether);
		assertEq(morpherAirdrop.totalAirdropClaimed(), 2 ether);
		
		vm.prank(_airdropAdmin);
		morpherAirdrop.adminAuthorizeAndSend(user2, 3 ether);

		assertEq(morpherAirdrop.getAirdropAuthorized(user2), 3 ether);
		assertEq(morpherAirdrop.getAirdropClaimed(user2), 3 ether);
		assertEq(morpherAirdrop.totalAirdropAuthorized(), 5 ether);
		assertEq(morpherAirdrop.totalAirdropClaimed(), 5 ether);
	}
}
