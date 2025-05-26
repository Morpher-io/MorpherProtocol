// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {ECDSA} from "../lib/openzeppelin-contracts-5/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "../lib/openzeppelin-contracts-5/contracts/utils/cryptography/MessageHashUtils.sol";
import {MerkleProof} from "../lib/openzeppelin-contracts-5/contracts/utils/cryptography/MerkleProof.sol";

import "./BaseSetup.sol";
import "./mocks/ERC20.sol"; // Assuming MorpherToken is ERC20-like for testing burn/mint
import "./mocks/UniswapRouter.sol"; // Mock Uniswap Router
import "../contracts/MorpherBridge.sol";
import "../contracts/MorpherToken.sol"; // For MINTER_ROLE, BURNER_ROLE constants
import {IWETH9} from '../lib/uniswap-v3-periphery/contracts/interfaces/external/IWETH9.sol'; // For WETH9 address from router

contract MorpherBridgeTest is BaseSetup {
    using MessageHashUtils for bytes32;

    MorpherBridge internal morpherBridge;
    MockUniswapRouter internal mockSwapRouter;
    MockERC20 internal wethMock; // Mock WETH for testing swaps

    Account internal user1;
    Account internal user2;
    Account internal sidechainOperator;
    Account internal admin;
    Account internal feeRecipient;

    uint256 constant ONE_DAY = 1 days;
    uint256 constant THIRTY_DAYS = 30 days;
    uint256 constant YEAR_DAYS = 365 days;


    event TransferToLinkedChain(
        address indexed from,
        uint256 tokens,
        uint256 totalTokenSent,
        uint256 timeStamp,
        uint256 transferNonce,
        uint256 targetChainId,
        bytes32 indexed transferHash
    );
    event TransferToLinkedChainAndWithdrawTo(
        address indexed from,
        uint256 tokens,
        uint256 totalTokenSent,
        uint256 timeStamp,
        uint256 transferNonce,
        uint256 targetChainId,
        address destinationAddress,
        bytes userSigature,
        bytes32 indexed transferHash
    );
    event TrustlessWithdrawFromSideChain(address indexed from, uint256 tokens);
    event SideChainMerkleRootUpdated(bytes32 _rootHash);
    event WithdrawalSuccess(address _destination, uint _amount, bool _convertedToGasToken);


    function setUp() public override {
        super.setUp();

        user1 = makeAccount("user1");
        user2 = makeAccount("user2");
        sidechainOperator = makeAccount("sidechainOperator");
        admin = makeAccount("admin");
        feeRecipient = makeAccount("feeRecipient");

        // Deploy Mock WETH
        wethMock = new MockERC20("Wrapped Ether Mock", "WMETH");

        // Deploy MockUniswapRouter
        mockSwapRouter = new MockUniswapRouter();
        // Seed router with WETH and MorpherToken for mock swaps
        wethMock.mint(address(mockSwapRouter), 1_000_000 ether);
        morpherToken.mint(address(mockSwapRouter), 1_000_000 ether); // Assuming morpherToken is mintable by setup

        // Deploy MorpherBridge (or get from BaseSetup if deployed there)
        // For this test, we deploy it directly to control initialization.
        address bridgeImplementation = address(new MorpherBridge());
        bytes memory initializerCall = abi.encodeCall(
            MorpherBridge.initialize,
            (address(morpherState), false, ISwapRouter(address(mockSwapRouter)))
        );
        morpherBridge = MorpherBridge(payable(deployProxy(CONTRACT_KEY_BRIDGE, address(bridgeImplementation), initializerCall)));

        // Set bridge address in state
        vm.prank(address(morpherAdmin)); // Assuming morpherAdmin has role to set addresses in state
        morpherState.setMorpherBridgeAddress(address(morpherBridge));

        // Grant roles on MorpherBridge
        vm.prank(address(morpherAdmin)); // morpherAdmin grants roles via AccessControl
        morpherAccessControl.grantRole(morpherBridge.ADMINISTRATOR_ROLE(), admin.addr);
        vm.prank(address(morpherAdmin));
        morpherAccessControl.grantRole(morpherBridge.SIDECHAINOPERATOR_ROLE(), sidechainOperator.addr);

        // Grant roles on MorpherToken to MorpherBridge for minting/burning
        vm.prank(address(morpherAdmin));
        morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(morpherBridge));
        vm.prank(address(morpherAdmin));
        morpherAccessControl.grantRole(morpherToken.BURNER_ROLE(), address(morpherBridge));

        // Mint some MPH to user1 for testing
        vm.prank(address(morpherAdmin)); // Assuming morpherAdmin has MINTER_ROLE on token
        morpherToken.mint(user1.addr, 1_000_000 ether);

        // Set WETH address in mockSwapRouter (if it has such a setter, or ensure it's known)
        // The mock router provided doesn't have a WETH setter, it's implicit.
        // We'll use our wethMock address when testing functions that need WETH.
        // For functions like getWethWmaticAddress, we might need to etch the mock router's storage
        // or modify the mock router if direct testing of that getter is needed.
        // For now, we assume the bridge's swap logic will correctly get WETH9 from the *actual* router.
        // In our tests, we ensure the mock router *behaves* as if it knows about WETH.
    }

    function testInitializeValues() public {
        assertEq(morpherBridge.withdrawalLimitPerUserDaily(), 200000 ether, "Initial user daily limit");
        assertEq(morpherBridge.withdrawalLimitGlobalDaily(), 3000000 ether, "Initial global daily limit");
        assertEq(address(morpherBridge.state()), address(morpherState), "State address mismatch");
        assertEq(address(morpherBridge.swapRouter()), address(mockSwapRouter), "Swap router mismatch");
        assertEq(morpherBridge.inactivityPeriod(), 3 days, "Inactivity period mismatch");
    }

    function testUpdateSideChainMerkleRoot() public {
        bytes32 newRoot = keccak256("new_merkle_root");
        vm.prank(sidechainOperator.addr);
        vm.expectEmit(true, false, false, true);
        emit SideChainMerkleRootUpdated(newRoot);
        morpherBridge.updateSideChainMerkleRoot(newRoot);
        assertEq(morpherBridge.withdrawalData().merkleRoot, newRoot, "Merkle root not updated");
        assertTrue(morpherBridge.withdrawalData().lastUpdatedAt > 0, "Last updated time not set");

        vm.prank(user1.addr);
        vm.expectRevert("MorpherBridge: Permission denied.");
        morpherBridge.updateSideChainMerkleRoot(keccak256("another_root"));
    }

    function testStageTokensForTransfer() public {
        uint256 tokensToStage = 1000 ether;
        uint256 initialBalance = morpherToken.balanceOf(user1.addr);
        uint256 withdrawalCost = 100 ether;
        uint256 expectedTokensToWithdraw = tokensToStage - withdrawalCost;

        vm.prank(user1.addr);
        vm.expectEmit(true, true, false, true); // from, tokens, totalTokenSent, timeStamp, transferNonce, targetChainId, transferHash
        emit TransferToLinkedChain(user1.addr, expectedTokensToWithdraw, expectedTokensToWithdraw, block.timestamp, 1, 137, bytes32(0)); // transferHash is dynamic
        morpherBridge.stageTokensForTransfer(tokensToStage, 137); // 137 for Polygon mainnet example

        assertEq(morpherToken.balanceOf(user1.addr), initialBalance - tokensToStage, "Tokens not burned correctly");
        (uint256 amountSent, uint256 lastTransferAt) = morpherBridge.tokenSentToLinkedChain(user1.addr, 137);
        assertEq(amountSent, expectedTokensToWithdraw, "tokenSentToLinkedChain amount incorrect");
        assertTrue(lastTransferAt > 0, "tokenSentToLinkedChain lastTransferAt not set");
        assertEq(morpherBridge.bridgeNonce(), 1, "Bridge nonce not incremented");

        // Check withdrawal limits
        assertEq(morpherBridge.withdrawalPerUserPerDay(user1.addr, block.timestamp / ONE_DAY), tokensToStage);
        assertEq(morpherBridge.withdrawalsGlobalDaily(block.timestamp / ONE_DAY), tokensToStage);
    }

    function testClaimStagedTokens() public {
        // 1. Stage tokens (implicitly tested elsewhere, setup state manually for focus)
        // For this test, let's assume operator updates root, then user claims.
        uint256 claimAmount = 500 ether;
        uint256 userClaimLimitOnSidechain = 1000 ether; // User's total available to claim from sidechain

        // Operator updates merkle root
        bytes32[] memory treeElements = new bytes32[](1);
        bytes32 leaf = keccak256(abi.encodePacked(user1.addr, userClaimLimitOnSidechain, block.chainid));
        treeElements[0] = leaf;
        bytes32 merkleRoot = MerkleProof.merkleRoot(treeElements); // Simplified tree for testing

        vm.prank(sidechainOperator.addr);
        morpherBridge.updateSideChainMerkleRoot(merkleRoot);

        // User prepares proof
        bytes32[] memory proof = MerkleProof.generateProof(treeElements, 0);

        uint256 initialUserBalance = morpherToken.balanceOf(user1.addr);

        vm.prank(user1.addr);
        vm.expectEmit(true, false, false, true);
        emit TrustlessWithdrawFromSideChain(user1.addr, claimAmount);
        morpherBridge.claimStagedTokens(claimAmount, userClaimLimitOnSidechain, proof);

        assertEq(morpherToken.balanceOf(user1.addr), initialUserBalance + claimAmount, "Tokens not minted correctly");
        (uint256 amountClaimed, ) = morpherBridge.tokenClaimedOnThisChain(user1.addr);
        assertEq(amountClaimed, claimAmount, "tokenClaimedOnThisChain incorrect");

        // Check withdrawal limits
        assertEq(morpherBridge.withdrawalPerUserPerDay(user1.addr, block.timestamp / ONE_DAY), claimAmount);
        assertEq(morpherBridge.withdrawalsGlobalDaily(block.timestamp / ONE_DAY), claimAmount);

        // Test invalid proof
        bytes32[] memory invalidProof = new bytes32[](0);
        vm.prank(user1.addr);
        vm.expectRevert("MorpherBridge: Merkle Proof failed. Please make sure you entered the correct claim limit.");
        morpherBridge.claimStagedTokens(claimAmount, userClaimLimitOnSidechain, invalidProof);
    }

    function testClaimStagedTokensConvertAndSendForUser_Signature() public {
        uint256 numOfTokenToClaim = 1000 ether;
        uint256 fee = 10 ether;
        uint256 claimLimitOnSidechain = 1500 ether; // User's total available from sidechain

        // User signs the message
        bytes32 messageHash = keccak256(abi.encodePacked(numOfTokenToClaim, user1.addr, block.chainid));
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1.key, ethSignedMessageHash);
        bytes memory userSignature = abi.encodePacked(r, s, v);

        // Operator prepares Merkle tree and proof
        bytes32[] memory treeElements = new bytes32[](1);
        bytes32 leaf = keccak256(abi.encodePacked(user1.addr, claimLimitOnSidechain, block.chainid));
        treeElements[0] = leaf;
        bytes32 merkleRoot = MerkleProof.merkleRoot(treeElements);
        bytes32[] memory proof = MerkleProof.generateProof(treeElements, 0);

        // Mock WETH address (assuming it's what the router would return for WETH9())
        // We need to ensure our mockSwapRouter can handle this.
        // For simplicity, we'll assume the mock router handles the swap correctly if called.
        // The actual WETH address is not directly used by the bridge if the router handles wrapping.

        uint256 initialFeeRecipientBalance = morpherToken.balanceOf(feeRecipient.addr);
        uint256 initialUser1EthBalance = user1.addr.balance;

        // Mock the swap: Bridge will receive (numOfTokenToClaim - fee) MPH, then swap it.
        // MockUniswapRouter's exactInput will transfer (numOfTokenToClaim - fee) from bridge to itself,
        // then transfer some amount of WETH (mocked as ETH for simplicity here) to user1.addr.
        // Let's say 1 MPH = 0.0001 ETH for the mock.
        uint256 tokensToSwap = numOfTokenToClaim - fee;
        uint256 expectedEthOut = tokensToSwap / 10000; // Mock conversion rate
        mockSwapRouter.setAmountOut(expectedEthOut); // Configure mock router for the expected output

        vm.prank(sidechainOperator.addr);
        vm.expectEmit(true, false, false, true); // TrustlessWithdrawFromSideChain
        emit TrustlessWithdrawFromSideChain(user1.addr, numOfTokenToClaim);
        vm.expectEmit(true, false, false, true); // WithdrawalSuccess
        emit WithdrawalSuccess(user1.addr, expectedEthOut, true);

        uint256 returnedAmountOut = morpherBridge.claimStagedTokensConvertAndSendForUser(
            user1.addr,
            numOfTokenToClaim,
            fee,
            feeRecipient.addr,
            claimLimitOnSidechain,
            proof,
            payable(user1.addr),
            merkleRoot,
            userSignature
        );
        assertEq(returnedAmountOut, expectedEthOut, "Returned amountOut from swap incorrect");

        assertEq(morpherBridge.withdrawalData().merkleRoot, merkleRoot, "Merkle root not updated by operator");
        assertEq(morpherToken.balanceOf(feeRecipient.addr), initialFeeRecipientBalance + fee, "Fee not transferred");
        assertEq(user1.addr.balance, initialUser1EthBalance + expectedEthOut, "ETH not received by user");
        (uint256 amountClaimed, ) = morpherBridge.tokenClaimedOnThisChain(user1.addr);
        assertEq(amountClaimed, numOfTokenToClaim, "tokenClaimedOnThisChain incorrect for user");

        // Check withdrawal limits for user1
        assertEq(morpherBridge.withdrawalPerUserPerDay(user1.addr, block.timestamp / ONE_DAY), numOfTokenToClaim);
    }


    function testClaimStagedTokensAndSendForUser_Signature() public {
        uint256 numOfTokenToClaim = 1200 ether;
        uint256 fee = 20 ether;
        uint256 claimLimitOnSidechain = 2000 ether;

        bytes32 messageHash = keccak256(abi.encodePacked(numOfTokenToClaim, user1.addr, block.chainid));
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1.key, ethSignedMessageHash);
        bytes memory userSignature = abi.encodePacked(r, s, v);

        bytes32[] memory treeElements = new bytes32[](1);
        bytes32 leaf = keccak256(abi.encodePacked(user1.addr, claimLimitOnSidechain, block.chainid));
        treeElements[0] = leaf;
        bytes32 merkleRoot = MerkleProof.merkleRoot(treeElements);
        bytes32[] memory proof = MerkleProof.generateProof(treeElements, 0);

        uint256 initialFeeRecipientBalance = morpherToken.balanceOf(feeRecipient.addr);
        uint256 initialUser1MphBalance = morpherToken.balanceOf(user1.addr);
        uint256 expectedMphToUser = numOfTokenToClaim - fee;

        vm.prank(sidechainOperator.addr);
        vm.expectEmit(true, false, false, true); // TrustlessWithdrawFromSideChain
        emit TrustlessWithdrawFromSideChain(user1.addr, numOfTokenToClaim);
        vm.expectEmit(true, false, false, true); // WithdrawalSuccess
        emit WithdrawalSuccess(user1.addr, expectedMphToUser, false); // false because it's ERC20

        uint returnedAmount = morpherBridge.claimStagedTokensAndSendForUser(
            user1.addr,
            numOfTokenToClaim,
            fee,
            feeRecipient.addr,
            claimLimitOnSidechain,
            proof,
            payable(user1.addr),
            merkleRoot,
            userSignature
        );
        assertEq(returnedAmount, expectedMphToUser, "Returned amount incorrect");

        assertEq(morpherBridge.withdrawalData().merkleRoot, merkleRoot, "Merkle root not updated by operator");
        assertEq(morpherToken.balanceOf(feeRecipient.addr), initialFeeRecipientBalance + fee, "Fee not transferred");
        assertEq(morpherToken.balanceOf(user1.addr), initialUser1MphBalance + expectedMphToUser, "MPH not received by user");
        (uint256 amountClaimed, ) = morpherBridge.tokenClaimedOnThisChain(user1.addr);
        assertEq(amountClaimed, numOfTokenToClaim, "tokenClaimedOnThisChain incorrect for user");
    }


    function testWithdrawalLimits_Daily() public {
        uint256 dailyLimit = morpherBridge.withdrawalLimitPerUserDaily(); // 200k
        uint256 amount1 = dailyLimit - 100 ether;
        uint256 amount2 = 50 ether;
        uint256 amount3 = 60 ether; // This will exceed (amount1 + amount2 + amount3 > dailyLimit)

        // User 1: amount1
        vm.prank(user1.addr);
        morpherBridge.stageTokensForTransfer(amount1, 137); // withdrawalCost is 100, so actual tokens staged is amount1-100
                                                          // but limits are checked on `tokensToStage` which is `amount1`

        // User 1: amount2
        vm.prank(user1.addr);
        morpherBridge.stageTokensForTransfer(amount2, 137);

        uint256 totalForUser1 = amount1 + amount2;
        assertEq(morpherBridge.withdrawalPerUserPerDay(user1.addr, block.timestamp / ONE_DAY), totalForUser1);

        // User 1: amount3 - should fail
        vm.prank(user1.addr);
        vm.expectRevert("MorpherBridge: Withdrawal Amount exceeds daily limit");
        morpherBridge.stageTokensForTransfer(amount3, 137);

        // Warp time to next day
        vm.warp(block.timestamp + 1 days + 1 hours);

        // User 1: amount3 - should succeed now
        vm.prank(user1.addr);
        morpherBridge.stageTokensForTransfer(amount3, 137);
        assertEq(morpherBridge.withdrawalPerUserPerDay(user1.addr, block.timestamp / ONE_DAY), amount3);
    }

    // --- Helper to deploy proxy for tests ---
    string constant CONTRACT_KEY_BRIDGE = "MorpherBridgeTestInstance";
    function deployProxy(string memory contractKey, address implementation, bytes memory initializeData) internal returns (address payable proxyAddress) {
        if (UPGRADE_PROXY_PATTERN) {
            proxyAddress = payable(Upgrades.deployUUPSProxy(contractKey, implementation, initializeData));
        } else {
            // Simplified proxy deployment for testing if not using full UUPS pattern from BaseSetup
            // This part might need adjustment based on how BaseSetup handles proxy deployments
            // For now, assume a direct deployment or a simple proxy pattern if Upgrades lib isn't fully set up for this context
            revert("UPGRADE_PROXY_PATTERN not set or simple proxy not implemented here");
        }
    }
}
