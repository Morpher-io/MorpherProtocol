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
 *  MorpherTimelockController - Governance timelock using centralized MorpherAccessControl
 *
 *  This contract extends OpenZeppelin's TimelockControllerUpgradeable and redirects
 *  all role checks to the centralized MorpherAccessControl system.
 *
 *  Roles (managed via MorpherAccessControl):
 *  - PROPOSER_ROLE: Can schedule operations (grant to Governor)
 *  - EXECUTOR_ROLE: Can execute ready operations (or use openExecution)
 *  - CANCELLER_ROLE: Can cancel pending operations (grant to Governor)
 *
 **/

import {TimelockControllerUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/governance/TimelockControllerUpgradeable.sol";
import {MorpherState} from "./MorpherState.sol";
import {MorpherAccessControl} from "./MorpherAccessControl.sol";

/**
 * @title MorpherTimelockController
 * @notice TimelockController that uses centralized MorpherAccessControl for role management
 * @dev Overrides hasRole to check against MorpherAccessControl instead of internal storage.
 *      Role management (grant/revoke) must be done directly on MorpherAccessControl.
 */
contract MorpherTimelockController is TimelockControllerUpgradeable {
    /// @notice MorpherState contract for accessing MorpherAccessControl
    MorpherState public morpherState;

    /// @notice Flag to indicate whether executor role is open (anyone can execute)
    bool public openExecution;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the timelock with MorpherState reference
     * @param _morpherState Address of MorpherState contract
     * @param minDelay Minimum delay for operations in seconds
     * @param _openExecution Whether anyone can execute ready operations
     */
    function initialize(
        address _morpherState,
        uint256 minDelay,
        bool _openExecution
    ) public initializer {
        require(_morpherState != address(0), "MorpherTimelockController: MorpherState cannot be zero address");

        morpherState = MorpherState(_morpherState);
        openExecution = _openExecution;

        // Initialize parent with empty arrays - we use MorpherAccessControl for role checks
        address[] memory emptyProposers = new address[](0);
        address[] memory emptyExecutors = new address[](0);
        __TimelockController_init(minDelay, emptyProposers, emptyExecutors, address(0));
    }

    /**
     * @dev Get the MorpherAccessControl contract
     */
    function _getAccessControl() internal view returns (MorpherAccessControl) {
        address accessControlAddress = morpherState.morpherAccessControlAddress();
        require(accessControlAddress != address(0), "MorpherTimelockController: AccessControl not set");
        return MorpherAccessControl(accessControlAddress);
    }

    /**
     * @notice Check if account has role - delegates to MorpherAccessControl
     * @dev Overrides AccessControlUpgradeable.hasRole to use centralized access control.
     *      Note: DEFAULT_ADMIN_ROLE check is not needed because grantRole/revokeRole/renounceRole
     *      are all disabled (they revert), so no function actually uses DEFAULT_ADMIN_ROLE.
     *      Self-admin functions (updateDelay, setOpenExecution) use msg.sender checks instead.
     * @param role The role to check (PROPOSER_ROLE, EXECUTOR_ROLE, CANCELLER_ROLE)
     * @param account The account to check
     * @return True if account has the role
     */
    function hasRole(bytes32 role, address account) public view virtual override returns (bool) {
        // Special case: address(0) check for open execution
        if (role == EXECUTOR_ROLE && account == address(0)) {
            return openExecution;
        }

        // Delegate to MorpherAccessControl
        return _getAccessControl().hasRole(role, account);
    }

    /**
     * @notice Grant role - disabled, use MorpherAccessControl directly
     */
    function grantRole(bytes32, address) public pure override {
        revert("MorpherTimelockController: Use MorpherAccessControl to manage roles");
    }

    /**
     * @notice Revoke role - disabled, use MorpherAccessControl directly
     */
    function revokeRole(bytes32, address) public pure override {
        revert("MorpherTimelockController: Use MorpherAccessControl to manage roles");
    }

    /**
     * @notice Renounce role - disabled, use MorpherAccessControl directly
     */
    function renounceRole(bytes32, address) public pure override {
        revert("MorpherTimelockController: Use MorpherAccessControl to manage roles");
    }

    /**
     * @notice Set whether execution is open to anyone
     * @dev Can only be called through a timelock operation (self-call)
     * @param _openExecution Whether to allow anyone to execute ready operations
     */
    function setOpenExecution(bool _openExecution) external {
        require(_msgSender() == address(this), "MorpherTimelockController: caller must be timelock");
        openExecution = _openExecution;
    }
}
