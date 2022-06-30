// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

import "./BaseSetup.sol";
import "murky/Merkle.sol";
import "../contracts/MorpherBridge.sol";

contract MorpherBridgeTest is BaseSetup, MorpherBridge {
	function setUp() public override {
		super.setUp();

		morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(this));
		morpherToken.mint(address(this), 10000 ether);
	}

	function testHasRole() public {
		assertEq(morpherAccessControl.hasRole(morpherBridge.SIDECHAINOPERATOR_ROLE(), address(this)), true);
	}

	function test24HourLimitsChangePerUser() public {
		uint oldLimit = morpherBridge.withdrawalLimitPerUserDaily();
		uint newLimit = oldLimit + 1 ether;

		vm.expectEmit(true, true, true, true);
		emit WithdrawLimitDailyPerUserChanged(oldLimit, newLimit);
		morpherBridge.updateWithdrawLimitPerUserDaily(newLimit);

		assertEq(morpherBridge.withdrawalLimitPerUserDaily(), newLimit);

		//set it back
		morpherBridge.updateWithdrawLimitPerUserDaily(oldLimit);
	}
	function testFail24HourLimitsChangePerUser() public {
        //has no sidechainoperator role, should fail
        morpherAccessControl.revokeRole(morpherBridge.SIDECHAINOPERATOR_ROLE(), address(this));
		morpherBridge.updateWithdrawLimitPerUserDaily(1 ether);
	}

	function test30DayLimitsChangePerUser() public {
		uint oldLimit = morpherBridge.withdrawalLimitPerUserMonthly();
		uint newLimit = oldLimit + 1 ether;

		vm.expectEmit(true, true, true, true);
		emit WithdrawLimitMonthlyPerUserChanged(oldLimit, newLimit);
		morpherBridge.updateWithdrawLimitPerUserMonthly(newLimit);

		assertEq(morpherBridge.withdrawalLimitPerUserMonthly(), newLimit);

		//set it back
		morpherBridge.updateWithdrawLimitPerUserMonthly(oldLimit);
	}

	function testYearlyLimitsChangePerUser() public {
		morpherAccessControl.grantRole(morpherBridge.SIDECHAINOPERATOR_ROLE(), address(this));
		uint oldLimit = morpherBridge.withdrawalLimitPerUserYearly();
		uint newLimit = oldLimit + 1 ether;

		vm.expectEmit(true, true, true, true);
		emit WithdrawLimitYearlyPerUserChanged(oldLimit, newLimit);
		morpherBridge.updateWithdrawLimitPerUserYearly(newLimit);

		assertEq(morpherBridge.withdrawalLimitPerUserYearly(), newLimit);

		//set it back
		morpherBridge.updateWithdrawLimitPerUserYearly(oldLimit);
		morpherAccessControl.revokeRole(morpherBridge.SIDECHAINOPERATOR_ROLE(), address(this));
	}

    // /**
    // *  Idea: User 1 withdraws max, 1 MPH more errors out, user 2 can still withdraw
    // */
	// function testUserLimits() public {
	// 	morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(this));
	// 	uint withdrawalLimit = morpherBridge.withdrawalLimitPerUserDaily();
		
    //     address user1 = address(0x1);
    //     address user2 = address(0x2);

    //     vm.prank(user1);
    //     vm.expectEmit(true, false, false, false);
    //     emit TransferToLinkedChain(user1, withdrawalAmount, with, _timeStamp, _transferNonce, _targetChainId, _transferHash);

	// }

	

	function testStageTokens() public {
		morpherBridge.updateWithdrawLimitPerUserDaily(200 ether);
		morpherAccessControl.grantRole(morpherToken.TRANSFER_ROLE(), address(this));
		address addr1 = address(0x01);
		morpherToken.transfer(addr1, 200 ether);

		assertEq(morpherToken.balanceOf(addr1), 200 ether);

		vm.prank(addr1);
		vm.expectEmit(true, false, false, false);
		emit TransferToLinkedChain(
			addr1,
			100000000000000000000,
			100000000000000000000,
			block.timestamp,
			1,
			block.chainid,
			0x9002f1c01bda6488e7f15919bfadd86b3dafd1daf59dd666697ca211dcf8e85c
		);
		morpherBridge.stageTokensForTransfer(200 ether, block.chainid);

		assertEq(morpherToken.balanceOf(addr1), 0 ether);

		//now lets go beyond the 24h withdrawal limit
		morpherToken.transfer(addr1, 1 ether);
		assertEq(morpherToken.balanceOf(addr1), 1 ether);

		vm.expectRevert("MorpherBridge: Withdrawal Amount exceeds daily limit");
		vm.prank(addr1);
		morpherBridge.stageTokensForTransfer(1 ether, block.chainid);

		assertEq(morpherToken.balanceOf(addr1), 1 ether);
		morpherAccessControl.grantRole(morpherToken.TRANSFER_ROLE(), addr1);

		vm.prank(addr1);
		morpherToken.transfer(address(this), 1 ether);
	}

	function testStageClaimTokens() public {
		morpherBridge.updateWithdrawLimitPerUserDaily(400 ether);
		morpherAccessControl.grantRole(morpherToken.TRANSFER_ROLE(), address(this));
		address addr1 = address(0x01);

		morpherToken.transfer(addr1, 200 ether);

		assertEq(morpherToken.balanceOf(addr1), 200 ether);

		vm.prank(addr1);
		vm.expectEmit(true, false, false, false);
		emit TransferToLinkedChain(
			addr1,
			100000000000000000000,
			100000000000000000000,
			block.timestamp,
			1,
			block.chainid,
			0x9002f1c01bda6488e7f15919bfadd86b3dafd1daf59dd666697ca211dcf8e85c
		);
		morpherBridge.stageTokensForTransfer(200 ether, 5555);

		assertEq(morpherToken.balanceOf(addr1), 0 ether);

		// Initialize
		Merkle m = new Merkle();
		// Toy Data
		bytes32[] memory data = new bytes32[](4);
		data[0] = keccak256(abi.encodePacked(addr1, uint(200 ether), uint(5555)));
		data[1] = keccak256(abi.encodePacked(addr1, uint(200 ether), uint(5555)));
		data[2] = keccak256(abi.encodePacked(addr1, uint(200 ether), uint(5555)));
		data[3] = keccak256(abi.encodePacked(addr1, uint(200 ether), uint(5555)));
		// Get Root, Proof, and Verify
		bytes32 root = m.getRoot(data);

		morpherBridge.updateSideChainMerkleRoot(root);

		bytes32[] memory proof = m.getProof(data, 2);
		vm.prank(addr1);
		vm.chainId(5555);
		morpherBridge.claimStagedTokens(200 ether, 200 ether, proof);

		assertEq(morpherToken.balanceOf(addr1), 200 ether);
	}
}
