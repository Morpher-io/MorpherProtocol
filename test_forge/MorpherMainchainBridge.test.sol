// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;
import "forge-std/Test.sol";

import "murky/Merkle.sol";
import "../contracts/MorpherBridge.sol";
import "../contracts/MorpherState.sol";
import "../contracts/MorpherAccessControl.sol";
import "../contracts/MorpherToken.sol";

contract MorpherBridgeTest is MorpherBridge, Test {
	using stdStorage for StdStorage;
	MorpherState morpherState;

	function setUp() public {
		morpherState = MorpherState(0x88A610554eb712DCD91a47108aE59028B3De6614);
	}

	function testStateAddress() public {
		assertEq(0x334643882B849A286E01c386C3e033B1b5c75164, morpherState.morpherTokenAddress());
	}

	// function testStageTokens() public {
	// 	morpherBridge.updateWithdrawLimitPerUserDaily(200 ether);
	// 	morpherAccessControl.grantRole(morpherToken.TRANSFER_ROLE(), address(this));
	// 	address addr1 = address(0x01);
	// 	morpherToken.transfer(addr1, 200 ether);

	// 	assertEq(morpherToken.balanceOf(addr1), 200 ether);

	// 	vm.prank(addr1);
	// 	vm.expectEmit(true, false, false, false);
	// 	emit TransferToLinkedChain(
	// 		addr1,
	// 		100000000000000000000,
	// 		100000000000000000000,
	// 		block.timestamp,
	// 		1,
	// 		block.chainid,
	// 		0x9002f1c01bda6488e7f15919bfadd86b3dafd1daf59dd666697ca211dcf8e85c
	// 	);
	// 	morpherBridge.stageTokensForTransfer(200 ether, block.chainid);

	// 	assertEq(morpherToken.balanceOf(addr1), 0 ether);

	// 	//now lets go beyond the 24h withdrawal limit
	// 	morpherToken.transfer(addr1, 1 ether);
	// 	assertEq(morpherToken.balanceOf(addr1), 1 ether);

	// 	vm.expectRevert("MorpherBridge: Withdrawal Amount exceeds daily limit");
	// 	vm.prank(addr1);
	// 	morpherBridge.stageTokensForTransfer(1 ether, block.chainid);

	// 	assertEq(morpherToken.balanceOf(addr1), 1 ether);
	// 	morpherAccessControl.grantRole(morpherToken.TRANSFER_ROLE(), addr1);

	// 	vm.prank(addr1);
	// 	morpherToken.transfer(address(this), 1 ether);
	// }

	function testStageClaimTokensMainchain() public {
		// address mainchain_owner = address(0x51c5cE7C4926D5cA74f4824e11a062f1Ef491762);
		address callback_addr1 = address(0xCCCcc0405E2eA54Ca901f929965227c50235D87b);

		MorpherBridge morpherBridge = MorpherBridge(payable(morpherState.morpherBridgeAddress()));

		MorpherToken oldMorpherToken = MorpherToken(0x1f426C51F0Ef7655A6f4c3Eb58017d2F1c381bfF); //address of state pretending to be a token

		address addr1 = address(0x01);
		address addr2 = address(0x02);
		address addr3 = address(0x03);
		address addr4 = address(0x04);
		// Initialize
		Merkle m = new Merkle();
		// Toy Data
		bytes32[] memory data = new bytes32[](4);
		data[0] = keccak256(abi.encodePacked(addr1, uint(200 ether), uint(1)));
		data[1] = keccak256(abi.encodePacked(addr2, uint(200 ether), uint(1)));
		data[2] = keccak256(abi.encodePacked(addr3, uint(200 ether), uint(1)));
		data[3] = keccak256(abi.encodePacked(addr4, uint(200 ether), uint(1)));
		// Get Root, Proof, and Verify
		bytes32 root = m.getRoot(data);

		vm.prank(callback_addr1);
		morpherBridge.updateSideChainMerkleRoot(root);

		bytes32[] memory proof = m.getProof(data, 2);

		vm.prank(addr3);
		vm.chainId(1);
		morpherBridge.claimStagedTokens(200 ether, 200 ether, proof);

		assertEq(oldMorpherToken.balanceOf(addr3), 200 ether);
	}

	function testClaimTokensMainchain() public {
		// address mainchain_owner = address(0x51c5cE7C4926D5cA74f4824e11a062f1Ef491762);
		address callback_addr1 = address(0xCCCcc0405E2eA54Ca901f929965227c50235D87b);

		MorpherBridge morpherBridge = MorpherBridge(payable(morpherState.morpherBridgeAddress()));

		MorpherToken oldMorpherToken = MorpherToken(0x1f426C51F0Ef7655A6f4c3Eb58017d2F1c381bfF); //address of state pretending to be a token

		address usrAddr = 0x9578a645c265267141FB2B9A8C6dBa70EDBe9dFC;
		uint numTokens = 2761435009657343000000;
		uint fee = 0;
		address feeRecipient = 0xCCCcc0405E2eA54Ca901f929965227c50235D87b;
		uint claimLimit = 5852870019314686000000;
		bytes32[] memory proof = new bytes32[](17);
		proof[0] = 0x67933604fd3d9ed9dc05e04bb4ed7f5f29f85ff1d11e4d2f01a167433e83128c;
		proof[1] = 0x85118bfc0cb4f9753dc39f991c9b29babe82ae1e5d11d2b7a8bfa57481a9e203;
		proof[2] = 0x86f65eeefe0f08ea8209360cbdd17ef3ef39fd408dfb45979e6184f33b313c9d;
		proof[3] = 0x5f30194e61a440b5f205c647f3f42a47d813f738b742b4162ad76360d0a2f7bf;
		proof[4] = 0x9db0610e5d3f03548e5568160986735065b236341da924631e7f87aa73bb2626;
		proof[5] = 0xe6a73e61789538d9bee2838bc6014d9dd45ece607899e6e797242b5a03cf7f20;
		proof[6] = 0x59e37b702d37096fa752eea9dac0811803f1d04bb9aae24f16133a87a085720b;
		proof[7] = 0xd40416251dbd39ede9bcea0fc8820d1c361398366324a57786878cecffe18a06;
		proof[8] = 0x8d1a5e33ceeb464e3ae9c97988a2f9cefb1f0337f27e2b2f1af69f720cd660a4;
		proof[9] = 0xe0f5d99edf08162fbf8cd23a5d4cc263929112a1717d8054be5823bf8b853698;
		proof[10] = 0x9f82f31099d9a2a769286370ad2dc790791da3ad53670526c5e253a16bf413f7;
		proof[11] = 0x0320862274b18a846f9748d9af72f392a32778af7451982ef978879ed305af6e;
		proof[12] = 0x70b71c9528ceac4ae3f30108249fdc7be577dbdffa7d9b4fabee05df1731cc3f;
		proof[13] = 0x308cb833a07f40e046529c5ac4c4aa31dbc3b96eb7a431ff96b35a1df8cc2589;
		proof[14] = 0x80b4a3450071de3d6c5857ec3c151e51aba4212cfbada2efd88c953edf6a4ae2;
		proof[15] = 0x0dd110b52bc0993707ddf442b329f093a46e30cab91416b069905955815822bf;
		proof[16] = 0xa66a364c628be71752cca7d360d96dca548b4202a8d2a0a0b1b6705350544624;

		address finalOutput = 0x32D0AC199eC8A920C60e743980258fbC97207A67;
		bytes32 rootHash = 0x071d4fb86d5d19c8f601da2ba68419139cc01390ec795de3b51cb82f58c3c150;
		bytes
			memory userSignature = hex"057ef86942be2a9ad1dd0a6da52d731206686b7f68d377d8a3e1ffe37e0a9b7f7d71c613b9113b3887531f35ed56bb8f0394254a325a3eac521ceb3fe880548e1b";
		// bytes memory userSignature = new bytes(65);
		// userSignature = bytes(userSignatureTxt);
		// for(uint i = 0; i < 65; i++){
		//   userSignature[i] = bytes(userSignatureTxt)[i];
		// }

		vm.prank(callback_addr1);
		vm.chainId(1);
		//Function: claimStagedTokensAndSendForUser(address _usrAddr, uint256 _numOfToken, uint256 fee, address feeRecipient, uint256 _claimLimit, bytes32[] _proof, address _finalOutput, bytes32 _rootHash, bytes _userConfirmationSignature)
		morpherBridge.claimStagedTokensAndSendForUser(
			usrAddr,
			numTokens,
			fee,
			feeRecipient,
			claimLimit,
			proof,
			payable(finalOutput),
			rootHash,
			userSignature
		);

		assertEq(oldMorpherToken.balanceOf(finalOutput), numTokens);
	}

	function updateSidechainRoot(address beneficiary, uint tokenAmount) private returns (bytes32[] memory, bytes32) {
		Merkle m = new Merkle();
		MorpherBridge morpherBridge = MorpherBridge(payable(morpherState.morpherBridgeAddress()));

		address callback_addr1 = address(0xCCCcc0405E2eA54Ca901f929965227c50235D87b);

		bytes32[] memory data = new bytes32[](4);
		data[0] = keccak256(abi.encodePacked(beneficiary, uint(tokenAmount), uint(1)));
		data[1] = keccak256(abi.encodePacked(beneficiary, uint(tokenAmount), uint(1)));
		data[2] = keccak256(abi.encodePacked(beneficiary, uint(tokenAmount), uint(1)));
		data[3] = keccak256(abi.encodePacked(beneficiary, uint(tokenAmount), uint(1)));
		// Get Root, Proof, and Verify
		bytes32 root = m.getRoot(data);

		vm.prank(callback_addr1);
		morpherBridge.updateSideChainMerkleRoot(root);

		bytes32[] memory proof = m.getProof(data, 2);
		return (proof, root);
	}

	function testClaimTokensMiniProofMainchain() public {
		// address mainchain_owner = address(0x51c5cE7C4926D5cA74f4824e11a062f1Ef491762);
		address callback_addr1 = address(0xCCCcc0405E2eA54Ca901f929965227c50235D87b);

		MorpherBridge morpherBridge = MorpherBridge(payable(morpherState.morpherBridgeAddress()));

		MorpherToken oldMorpherToken = MorpherToken(0x1f426C51F0Ef7655A6f4c3Eb58017d2F1c381bfF); //address of state pretending to be a token

		address usrAddr = 0x9578a645c265267141FB2B9A8C6dBa70EDBe9dFC;
		uint numTokens = 2761435009657343000000;
		uint fee = 0;
		address feeRecipient = 0xCCCcc0405E2eA54Ca901f929965227c50235D87b;
		uint claimLimit = 5852870019314686000000;
		(bytes32[] memory proof, bytes32 rootHash) = updateSidechainRoot(usrAddr, claimLimit);
		address finalOutput = 0x32D0AC199eC8A920C60e743980258fbC97207A67;
		//bytes32 rootHash = 0x071d4fb86d5d19c8f601da2ba68419139cc01390ec795de3b51cb82f58c3c150;
		bytes
			memory userSignature = hex"057ef86942be2a9ad1dd0a6da52d731206686b7f68d377d8a3e1ffe37e0a9b7f7d71c613b9113b3887531f35ed56bb8f0394254a325a3eac521ceb3fe880548e1b";
		// bytes memory userSignature = new bytes(65);
		// userSignature = bytes(userSignatureTxt);
		// for(uint i = 0; i < 65; i++){
		//   userSignature[i] = bytes(userSignatureTxt)[i];
		// }

		vm.prank(callback_addr1);
		vm.chainId(1);
		//Function: claimStagedTokensAndSendForUser(address _usrAddr, uint256 _numOfToken, uint256 fee, address feeRecipient, uint256 _claimLimit, bytes32[] _proof, address _finalOutput, bytes32 _rootHash, bytes _userConfirmationSignature)
		morpherBridge.claimStagedTokensAndSendForUser(
			usrAddr,
			numTokens,
			fee,
			feeRecipient,
			claimLimit,
			proof,
			payable(finalOutput),
			rootHash,
			userSignature
		);

		assertEq(oldMorpherToken.balanceOf(finalOutput), numTokens);
	}
	function testClaimOnlyTokensMiniProofMainchain() public {
		// address mainchain_owner = address(0x51c5cE7C4926D5cA74f4824e11a062f1Ef491762);
		address callback_addr1 = address(0xCCCcc0405E2eA54Ca901f929965227c50235D87b);

		MorpherBridge morpherBridge = MorpherBridge(payable(morpherState.morpherBridgeAddress()));

		MorpherToken oldMorpherToken = MorpherToken(0x1f426C51F0Ef7655A6f4c3Eb58017d2F1c381bfF); //address of state pretending to be a token

		address usrAddr = 0x9578a645c265267141FB2B9A8C6dBa70EDBe9dFC;
		uint numTokens = 2761435009657343000000;
		uint claimLimit = 5852870019314686000000;
		bytes32[] memory proof = new bytes32[](17);
		proof[0] = 0x67933604fd3d9ed9dc05e04bb4ed7f5f29f85ff1d11e4d2f01a167433e83128c;
		proof[1] = 0x85118bfc0cb4f9753dc39f991c9b29babe82ae1e5d11d2b7a8bfa57481a9e203;
		proof[2] = 0x86f65eeefe0f08ea8209360cbdd17ef3ef39fd408dfb45979e6184f33b313c9d;
		proof[3] = 0x5f30194e61a440b5f205c647f3f42a47d813f738b742b4162ad76360d0a2f7bf;
		proof[4] = 0x9db0610e5d3f03548e5568160986735065b236341da924631e7f87aa73bb2626;
		proof[5] = 0xe6a73e61789538d9bee2838bc6014d9dd45ece607899e6e797242b5a03cf7f20;
		proof[6] = 0x59e37b702d37096fa752eea9dac0811803f1d04bb9aae24f16133a87a085720b;
		proof[7] = 0xd40416251dbd39ede9bcea0fc8820d1c361398366324a57786878cecffe18a06;
		proof[8] = 0x8d1a5e33ceeb464e3ae9c97988a2f9cefb1f0337f27e2b2f1af69f720cd660a4;
		proof[9] = 0xe0f5d99edf08162fbf8cd23a5d4cc263929112a1717d8054be5823bf8b853698;
		proof[10] = 0x9f82f31099d9a2a769286370ad2dc790791da3ad53670526c5e253a16bf413f7;
		proof[11] = 0x0320862274b18a846f9748d9af72f392a32778af7451982ef978879ed305af6e;
		proof[12] = 0x70b71c9528ceac4ae3f30108249fdc7be577dbdffa7d9b4fabee05df1731cc3f;
		proof[13] = 0x308cb833a07f40e046529c5ac4c4aa31dbc3b96eb7a431ff96b35a1df8cc2589;
		proof[14] = 0x80b4a3450071de3d6c5857ec3c151e51aba4212cfbada2efd88c953edf6a4ae2;
		proof[15] = 0x0dd110b52bc0993707ddf442b329f093a46e30cab91416b069905955815822bf;
		proof[16] = 0xa66a364c628be71752cca7d360d96dca548b4202a8d2a0a0b1b6705350544624;

		address finalOutput = 0x32D0AC199eC8A920C60e743980258fbC97207A67;
		bytes32 rootHash = 0x071d4fb86d5d19c8f601da2ba68419139cc01390ec795de3b51cb82f58c3c150;
	
		vm.prank(callback_addr1);
		morpherBridge.updateSideChainMerkleRoot(rootHash);

		vm.prank(usrAddr);
		vm.chainId(1);
		//Function: claimStagedTokensAndSendForUser(address _usrAddr, uint256 _numOfToken, uint256 fee, address feeRecipient, uint256 _claimLimit, bytes32[] _proof, address _finalOutput, bytes32 _rootHash, bytes _userConfirmationSignature)
		morpherBridge.claimStagedTokens(numTokens, claimLimit, proof);

		assertEq(oldMorpherToken.balanceOf(finalOutput), numTokens);
	}
}
