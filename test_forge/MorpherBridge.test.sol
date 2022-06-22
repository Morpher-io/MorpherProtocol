// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

import "./BaseSetup.sol";

contract MorpherBridgeTest is BaseSetup {

    function setUp() override public {
        super.setUp();
        

        morpherAccessControl.grantRole(
            morpherToken.MINTER_ROLE(),
            address(this)
        );
        morpherToken.mint(address(this), 10000 ether);
    }

    function testHasRole() public {
        assertEq(
            morpherAccessControl.hasRole(
                morpherBridge.SIDECHAINOPERATOR_ROLE(),
                address(this)
            ),
            true
        );

    }

    event TransferToLinkedChain(
        address indexed from,
        uint256 tokens,
        uint256 totalTokenSent,
        uint256 timeStamp,
        uint256 transferNonce,
        uint256 targetChainId,
        bytes32 indexed transferHash
    );

    function testStageTokens() public {
        morpherBridge.updateWithdrawLimitPerUserDaily(200 ether);
        morpherAccessControl.grantRole(
            morpherToken.TRANSFER_ROLE(),
            address(this)
        );
        address addr1 = address(0x01);
        address addr2 = address(0x02);
        morpherToken.transfer(addr1, 200 ether);

        assertEq(morpherToken.balanceOf(addr1), 200 ether);

        vm.prank(addr1);
        vm.expectEmit(true, false, false, false);
        emit TransferToLinkedChain(addr1, 100000000000000000000, 100000000000000000000, block.timestamp, 1, block.chainid, 0x9002f1c01bda6488e7f15919bfadd86b3dafd1daf59dd666697ca211dcf8e85c);
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
}
