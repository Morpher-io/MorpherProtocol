// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "./BaseSetup.sol";
import "../contracts/MorpherAirdrop.sol"; // Use V5 contract
// --- V5 Imports ---
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
// Remove Transparent Proxy imports
// import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
// import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract MorpherAirdropTest is BaseSetup {
	address _airdropAdmin = address(0x1234); // Address granted AIRDROPADMIN_ROLE
	address _coldStorageOwner = address(0x5678); // Address set as Ownable owner

	// Remove ProxyAdmin, implementation, proxy variables
	// ProxyAdmin proxyAdmin;
	// MorpherAirdrop implementation;
	// TransparentUpgradeableProxy proxy;
	// MorpherAirdrop wrappedProxy; // Use morpherAirdrop from BaseSetup

	event AirdropSent(
		address indexed _operator,
		address indexed _recipient,
		uint256 _amountClaimed,
		uint256 _amountAuthorized
	);
	event SetAirdropAuthorized(address indexed _recipient, uint256 _amountClaimed, uint256 _amountAuthorized);
	event Transfer(address indexed from, address indexed to, uint256 value);

	function setUp() public override {
		// BaseSetup already deploys implementations, including MorpherAirdrop
		// We need to override the deployment in BaseSetup to use UUPS proxy
		// OR deploy it here separately. Let's deploy separately for clarity.

		// Call BaseSetup first to get dependencies (State, Token, AccessControl)
		super.setUp();

		// 1. Deploy Implementation
		MorpherAirdrop airdropImpl = new MorpherAirdrop();

		// 2. Encode V5 initialization data (state, token, owner)
		bytes memory initData = abi.encodeCall(
			MorpherAirdrop.initialize,
			(address(morpherState), address(morpherToken), _coldStorageOwner)
		);

		// 3. Deploy UUPS Proxy using UnsafeUpgrades
		address airdropProxyAddress = UnsafeUpgrades.deployUUPSProxy(address(airdropImpl), initData);

		// 4. Set the morpherAirdrop variable used in tests
		morpherAirdrop = MorpherAirdrop(payable(airdropProxyAddress));

		// 5. Setup permissions
		// Grant AIRDROPADMIN_ROLE (on AccessControl) to the designated admin address
		morpherAccessControl.grantRole(morpherAirdrop.AIRDROPADMIN_ROLE(), _airdropAdmin);
		// Grant AIRDROPADMIN_ROLE (on Token) to the Airdrop contract proxy itself
		morpherAccessControl.grantRole(morpherToken.AIRDROPADMIN_ROLE(), airdropProxyAddress);
		// Grant MINTER_ROLE to test contract for initial funding
		morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(this));
		// Fund the Airdrop proxy
		morpherToken.mint(airdropProxyAddress, 10 ether);
		// Revoke minter role if not needed elsewhere
		morpherAccessControl.revokeRole(morpherToken.MINTER_ROLE(), address(this));
	}

	function testAdminFunctions() public {
		// Test Ownable functions (called by _coldStorageOwner)
		vm.expectRevert("Ownable: caller is not the owner");
		morpherAirdrop.setMorpherStateAddress(address(0x33)); // Test new setter

		vm.expectRevert("Ownable: caller is not the owner");
		morpherAirdrop.setMorpherTokenAddress(address(0x22));

		// Test role-based function (called by _airdropAdmin)
		vm.expectRevert("MorpherAirdrop: Caller is not an Airdrop Administrator.");
		morpherAirdrop.setAirdropAuthorized(address(0x44), 1 ether);

		// Test successful calls
		vm.startPrank(_coldStorageOwner);
		morpherAirdrop.setMorpherStateAddress(address(0x33));
		morpherAirdrop.setMorpherTokenAddress(address(0x22));
		vm.stopPrank();

		assertEq(address(morpherAirdrop.state()), address(0x33));
		assertEq(morpherAirdrop.morpherToken(), address(0x22));

		// Test successful role call
		vm.startPrank(_airdropAdmin);
		morpherAirdrop.setAirdropAuthorized(address(0x44), 1 ether);
		vm.stopPrank();
		assertEq(morpherAirdrop.getAirdropAuthorized(address(0x44)), 1 ether);
	}

	// --- Remove duplicate testCannotReceiveETH ---
	// function testCannotReceiveETH() public {
	// 	vm.prank(_coldStorageOwner);
	// 	morpherAirdrop.setAirdropAdmin(address(0x11)); // This function was removed
	// 	vm.prank(_coldStorageOwner);
	// 	morpherAirdrop.setMorpherTokenAddress(address(0x22));
	// }

	function testCannotReceiveETH() public {
		vm.deal(address(0x11), 1 ether);
		vm.expectRevert();
		(bool success,) = payable(address(morpherAirdrop)).call{value: 1 ether}("");
		assertEq(success, true);
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

	function testAdminSendLockedRewards() public {
		address user = address(0xabc);
		uint256 rewardAmount = 1 ether;

		// Non-admin should not be able to send locked rewards
		vm.prank(user);
		vm.expectRevert("MorpherAirdrop: Caller is not an Airdrop Administrator.");
		morpherAirdrop.adminSendLockedRewards(user, rewardAmount);

		// Admin should be able to send locked rewards
		vm.prank(_airdropAdmin);
		vm.expectEmit(true, true, true, true);
		emit Transfer(address(morpherAirdrop), user, rewardAmount);
		vm.expectEmit(true, true, true, true);
		emit AirdropSent(_airdropAdmin, user, rewardAmount, rewardAmount);
		morpherAirdrop.adminSendLockedRewards(user, rewardAmount);

		// Verify the rewards are locked
		assertEq(MorpherToken(morpherToken).balanceOf(user), 0);
		assertEq(MorpherToken(morpherToken).getTradeableBalanceOf(user), rewardAmount);
		assertEq(MorpherToken(morpherToken).getLockedRewards(user), rewardAmount);

		// User should not be able to transfer locked rewards
		vm.prank(user);
		vm.expectRevert("MorpherToken: transfer amount exceeds available balance (locked)");
		MorpherToken(morpherToken).transfer(address(0xdef), rewardAmount);
	}
}
