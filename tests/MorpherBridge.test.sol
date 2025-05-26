// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
// import {Upgrades} from "forge-std/Upgrades.sol"; // Removed import for Upgrades
import {ECDSA} from "../lib/openzeppelin-contracts-5/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "../lib/openzeppelin-contracts-5/contracts/utils/cryptography/MessageHashUtils.sol";
import {Merkle} from "../lib/murky/src/Merkle.sol"; // Changed to Murky Merkle

import "./BaseSetup.sol";
import "./mocks/ERC20.sol"; // Assuming MorpherToken is ERC20-like for testing burn/mint
import "./mocks/UniswapRouter.sol"; // Mock Uniswap Router
import "../contracts/MorpherBridge.sol";
import "../contracts/MorpherToken.sol"; // For MINTER_ROLE, BURNER_ROLE constants
import {IWETH9} from '../lib/uniswap-v3-periphery/contracts/interfaces/external/IWETH9.sol'; // For WETH9 address from router

contract MorpherBridgeTest is BaseSetup {
    using MessageHashUtils for bytes32;

    // MorpherBridge is now inherited from BaseSetup
    // bool constant UPGRADE_PROXY_PATTERN = true; // Removed

    // MorpherBridge internal morpherBridge; // Inherited
    MockUniswapRouter internal mockSwapRouter; // Keep mock router for specific bridge tests
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
        console.log("user1.addr:", user1.addr);
        console.log("address(this) for MorpherBridgeTest:", address(this));
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

        // Grant MINTER_ROLE to the admin account for minting tokens
        vm.prank(address(this)); // address(this) should have DEFAULT_ADMIN_ROLE from BaseSetup
        morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), admin.addr);

        // Minting to mockSwapRouter needs MINTER_ROLE for admin.addr
        vm.prank(admin.addr); 
        morpherToken.mint(address(mockSwapRouter), 1_000_000 ether);

        // Grant ADMINISTRATOR_ROLE on MorpherBridge to test's admin account
        vm.prank(address(this)); // address(this) has DEFAULT_ADMIN_ROLE on MorpherAccessControl
        morpherAccessControl.grantRole(morpherBridge.ADMINISTRATOR_ROLE(), admin.addr);
        
        // Grant SIDECHAINOPERATOR_ROLE on MorpherBridge to test's sidechainOperator account
        vm.prank(address(this)); // address(this) has DEFAULT_ADMIN_ROLE on MorpherAccessControl
        morpherAccessControl.grantRole(morpherBridge.SIDECHAINOPERATOR_ROLE(), sidechainOperator.addr);

        // MorpherBridge is now deployed and initialized in BaseSetup.
        // We need to update its swapRouter to the mockSwapRouter for these tests.
        vm.prank(admin.addr); // Now admin.addr has ADMINISTRATOR_ROLE on the bridge
        morpherBridge.updateSwapRouter(ISwapRouter(address(mockSwapRouter)));

        // Mint some MPH to user1 for testing
        vm.prank(admin.addr); // Assuming admin has MINTER_ROLE on token
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
        (bytes32 updatedMerkleRoot, uint256 updatedLastAt) = morpherBridge.withdrawalData();
        assertEq(updatedMerkleRoot, newRoot, "Merkle root not updated");
        assertTrue(updatedLastAt > 0, "Last updated time not set");

        vm.prank(user1.addr);
        vm.expectRevert("MorpherBridge: Permission denied.");
        morpherBridge.updateSideChainMerkleRoot(keccak256("another_root"));
    }

    function testStageTokensForTransfer() public {
        // Inlined: tokensToStage = 1000 ether; withdrawalCost = 100 ether; expectedTokensToWithdraw = 1000 ether - 100 ether;
        uint256 initialBalance = morpherToken.balanceOf(user1.addr); // Keep this as it's used before the state change

        vm.prank(user1.addr);
        vm.expectEmit(true, true, false, true); // from, tokens, totalTokenSent, timeStamp, transferNonce, targetChainId, transferHash
        emit TransferToLinkedChain(user1.addr, (1000 ether - 100 ether), (1000 ether - 100 ether), block.timestamp, 1, 137, bytes32(0)); // transferHash is dynamic
        morpherBridge.stageTokensForTransfer(1000 ether, 137); // 137 for Polygon mainnet example

        assertEq(morpherToken.balanceOf(user1.addr), initialBalance - (1000 ether), "Tokens not burned correctly");
        (uint256 amountSent, uint256 lastTransferAt) = morpherBridge.tokenSentToLinkedChain(user1.addr, 137);
        assertEq(amountSent, (1000 ether - 100 ether), "tokenSentToLinkedChain amount incorrect");
        assertTrue(lastTransferAt > 0, "tokenSentToLinkedChain lastTransferAt not set");
        assertEq(morpherBridge.bridgeNonce(), 1, "Bridge nonce not incremented");

        // Check withdrawal limits
        assertEq(morpherBridge.withdrawalPerUserPerDay(user1.addr, block.timestamp / ONE_DAY), (1000 ether));
        assertEq(morpherBridge.withdrawalsGlobalDaily(block.timestamp / ONE_DAY), (1000 ether));
    }

    function testClaimStagedTokens() public {
        // 1. Stage tokens (implicitly tested elsewhere, setup state manually for focus)
        // For this test, let's assume operator updates root, then user claims.
        // Inlined: claimAmount = 500 ether; userClaimLimitOnSidechain = 1000 ether;

        // Operator updates merkle root
        bytes32[] memory treeElements = new bytes32[](2); // Changed size to 2
        // Inlined: leaf = keccak256(abi.encodePacked(user1.addr, uint256(1000 ether), block.chainid));
        treeElements[0] = keccak256(abi.encodePacked(user1.addr, uint256(1000 ether), block.chainid));
        treeElements[1] = keccak256(abi.encodePacked("dummyLeaf1")); // Added dummy leaf
        
        Merkle m = new Merkle(); // Use Murky
        // Inlined: merkleRoot = m.getRoot(treeElements);
        vm.prank(sidechainOperator.addr);
        morpherBridge.updateSideChainMerkleRoot(m.getRoot(treeElements));

        // User prepares proof
        // Inlined: proof = m.getProof(treeElements, 0);
        uint256 initialUserBalance = morpherToken.balanceOf(user1.addr); // Keep this

        vm.prank(user1.addr);
        vm.expectEmit(true, false, false, true);
        emit TrustlessWithdrawFromSideChain(user1.addr, 500 ether);
        morpherBridge.claimStagedTokens(500 ether, 1000 ether, m.getProof(treeElements, 0));

        assertEq(morpherToken.balanceOf(user1.addr), initialUserBalance + (500 ether), "Tokens not minted correctly");
        (uint256 amountClaimed, ) = morpherBridge.tokenClaimedOnThisChain(user1.addr);
        assertEq(amountClaimed, (500 ether), "tokenClaimedOnThisChain incorrect");

        // Check withdrawal limits
        assertEq(morpherBridge.withdrawalPerUserPerDay(user1.addr, block.timestamp / ONE_DAY), (500 ether));
        assertEq(morpherBridge.withdrawalsGlobalDaily(block.timestamp / ONE_DAY), (500 ether));

        // Test invalid proof
        bytes32[] memory invalidProof = new bytes32[](0);
        vm.prank(user1.addr);
        vm.expectRevert("MorpherBridge: Merkle Proof failed. Please make sure you entered the correct claim limit.");
        morpherBridge.claimStagedTokens(500 ether, 1000 ether, invalidProof);
    }

    function testClaimStagedTokensConvertAndSendForUser_Signature() public {
        // Inlined: numOfTokenToClaim = 1000 ether; fee = 10 ether; claimLimitOnSidechain = 1500 ether;
        
        // User signs the message
        // Inlined: messageHash = keccak256(abi.encodePacked(uint256(1000 ether), user1.addr, block.chainid));
        // Inlined: ethSignedMessageHash = keccak256(abi.encodePacked(uint256(1000 ether), user1.addr, block.chainid)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1.key, keccak256(abi.encodePacked(uint256(1000 ether), user1.addr, block.chainid)).toEthSignedMessageHash());
        bytes memory userSignature = abi.encodePacked(r, s, v); // Re-introduce userSignature variable

        // Operator prepares Merkle tree and proof
        bytes32[] memory treeElements = new bytes32[](2); // Changed size to 2
        // Inlined: leaf = keccak256(abi.encodePacked(user1.addr, uint256(1500 ether), block.chainid));
        treeElements[0] = keccak256(abi.encodePacked(user1.addr, uint256(1500 ether), block.chainid));
        treeElements[1] = keccak256(abi.encodePacked("dummyLeaf2")); // Added dummy leaf

        Merkle m = new Merkle(); // Use Murky
        // Inlined: merkleRoot = m.getRoot(treeElements);
        // Inlined: proof = m.getProof(treeElements, 0);
        
        uint256 initialFeeRecipientBalance = morpherToken.balanceOf(feeRecipient.addr); // Keep
        uint256 initialUser1EthBalance = user1.addr.balance; // Keep
        
        // Inlined: tokensToSwap = 1000 ether - 10 ether;
        // Inlined: expectedEthOut = (1000 ether - 10 ether) / 10000;
        mockSwapRouter.setAmountOut(((1000 ether - 10 ether) / 10000)); 

        vm.prank(sidechainOperator.addr);
        vm.expectEmit(true, false, false, true); // TrustlessWithdrawFromSideChain
        emit TrustlessWithdrawFromSideChain(user1.addr, 1000 ether);
        vm.expectEmit(true, false, false, true); // WithdrawalSuccess
        emit WithdrawalSuccess(user1.addr, ((1000 ether - 10 ether) / 10000), true);

        uint256 returnedAmountOut = morpherBridge.claimStagedTokensConvertAndSendForUser(
            user1.addr,
            1000 ether, // numOfTokenToClaim
            10 ether,   // fee
            feeRecipient.addr,
            1500 ether, // claimLimitOnSidechain
            m.getProof(treeElements, 0), // proof
            payable(user1.addr),
            m.getRoot(treeElements), // merkleRoot
            userSignature // Pass the pre-calculated variable
        );
        assertEq(returnedAmountOut, ((1000 ether - 10 ether) / 10000), "Returned amountOut from swap incorrect");

        (bytes32 currentMerkleRoot, ) = morpherBridge.withdrawalData();
        assertEq(currentMerkleRoot, m.getRoot(treeElements), "Merkle root not updated by operator");
        assertEq(morpherToken.balanceOf(feeRecipient.addr), initialFeeRecipientBalance + (10 ether), "Fee not transferred");
        assertEq(user1.addr.balance, initialUser1EthBalance + ((1000 ether - 10 ether) / 10000), "ETH not received by user");
        (uint256 amountClaimed, ) = morpherBridge.tokenClaimedOnThisChain(user1.addr);
        assertEq(amountClaimed, (1000 ether), "tokenClaimedOnThisChain incorrect for user");

        // Check withdrawal limits for user1
        assertEq(morpherBridge.withdrawalPerUserPerDay(user1.addr, block.timestamp / ONE_DAY), (1000 ether));
    }


    function testClaimStagedTokensAndSendForUser_Signature() public {
        // Inlined: numOfTokenToClaim = 1200 ether; fee = 20 ether; claimLimitOnSidechain = 2000 ether;

        // Inlined: messageHash = keccak256(abi.encodePacked(uint256(1200 ether), user1.addr, block.chainid));
        // Inlined: ethSignedMessageHash = keccak256(abi.encodePacked(uint256(1200 ether), user1.addr, block.chainid)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1.key, keccak256(abi.encodePacked(uint256(1200 ether), user1.addr, block.chainid)).toEthSignedMessageHash());
        bytes memory userSignature = abi.encodePacked(r, s, v); // Re-introduce userSignature variable

        bytes32[] memory treeElements = new bytes32[](2); // Changed size to 2
        // Inlined: leaf = keccak256(abi.encodePacked(user1.addr, uint256(2000 ether), block.chainid));
        treeElements[0] = keccak256(abi.encodePacked(user1.addr, uint256(2000 ether), block.chainid));
        treeElements[1] = keccak256(abi.encodePacked("dummyLeaf3")); // Added dummy leaf

        Merkle m = new Merkle(); // Use Murky
        // Inlined: merkleRoot = m.getRoot(treeElements);
        // Inlined: proof = m.getProof(treeElements, 0);

        uint256 initialFeeRecipientBalance = morpherToken.balanceOf(feeRecipient.addr); // Keep
        uint256 initialUser1MphBalance = morpherToken.balanceOf(user1.addr); // Keep
        // Inlined: expectedMphToUser = 1200 ether - 20 ether;

        vm.prank(sidechainOperator.addr);
        vm.expectEmit(true, false, false, true); // TrustlessWithdrawFromSideChain
        emit TrustlessWithdrawFromSideChain(user1.addr, 1200 ether);
        vm.expectEmit(true, false, false, true); // WithdrawalSuccess
        emit WithdrawalSuccess(user1.addr, (1200 ether - 20 ether), false); // false because it's ERC20

        uint returnedAmount = morpherBridge.claimStagedTokensAndSendForUser(
            user1.addr,
            1200 ether, // numOfTokenToClaim
            20 ether,   // fee
            feeRecipient.addr,
            2000 ether, // claimLimitOnSidechain
            m.getProof(treeElements, 0), // proof
            payable(user1.addr),
            m.getRoot(treeElements), // merkleRoot
            userSignature // Pass the pre-calculated variable
        );
        assertEq(returnedAmount, (1200 ether - 20 ether), "Returned amount incorrect");

        (bytes32 currentMerkleRootUser, ) = morpherBridge.withdrawalData();
        assertEq(currentMerkleRootUser, m.getRoot(treeElements), "Merkle root not updated by operator");
        assertEq(morpherToken.balanceOf(feeRecipient.addr), initialFeeRecipientBalance + (20 ether), "Fee not transferred");
        assertEq(morpherToken.balanceOf(user1.addr), initialUser1MphBalance + (1200 ether - 20 ether), "MPH not received by user");
        (uint256 amountClaimed, ) = morpherBridge.tokenClaimedOnThisChain(user1.addr);
        assertEq(amountClaimed, (1200 ether), "tokenClaimedOnThisChain incorrect for user");
    }


    function testWithdrawalLimits_Daily() public {
        uint256 dailyUserLimit = morpherBridge.withdrawalLimitPerUserDaily(); // 200k ether
        uint256 val1 = 100000 ether; // Must be >= 100 ether (withdrawalCost)
        uint256 val2 = 99900 ether;  // Must be >= 100 ether (withdrawalCost)
        uint256 val3_fail = 101 ether; // Must be >= 100 ether. (val1 + val2 + val3_fail > dailyUserLimit)
        uint256 val4_next_day = 150 ether; // Must be >= 100 ether

        require(val1 >= 100 ether && val2 >= 100 ether && val3_fail >= 100 ether && val4_next_day >= 100 ether, "Test values < withdrawalCost");
        require(val1 + val2 <= dailyUserLimit, "Test setup error: val1 + val2 exceeds limit");
        require(val1 + val2 + val3_fail > dailyUserLimit, "Test setup error: val1 + val2 + val3_fail does not exceed limit");

        vm.startPrank(user1.addr);
        
        // User 1: val1
        morpherBridge.stageTokensForTransfer(val1, 137); 
                                                          
        // User 1: val2
        morpherBridge.stageTokensForTransfer(val2, 137);

        uint256 totalStagedDay1 = val1 + val2;
        assertEq(morpherBridge.withdrawalPerUserPerDay(user1.addr, block.timestamp / ONE_DAY), totalStagedDay1);

        // User 1: val3_fail - should fail
        vm.expectRevert("MorpherBridge: Withdrawal Amount exceeds daily limit");
        morpherBridge.stageTokensForTransfer(val3_fail, 137);

        // Warp time to next day
        vm.warp(block.timestamp + 1 days + 1 hours);

        // User 1: val4_next_day - should succeed now
        morpherBridge.stageTokensForTransfer(val4_next_day, 137);
        assertEq(morpherBridge.withdrawalPerUserPerDay(user1.addr, block.timestamp / ONE_DAY), val4_next_day);
        
        vm.stopPrank();
    }

    // --- Helper to deploy proxy for tests --- // Removed as bridge is deployed in BaseSetup
    // string constant CONTRACT_KEY_BRIDGE = "MorpherBridgeTestInstance";
    // function deployProxy(string memory contractKey, address implementation, bytes memory initializeData) internal returns (address payable proxyAddress) {
    //     if (UPGRADE_PROXY_PATTERN) {
    //         proxyAddress = payable(Upgrades.deployUUPSProxy(contractKey, implementation, initializeData));
    //     } else {
    //         revert("UPGRADE_PROXY_PATTERN not set or simple proxy not implemented here");
    //     }
    // }
}
