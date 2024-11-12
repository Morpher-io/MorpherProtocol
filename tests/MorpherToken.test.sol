// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

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
		emit SetRestrictTransfers(true, false);
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
}
