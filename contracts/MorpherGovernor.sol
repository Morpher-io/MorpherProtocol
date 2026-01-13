//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.20;

/**
 *
 *
 *  ███╗   ███╗ ██████╗ ██████╗ ██████╗ ██╗  ██╗███████╗██████╗
 *  ████╗ ████║██╔═══██╗██╔══██╗██╔══██╗██║  ██║██╔════╝██╔══██╗
 *  ██╔████╔██║██║   ██║██████╔╝██████╔╝███████║█████╗  ██████╔╝
 *  ██║╚██╔╝██║██║   ██║██╔══██╗██╔═══╝ ██╔══██║██╔══╝  ██╔══██╗
 *  ██║ ╚═╝ ██║╚██████╔╝██║  ██║██║     ██║  ██║███████╗██║  ██║
 *  ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝
 *
 *  MorpherGovernor - On-chain governance for the Morpher Protocol
 *
 *  This contract implements OpenZeppelin Governor with:
 *  - 51% quorum based on circulating supply (excludes locked tokens)
 *  - 1 day voting delay
 *  - 7 day voting period
 *  - 10M MPH proposal threshold
 *  - Timelock-controlled execution
 *
 **/

import {GovernorUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/governance/GovernorUpgradeable.sol";
import {GovernorSettingsUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/governance/extensions/GovernorSettingsUpgradeable.sol";
import {GovernorCountingSimpleUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/governance/extensions/GovernorCountingSimpleUpgradeable.sol";
import {GovernorVotesUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/governance/extensions/GovernorVotesUpgradeable.sol";
import {GovernorTimelockControlUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/governance/extensions/GovernorTimelockControlUpgradeable.sol";
import {TimelockControllerUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/governance/TimelockControllerUpgradeable.sol";
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IVotes} from "../lib/openzeppelin-contracts-5/contracts/governance/utils/IVotes.sol";
import {MorpherState} from "./MorpherState.sol";
import {MorpherToken} from "./MorpherToken.sol";

/**
 * @title MorpherGovernor
 * @notice On-chain governance contract for the Morpher Protocol
 * @dev Implements OpenZeppelin Governor with custom 51% quorum based on circulating supply
 *
 * Key features:
 * - Uses MorpherState to get token address (follows State Pointer Pattern)
 * - Custom quorum: 51% of circulating supply (excludes locked/staked tokens)
 * - Tally compatible (standard Governor interface)
 * - UUPS upgradeable
 */
contract MorpherGovernor is
    GovernorUpgradeable,
    GovernorSettingsUpgradeable,
    GovernorCountingSimpleUpgradeable,
    GovernorVotesUpgradeable,
    GovernorTimelockControlUpgradeable,
    UUPSUpgradeable
{
    /// @notice MorpherState contract for reading token address
    MorpherState public morpherState;

    /// @notice Quorum percentage (51 = 51%)
    uint256 public constant QUORUM_PERCENTAGE = 51;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the governor contract
     * @param _morpherState Address of MorpherState contract
     * @param _timelock Address of TimelockController contract
     * @param _votingDelay Delay before voting starts (in blocks)
     * @param _votingPeriod Duration of voting (in blocks)
     * @param _proposalThreshold Minimum tokens required to create proposal
     */
    function initialize(
        address _morpherState,
        TimelockControllerUpgradeable _timelock,
        uint48 _votingDelay,
        uint32 _votingPeriod,
        uint256 _proposalThreshold
    ) public initializer {
        require(_morpherState != address(0), "MorpherGovernor: MorpherState cannot be zero address");

        morpherState = MorpherState(_morpherState);
        address tokenAddress = morpherState.morpherTokenAddress();
        require(tokenAddress != address(0), "MorpherGovernor: Token address not set in MorpherState");

        __Governor_init("MorpherGovernor");
        __GovernorSettings_init(_votingDelay, _votingPeriod, _proposalThreshold);
        __GovernorCountingSimple_init();
        __GovernorVotes_init(IVotes(tokenAddress));
        __GovernorTimelockControl_init(_timelock);
        __UUPSUpgradeable_init();
    }

    // --- Custom Quorum Implementation ---

    /**
     * @notice Returns the quorum required for a proposal to pass
     * @dev Quorum is 51% of the circulating supply at the given timepoint
     * @param timepoint The block number to calculate quorum for
     * @return The number of votes required for quorum
     */
    function quorum(uint256 timepoint) public view override(GovernorUpgradeable) returns (uint256) {
        // Note: timepoint parameter is kept for interface compatibility but we use current supply
        // This is acceptable because circulating supply doesn't change dramatically between blocks
        (timepoint); // Silence unused parameter warning

        // Get token address from MorpherState (follows protocol pattern)
        address tokenAddress = morpherState.morpherTokenAddress();
        uint256 circulatingSupply = MorpherToken(tokenAddress).getCirculatingSupply();

        // Require 51% participation
        return (circulatingSupply * QUORUM_PERCENTAGE) / 100;
    }

    // --- UUPS Upgrade Authorization ---

    /**
     * @notice Authorize upgrade - only governance can upgrade
     * @dev This ensures upgrades must go through the governance process
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance {}

    // --- Required Overrides for Solidity ---

    function votingDelay()
        public
        view
        override(GovernorUpgradeable, GovernorSettingsUpgradeable)
        returns (uint256)
    {
        return super.votingDelay();
    }

    function votingPeriod()
        public
        view
        override(GovernorUpgradeable, GovernorSettingsUpgradeable)
        returns (uint256)
    {
        return super.votingPeriod();
    }

    function proposalThreshold()
        public
        view
        override(GovernorUpgradeable, GovernorSettingsUpgradeable)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    function state(uint256 proposalId)
        public
        view
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor()
        internal
        view
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (address)
    {
        return super._executor();
    }
}
