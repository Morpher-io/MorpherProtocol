// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "./BaseSetup.sol";

contract MorkpherMintingLimiterTest is BaseSetup {
	event Transfer(address indexed from, address indexed to, uint256 value);

	event MintingEscrowed(address _user, uint256 _tokenAmount);
	event EscrowReleased(address _user, uint256 _tokenAmount);
	event MintingDenied(address _user, uint256 _tokenAmount);
	event MintingLimitUpdatedPerUser(uint256 _mintingLimitOld, uint256 _mintingLimitNew);
	event MintingLimitUpdatedDaily(uint256 _mintingLimitOld, uint256 _mintingLimitNew);
	event TimeLockPeriodUpdated(uint256 _timeLockPeriodOld, uint256 _timeLockPeriodNew);
	event TradeEngineAddressSet(address _morpherTradeEngineAddress);
	event DailyMintedTokensReset();

	address _admin = address(0xffeedd);

	function setUp() public override {
		super.setUp();
		morpherAccessControl.grantRole(morpherToken.ADMINISTRATOR_ROLE(), address(_admin));
	}

	function testAdministratorSettings() public {
		vm.expectRevert();
		morpherMintingLimiter.setMintingLimitDaily(0);
		vm.prank(_admin);
		vm.expectEmit(true, true, true, true);
		emit MintingLimitUpdatedDaily(5000000000000000000000000, 0);
		morpherMintingLimiter.setMintingLimitDaily(0);
		uint newLimit = morpherMintingLimiter.mintingLimitDaily();
		assertEq(newLimit, 0);

		address newTradeEngineAddress = address(0xabcdef);
		vm.expectRevert();
		morpherMintingLimiter.setTradeEngineAddress(newTradeEngineAddress);
		vm.prank(_admin);
		vm.expectEmit(true, true, true, true);
		emit TradeEngineAddressSet(newTradeEngineAddress);
		morpherMintingLimiter.setTradeEngineAddress(newTradeEngineAddress);

		vm.expectRevert();
		morpherMintingLimiter.setMintingLimitPerUser(0);
		vm.prank(_admin);
		vm.expectEmit(true, true, true, true);
		emit MintingLimitUpdatedPerUser(500000000000000000000000, 0);
		morpherMintingLimiter.setMintingLimitPerUser(0);
		uint newUserLimit = morpherMintingLimiter.mintingLimitPerUser();
		assertEq(newUserLimit, 0);

		vm.expectRevert();
		morpherMintingLimiter.setTimeLockingPeriod(3600);
		vm.prank(_admin);
		vm.expectEmit(true, true, true, true);
		emit TimeLockPeriodUpdated(260000, 3600);
		morpherMintingLimiter.setTimeLockingPeriod(3600);
		uint newTimeLock = morpherMintingLimiter.timeLockingPeriod();
		assertEq(newTimeLock, 3600);
	}

	function testMintBelowLimits() public {
		uint256 tokenAmount = 500000000000000000000000;

		vm.prank(address(morpherTradeEngine));
		vm.expectEmit(true, true, true, true);
		emit Transfer(address(0), address(0xabc), tokenAmount);
		morpherMintingLimiter.mint(address(0xabc), tokenAmount);

		uint256 balance = morpherToken.balanceOf(address(0xabc));
		assertEq(balance, tokenAmount);

		uint256 mintedToday = morpherMintingLimiter.getDailyMintedTokens();
		assertEq(mintedToday, tokenAmount);
	}

	function testResetDailyMintedTokens() public {
		uint256 tokenAmount = 500000000000000000000000;

		vm.prank(address(morpherTradeEngine));
		morpherMintingLimiter.mint(address(0xabc), tokenAmount);

		vm.prank(_admin);
		morpherMintingLimiter.resetDailyMintedTokens();

		uint256 mintedToday = morpherMintingLimiter.getDailyMintedTokens();
		assertEq(mintedToday, 0);
	}

	function testMintAboveUserLimit() public {
		uint256 tokenAmount = 500000000000000000000001;

		vm.prank(address(morpherTradeEngine));
		vm.expectEmit(true, true, true, true);
		emit MintingEscrowed(address(0xabc), tokenAmount);
		morpherMintingLimiter.mint(address(0xabc), tokenAmount);

		uint256 balance = morpherToken.balanceOf(address(0xabc));
		assertEq(balance, 0);

		uint256 mintedToday = morpherMintingLimiter.getDailyMintedTokens();
		// not minted since they are escrowed
		assertEq(mintedToday, 0);
	}

	function testMintAboveDailyLimit() public {
		uint256 tokenAmount = 500000000000000000000000;

		vm.prank(_admin);
		morpherMintingLimiter.setMintingLimitDaily(900000000000000000000000);

		vm.prank(address(morpherTradeEngine));
		morpherMintingLimiter.mint(address(0x123), tokenAmount);

		vm.prank(address(morpherTradeEngine));
		vm.expectEmit(true, true, true, true);
		emit MintingEscrowed(address(0x456), tokenAmount);
		morpherMintingLimiter.mint(address(0x456), tokenAmount);

		uint256 escrowed = morpherMintingLimiter.escrowedTokens(address(0x456));
		assertEq(escrowed, tokenAmount);

		uint256 balance = morpherToken.balanceOf(address(0x456));
		assertEq(balance, 0);

		uint256 lockTime = morpherMintingLimiter.lockedUntil(address(0x456));
		assertEq(lockTime, block.timestamp + morpherMintingLimiter.timeLockingPeriod());

		// same for 1st user as well
		vm.prank(address(morpherTradeEngine));
		vm.expectEmit(true, true, true, true);
		emit MintingEscrowed(address(0x123), tokenAmount);
		morpherMintingLimiter.mint(address(0x123), tokenAmount);

		escrowed = morpherMintingLimiter.escrowedTokens(address(0x123));
		assertEq(escrowed, tokenAmount);

		balance = morpherToken.balanceOf(address(0x123));
		assertEq(balance, tokenAmount);

		lockTime = morpherMintingLimiter.lockedUntil(address(0x456));
		assertEq(lockTime, block.timestamp + morpherMintingLimiter.timeLockingPeriod());
	}

	function testDelayedMint() public {
		address user = address(0xabc);
		uint256 tokenAmount = 500000000000000000000001;

		vm.warp(morpherMintingLimiter.timeLockingPeriod());

		vm.prank(address(morpherTradeEngine));
		morpherMintingLimiter.mint(user, tokenAmount);

		vm.prank(user);
		vm.expectRevert();
		morpherMintingLimiter.delayedMint(user);

		vm.warp(morpherMintingLimiter.timeLockingPeriod() * 2 - 1);

		vm.prank(user);
		vm.expectRevert();
		morpherMintingLimiter.delayedMint(user);

		vm.warp(morpherMintingLimiter.timeLockingPeriod() * 2);

		vm.prank(user);
		vm.expectEmit(true, true, true, true);
		emit EscrowReleased(user, tokenAmount);
		morpherMintingLimiter.delayedMint(user);

		uint256 balance = morpherToken.balanceOf(user);
		assertEq(balance, tokenAmount);
	}

	function testAdminApprovesMint() public {
		address user = address(0xabc);
		uint256 tokenAmount = 500000000000000000000001;

		vm.prank(address(morpherTradeEngine));
		morpherMintingLimiter.mint(user, tokenAmount);

		vm.prank(_admin);
		vm.expectEmit(true, true, true, true);
		emit EscrowReleased(user, tokenAmount);
		morpherMintingLimiter.adminApprovedMint(user, tokenAmount);

		uint256 balance = morpherToken.balanceOf(user);
		assertEq(balance, tokenAmount);

		vm.warp(morpherMintingLimiter.timeLockingPeriod() * 2);

		vm.prank(user);
		morpherMintingLimiter.delayedMint(user);

		// unchanged
		balance = morpherToken.balanceOf(user);
		assertEq(balance, tokenAmount);
	}

	function testAdminDisapprovesMint() public {
		address user = address(0xabc);
		uint256 tokenAmount = 500000000000000000000001;

		vm.prank(address(morpherTradeEngine));
		morpherMintingLimiter.mint(user, tokenAmount);

		vm.prank(_admin);
		vm.expectEmit(true, true, true, true);
		emit MintingDenied(user, tokenAmount);
		morpherMintingLimiter.adminDisapproveMint(user, tokenAmount);

		uint256 balance = morpherToken.balanceOf(user);
		assertEq(balance, 0);

		vm.warp(morpherMintingLimiter.timeLockingPeriod() * 2);

		vm.prank(user);
		morpherMintingLimiter.delayedMint(user);

		// unchanged
		balance = morpherToken.balanceOf(user);
		assertEq(balance, 0);
	}
}
