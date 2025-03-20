// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/ECDSAUpgradeable.sol";

import "./BaseSetup.sol";

contract MorpherTokenTest is BaseSetup, ERC20Upgradeable {
	address _admin = address(0x1234);
	address _tokenUpdater = address(0x5678);
	address _pauser = address(0x90);

	bytes32 private constant _TYPE_HASH =
		keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
	bytes32 private constant _PERMIT_TYPEHASH =
		keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

	event SetTotalTokensOnOtherChain(uint256 _oldValue, uint256 _newValue);
	event SetTotalTokensInPositions(uint256 _oldValue, uint256 _newValue);
	event SetRestrictTransfers(bool _oldValue, bool _newValue);
	event Paused(address pauser);
	event Unpaused(address pauser);

	function setUp() public override {
		super.setUp();
		morpherAccessControl.grantRole(morpherToken.ADMINISTRATOR_ROLE(), _admin);
		morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), _admin);
		morpherAccessControl.grantRole(morpherToken.BURNER_ROLE(), _admin);
		morpherAccessControl.grantRole(morpherToken.POLYGONMINTER_ROLE(), _admin);
		morpherAccessControl.grantRole(morpherToken.PAUSER_ROLE(), _pauser);
		morpherAccessControl.grantRole(morpherToken.TOKENUPDATER_ROLE(), _tokenUpdater);
	}

	function testAdminFunctions() public {
		vm.startPrank(_admin);

		string memory name = "MorpherToken2";
		bytes32 expectedHash = keccak256(bytes(name));
		morpherToken.setHashedName(name);

		string memory version = "2";
		expectedHash = keccak256(bytes(version));
		morpherToken.setHashedVersion(version);

		vm.expectEmit(true, true, true, true);
		emit SetRestrictTransfers(false, false);
		morpherToken.setRestrictTransfers(false);
		assertEq(morpherToken.getRestrictTransfers(), false);

		vm.stopPrank();
		vm.startPrank(_tokenUpdater);

		uint256 totalOnOtherChain = 1000 * 10 ** 18;
		vm.expectEmit(true, true, true, true);
		emit SetTotalTokensOnOtherChain(0, totalOnOtherChain);
		morpherToken.setTotalTokensOnOtherChain(totalOnOtherChain);
		assertEq(morpherToken.getTotalTokensOnOtherChain(), totalOnOtherChain);

		uint256 totalTokensInPositions = 500 * 10 ** 18;
		vm.expectEmit(true, true, true, true);
		emit SetTotalTokensInPositions(0, totalTokensInPositions);
		morpherToken.setTotalInPositions(totalTokensInPositions);
		assertEq(morpherToken.getTotalTokensInPositions(), totalTokensInPositions);

		vm.stopPrank();

		uint256 totalSupply = morpherToken.totalSupply();
		assertEq(totalSupply, 1500 * 10 ** 18);

		vm.startPrank(_pauser);
		vm.expectEmit(true, true, true, true);
		emit Paused(_pauser);
		morpherToken.pause();
		assertEq(morpherToken.paused(), true);
		vm.expectEmit(true, true, true, true);
		emit Unpaused(_pauser);
		morpherToken.unpause();
		assertEq(morpherToken.paused(), false);
		vm.stopPrank();
	}

	function testPermitWithEIP712() public {
		Account memory owner = makeAccount("owner");
		address spender = address(0xdef);
		uint value = 1 ether;
		uint deadline = 100;

		vm.startPrank(_admin);

		bytes32 nameHash = keccak256(bytes("MorpherToken2"));
		morpherToken.setHashedName("MorpherToken2");

		bytes32 versionHash = keccak256(bytes("2"));
		morpherToken.setHashedVersion("2");

		morpherToken.mint(owner.addr, value);

		vm.stopPrank();

		uint nonce = morpherToken.nonces(owner.addr);

		bytes32 structHash = keccak256(abi.encode(_PERMIT_TYPEHASH, owner.addr, spender, value, nonce, deadline));
		bytes32 domainSeparator = keccak256(
			abi.encode(_TYPE_HASH, nameHash, versionHash, block.chainid, address(morpherToken))
		);
		bytes32 finalHash = ECDSAUpgradeable.toTypedDataHash(domainSeparator, structHash);
		(uint8 v, bytes32 r, bytes32 s) = vm.sign(owner.key, finalHash);

		vm.expectEmit(true, true, true, true);
		emit Approval(owner.addr, spender, value);
		morpherToken.permit(owner.addr, spender, value, deadline, v, r, s);
	}

	function testDepositWithdraw() public {
		address user = address(0xabcdef);
		vm.startPrank(_admin);

		vm.expectEmit(true, true, true, true);
		emit Transfer(address(0), user, 1 ether);
		morpherToken.deposit(user, bytes(abi.encode(1 ether)));

		uint256 totalSupply = morpherToken.totalSupply();
		assertEq(totalSupply, 1 ether);

		morpherToken.mint(_admin, 2 ether);

		totalSupply = morpherToken.totalSupply();
		assertEq(totalSupply, 3 ether);

		vm.expectEmit(true, true, true, true);
		emit Transfer(_admin, address(0), 1 ether);
		morpherToken.withdraw(1 ether);

		totalSupply = morpherToken.totalSupply();
		assertEq(totalSupply, 2 ether);
	}
	
	function testDailyMintedTransferLimit() public {
		address user = address(0xabcdef);
		address recipient = address(0x123456);
		address tradeEngine = address(0x789abc);
		
		// Set up MorpherMintingLimiter and TradeEngine addresses in state
		vm.mockCall(
			address(morpherState),
			abi.encodeWithSignature("morpherMintingLimiterAddress()"),
			abi.encode(address(this))
		);
		
		vm.mockCall(
			address(morpherState),
			abi.encodeWithSignature("morpherTradeEngineAddress()"),
			abi.encode(tradeEngine)
		);
		
		// Set daily transfer limit
		vm.startPrank(_admin);
		morpherToken.setDailyMintedTransferLimit(5 ether);
		vm.stopPrank();
		
		// Mint tokens as MintingLimiter (this will track them as net minted tokens)
		morpherToken.mint(user, 10 ether);
		
		// Check net minted tokens balance
		assertEq(morpherToken.getNetMintedTokens(user), 10 ether);
		assertEq(morpherToken.balanceOf(user), 10 ether);
		
		// Try to transfer more than the daily limit
		vm.startPrank(user);
		vm.expectRevert("MorpherToken: daily minted token transfer limit exceeded");
		morpherToken.transfer(recipient, 6 ether);
		vm.stopPrank();
		
		// Transfer within the limit
		vm.startPrank(user);
		morpherToken.transfer(recipient, 4 ether);
		vm.stopPrank();
		
		// Check balances after transfer
		assertEq(morpherToken.balanceOf(user), 6 ether);
		assertEq(morpherToken.balanceOf(recipient), 4 ether);
		assertEq(morpherToken.getNetMintedTokens(user), 6 ether);
		assertEq(morpherToken.getDailyMintedTransfers(user), 4 ether);
		assertEq(morpherToken.getTransferredInTokens(recipient), 4 ether);
		
		// Try another transfer that would exceed the limit
		vm.startPrank(user);
		vm.expectRevert("MorpherToken: daily minted token transfer limit exceeded");
		morpherToken.transfer(recipient, 2 ether);
		vm.stopPrank();
		
		// Transfer exactly at the limit
		vm.startPrank(user);
		morpherToken.transfer(recipient, 1 ether);
		vm.stopPrank();
		
		// Check final balances
		assertEq(morpherToken.balanceOf(user), 5 ether);
		assertEq(morpherToken.balanceOf(recipient), 5 ether);
		assertEq(morpherToken.getNetMintedTokens(user), 5 ether);
		assertEq(morpherToken.getDailyMintedTransfers(user), 5 ether);
		assertEq(morpherToken.getTransferredInTokens(recipient), 5 ether);
		
		// Test burn/mint cycle with TradeEngine
		vm.startPrank(tradeEngine);
		morpherToken.burn(user, 3 ether);
		assertEq(morpherToken.getNetMintedTokens(user), 2 ether);
		
		morpherToken.mint(user, 3 ether);
		assertEq(morpherToken.getNetMintedTokens(user), 5 ether);
		vm.stopPrank();
		
		// Admin should be able to bypass the limit
		vm.startPrank(_admin);
		morpherToken.mint(user, 10 ether);
		vm.stopPrank();
		
		// Admin transfer should bypass limit
		vm.startPrank(_admin);
		morpherToken.transferFrom(user, recipient, 10 ether);
		vm.stopPrank();
		
		// Check final balances after admin transfer
		assertEq(morpherToken.balanceOf(user), 5 ether);
		assertEq(morpherToken.balanceOf(recipient), 15 ether);
	}
	function testTransferredInTokensWithBurnMintCycle() public {
		address user1 = address(0xabcdef);
		address user2 = address(0x123456);
		address tradeEngine = address(0x789abc);
		
		// Set up TradeEngine address in state
		vm.mockCall(
			address(morpherState),
			abi.encodeWithSignature("morpherTradeEngineAddress()"),
			abi.encode(tradeEngine)
		);
		
		// Set daily transfer limit
		vm.startPrank(_admin);
		morpherToken.setDailyMintedTransferLimit(5 ether);
		morpherToken.mint(user1, 10 ether);
		vm.stopPrank();
		
		// User1 transfers to User2
		vm.startPrank(user1);
		morpherToken.transfer(user2, 10 ether);
		vm.stopPrank();
		
		// Check that User2 has transferred in tokens
		assertEq(morpherToken.getTransferredInTokens(user2), 10 ether);
		assertEq(morpherToken.getNetMintedTokens(user2), 0);
		
		// TradeEngine burns tokens (opening a position)
		vm.startPrank(tradeEngine);
		morpherToken.burn(user2, 8 ether);
		vm.stopPrank();
		
		// Check balances
		assertEq(morpherToken.balanceOf(user2), 2 ether);
		assertEq(morpherToken.getNetMintedTokens(user2), 0); // Should still be 0
		
		// TradeEngine mints tokens back (closing a position)
		vm.startPrank(tradeEngine);
		morpherToken.mint(user2, 8 ether);
		vm.stopPrank();
		
		// Check balances - user should have 8 ether of net minted tokens now
		assertEq(morpherToken.balanceOf(user2), 10 ether);
		assertEq(morpherToken.getNetMintedTokens(user2), 8 ether);
		
		// User2 should be able to transfer up to the daily limit of net minted tokens
		vm.startPrank(user2);
		morpherToken.transfer(user1, 5 ether); // Within limit
		vm.stopPrank();
		
		// Check balances
		assertEq(morpherToken.balanceOf(user2), 5 ether);
		assertEq(morpherToken.balanceOf(user1), 5 ether);
		assertEq(morpherToken.getNetMintedTokens(user2), 3 ether); // 8 - 5
		
		// Try to transfer more than the remaining limit
		vm.startPrank(user2);
		vm.expectRevert("MorpherToken: daily minted token transfer limit exceeded");
		morpherToken.transfer(user1, 4 ether); // Would exceed limit
		vm.stopPrank();
		
		// Transfer exactly at the limit
		vm.startPrank(user2);
		morpherToken.transfer(user1, 3 ether); // Exactly at limit
		vm.stopPrank();
		
		// Check final balances
		assertEq(morpherToken.balanceOf(user2), 2 ether);
		assertEq(morpherToken.balanceOf(user1), 8 ether);
		assertEq(morpherToken.getNetMintedTokens(user2), 0); // All net minted tokens transferred
	}
}
