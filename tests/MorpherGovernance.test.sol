// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./BaseSetup.sol";
import "../contracts/MorpherGovernor.sol";
import "../contracts/MorpherTimelockController.sol";
import {TimelockControllerUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/governance/TimelockControllerUpgradeable.sol";
import {ERC1967Proxy} from "../lib/openzeppelin-contracts-5/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IGovernor} from "../lib/openzeppelin-contracts-5/contracts/governance/IGovernor.sol";

/**
 * @title MorpherGovernance Tests
 * @notice Tests for the MorpherGovernor and ERC20Votes extension
 */
contract MorpherGovernanceTest is BaseSetup {
    MorpherGovernor internal governor;
    MorpherTimelockController internal timelock;

    // Test accounts
    address internal voter1;
    address internal voter2;
    address internal proposer;

    // Governance parameters matching deployment script
    uint48 constant VOTING_DELAY = 43200; // ~1 day
    uint32 constant VOTING_PERIOD = 302400; // ~7 days
    uint256 constant PROPOSAL_THRESHOLD = 10_000_000 ether; // 10M MPH
    uint256 constant TIMELOCK_MIN_DELAY = 2 days;

    function setUp() public override {
        super.setUp();

        // Create test accounts
        voter1 = makeAddr("voter1");
        voter2 = makeAddr("voter2");
        proposer = makeAddr("proposer");

        // Grant admin role to test contract for setup
        morpherAccessControl.grantRole(morpherState.ADMINISTRATOR_ROLE(), address(this));

        // Deploy TimelockController
        _deployTimelock();

        // Deploy MorpherGovernor
        _deployGovernor();

        // Mint tokens to test accounts
        morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(this));
        morpherToken.mint(proposer, 50_000_000 ether); // 50M MPH - enough to propose
        morpherToken.mint(voter1, 100_000_000 ether); // 100M MPH
        morpherToken.mint(voter2, 100_000_000 ether); // 100M MPH
        morpherAccessControl.revokeRole(morpherToken.MINTER_ROLE(), address(this));
    }

    function _deployTimelock() internal {
        // Deploy MorpherTimelockController implementation
        MorpherTimelockController impl = new MorpherTimelockController();

        // Setup timelock with MorpherState reference and open execution
        bytes memory initData = abi.encodeCall(
            MorpherTimelockController.initialize,
            (address(morpherState), TIMELOCK_MIN_DELAY, true) // true = open execution
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        timelock = MorpherTimelockController(payable(address(proxy)));

        // Grant DEFAULT_ADMIN_ROLE to test contract for setup (used by updateDelay)
        // Note: TIMELOCK_ADMIN_ROLE exists but our hasRole override delegates to MorpherAccessControl
        morpherAccessControl.grantRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));
    }

    function _deployGovernor() internal {
        // Deploy MorpherGovernor implementation
        MorpherGovernor impl = new MorpherGovernor();

        bytes memory initData = abi.encodeCall(
            MorpherGovernor.initialize,
            (
                address(morpherState),
                TimelockControllerUpgradeable(payable(address(timelock))),
                VOTING_DELAY,
                VOTING_PERIOD,
                PROPOSAL_THRESHOLD
            )
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        governor = MorpherGovernor(payable(address(proxy)));

        // Grant Governor roles via MorpherAccessControl
        // PROPOSER_ROLE and CANCELLER_ROLE (standard OZ Timelock roles)
        morpherAccessControl.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        morpherAccessControl.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        // Grant Timelock roles on AccessControl for protocol operations
        morpherAccessControl.grantRole(morpherAccessControl.PROXYUPDATER_ROLE(), address(timelock));
        morpherAccessControl.grantRole(keccak256("ADMINISTRATOR_ROLE"), address(timelock));
    }

    // ============ Token Delegation Tests ============

    function testDelegation() public {
        // Initially, voting power is 0 (no self-delegation)
        assertEq(morpherToken.getVotes(voter1), 0);

        // Self-delegate
        vm.prank(voter1);
        morpherToken.delegate(voter1);

        // Now voting power equals balance
        assertEq(morpherToken.getVotes(voter1), morpherToken.balanceOf(voter1));
    }

    function testDelegationToAnother() public {
        // voter1 delegates to voter2
        vm.prank(voter1);
        morpherToken.delegate(voter2);

        // voter2 delegates to self
        vm.prank(voter2);
        morpherToken.delegate(voter2);

        // voter2 should have both balances as voting power
        assertEq(morpherToken.getVotes(voter2), morpherToken.balanceOf(voter1) + morpherToken.balanceOf(voter2));
        assertEq(morpherToken.getVotes(voter1), 0);
    }

    // ============ Voting Power Tests ============

    function testVotingPowerExcludesLockedRewards() public {
        uint256 initialBalance = morpherToken.balanceOf(voter1);

        // Lock some rewards
        morpherAccessControl.grantRole(morpherToken.AIRDROPADMIN_ROLE(), address(this));
        morpherToken.lockRewards(voter1, 10_000_000 ether);

        // Self-delegate
        vm.prank(voter1);
        morpherToken.delegate(voter1);

        // Voting power should exclude locked rewards
        assertEq(morpherToken.getVotes(voter1), initialBalance - 10_000_000 ether);
    }

    function testVotingPowerExcludesTimeLocks() public {
        uint256 initialBalance = morpherToken.balanceOf(voter1);

        // Lock some tokens for time
        morpherAccessControl.grantRole(morpherToken.AIRDROPADMIN_ROLE(), address(this));
        morpherToken.lockTokensForTime(voter1, 20_000_000 ether, 30 days);

        // Self-delegate
        vm.prank(voter1);
        morpherToken.delegate(voter1);

        // Voting power should exclude time-locked tokens
        assertEq(morpherToken.getVotes(voter1), initialBalance - 20_000_000 ether);
    }

    // ============ Circulating Supply Tests ============

    function testCirculatingSupplyBasic() public {
        // Get initial circulating supply (should equal total supply since no locks)
        uint256 totalSupply = morpherToken.totalSupply();
        uint256 circulatingSupply = morpherToken.getCirculatingSupply();

        // Note: totalSupply() adds _totalTokensInPositions, getCirculatingSupply uses super.totalSupply()
        // They should be close but not necessarily equal depending on positions
        assertTrue(circulatingSupply > 0);
    }

    function testCirculatingSupplyExcludesLockedRewards() public {
        uint256 initialCirculating = morpherToken.getCirculatingSupply();

        // Lock some rewards
        morpherAccessControl.grantRole(morpherToken.AIRDROPADMIN_ROLE(), address(this));
        morpherToken.lockRewards(voter1, 10_000_000 ether);

        uint256 newCirculating = morpherToken.getCirculatingSupply();

        // Circulating supply should decrease by locked amount
        assertEq(newCirculating, initialCirculating - 10_000_000 ether);
    }

    function testCirculatingSupplyExcludesTimeLocks() public {
        uint256 initialCirculating = morpherToken.getCirculatingSupply();

        // Lock some tokens
        morpherAccessControl.grantRole(morpherToken.AIRDROPADMIN_ROLE(), address(this));
        morpherToken.lockTokensForTime(voter1, 20_000_000 ether, 30 days);

        uint256 newCirculating = morpherToken.getCirculatingSupply();

        // Circulating supply should decrease by locked amount
        assertEq(newCirculating, initialCirculating - 20_000_000 ether);
    }

    function testCleanupExpiredTimeLocks() public {
        // Lock some tokens
        morpherAccessControl.grantRole(morpherToken.AIRDROPADMIN_ROLE(), address(this));
        morpherToken.lockTokensForTime(voter1, 20_000_000 ether, 30 days);

        uint256 circulatingBeforeExpiry = morpherToken.getCirculatingSupply();

        // Warp past expiry
        vm.warp(block.timestamp + 31 days);

        // Circulating supply still shows reduced (stale)
        assertEq(morpherToken.getCirculatingSupply(), circulatingBeforeExpiry);

        // Cleanup expired locks
        address[] memory accounts = new address[](1);
        accounts[0] = voter1;
        morpherToken.cleanupExpiredTimeLocks(accounts);

        // Now circulating supply should be restored
        assertEq(morpherToken.getCirculatingSupply(), circulatingBeforeExpiry + 20_000_000 ether);
    }

    // ============ Quorum Tests ============

    function testQuorumCalculation() public {
        uint256 circulatingSupply = morpherToken.getCirculatingSupply();
        uint256 expectedQuorum = (circulatingSupply * 51) / 100;

        // Mine a block for timepoint
        vm.roll(block.number + 1);

        assertEq(governor.quorum(block.number - 1), expectedQuorum);
    }

    // ============ Proposal Threshold Tests ============

    function testProposalThreshold() public {
        assertEq(governor.proposalThreshold(), PROPOSAL_THRESHOLD);
    }

    function testCannotProposeWithoutEnoughTokens() public {
        // Create account with less than threshold
        address smallHolder = makeAddr("smallHolder");
        morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(this));
        morpherToken.mint(smallHolder, 1_000_000 ether); // 1M MPH (need 10M)
        morpherAccessControl.revokeRole(morpherToken.MINTER_ROLE(), address(this));

        // Self-delegate
        vm.prank(smallHolder);
        morpherToken.delegate(smallHolder);

        // Mine a block to record checkpoint
        vm.roll(block.number + 1);

        // Try to propose
        address[] memory targets = new address[](1);
        targets[0] = address(morpherToken);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(morpherToken.pause, ());

        vm.prank(smallHolder);
        vm.expectRevert(); // Should revert due to insufficient voting power
        governor.propose(targets, values, calldatas, "Test proposal");
    }

    // ============ Full Proposal Lifecycle Tests ============

    function testFullProposalLifecycle() public {
        // Setup: delegate tokens to self
        vm.prank(proposer);
        morpherToken.delegate(proposer);
        vm.prank(voter1);
        morpherToken.delegate(voter1);
        vm.prank(voter2);
        morpherToken.delegate(voter2);

        // Mine a block to record checkpoints
        vm.roll(block.number + 1);

        // Grant PAUSER_ROLE to timelock for the test
        morpherAccessControl.grantRole(morpherToken.PAUSER_ROLE(), address(timelock));

        // 1. Create proposal
        address[] memory targets = new address[](1);
        targets[0] = address(morpherToken);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(morpherToken.pause, ());
        string memory description = "Proposal to pause token";

        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Check proposal is pending
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));

        // 2. Wait for voting delay
        vm.roll(block.number + VOTING_DELAY + 1);

        // Check proposal is active
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active));

        // 3. Vote
        vm.prank(voter1);
        governor.castVote(proposalId, 1); // Vote for

        vm.prank(voter2);
        governor.castVote(proposalId, 1); // Vote for

        // 4. Wait for voting period to end
        vm.roll(block.number + VOTING_PERIOD + 1);

        // Check proposal succeeded
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));

        // 5. Queue the proposal
        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        // Check proposal is queued
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued));

        // 6. Wait for timelock delay
        vm.warp(block.timestamp + TIMELOCK_MIN_DELAY + 1);

        // 7. Execute the proposal
        governor.execute(targets, values, calldatas, descriptionHash);

        // Check proposal is executed
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));

        // Verify the action was executed - token should be paused
        assertTrue(morpherToken.paused());
    }

    function testProposalFailsWithoutQuorum() public {
        // Setup: only proposer delegates (not enough for quorum)
        vm.prank(proposer);
        morpherToken.delegate(proposer);

        vm.roll(block.number + 1);

        // Create proposal
        address[] memory targets = new address[](1);
        targets[0] = address(morpherToken);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(morpherToken.pause, ());

        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        // Wait for voting delay
        vm.roll(block.number + VOTING_DELAY + 1);

        // Only proposer votes (50M MPH - less than 51% quorum)
        vm.prank(proposer);
        governor.castVote(proposalId, 1);

        // Wait for voting period
        vm.roll(block.number + VOTING_PERIOD + 1);

        // Proposal should be defeated (not enough quorum)
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
    }

    // ============ Timelock Tests ============

    function testTimelockDelay() public {
        // Setup delegation
        vm.prank(proposer);
        morpherToken.delegate(proposer);
        vm.prank(voter1);
        morpherToken.delegate(voter1);
        vm.prank(voter2);
        morpherToken.delegate(voter2);

        vm.roll(block.number + 1);

        morpherAccessControl.grantRole(morpherToken.PAUSER_ROLE(), address(timelock));

        // Create and pass proposal
        address[] memory targets = new address[](1);
        targets[0] = address(morpherToken);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(morpherToken.pause, ());
        string memory description = "Test timelock delay";

        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(voter1);
        governor.castVote(proposalId, 1);
        vm.prank(voter2);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);

        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        // Try to execute before timelock delay - should fail
        vm.expectRevert();
        governor.execute(targets, values, calldatas, descriptionHash);

        // Wait for timelock delay
        vm.warp(block.timestamp + TIMELOCK_MIN_DELAY + 1);

        // Now execution should succeed
        governor.execute(targets, values, calldatas, descriptionHash);
    }

    // ============ Governor Settings Tests ============

    function testGovernorSettings() public {
        assertEq(governor.votingDelay(), VOTING_DELAY);
        assertEq(governor.votingPeriod(), VOTING_PERIOD);
        assertEq(governor.proposalThreshold(), PROPOSAL_THRESHOLD);
    }

    function testGovernorName() public {
        assertEq(governor.name(), "MorpherGovernor");
    }

    // ============ Nonces Tests (Diamond Inheritance) ============

    function testNoncesFunction() public {
        // Test that nonces function works (resolving diamond inheritance)
        uint256 nonce = morpherToken.nonces(voter1);
        assertEq(nonce, 0); // Should start at 0
    }
}
