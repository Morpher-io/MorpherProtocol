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
 *  all role checks to the centralized MorpherAccessControl system, following the
 *  protocol's State Pointer Pattern.
 *
 **/

import {TimelockControllerUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/governance/TimelockControllerUpgradeable.sol";
import {MorpherState} from "./MorpherState.sol";
import {MorpherAccessControl} from "./MorpherAccessControl.sol";

/**
 * @title MorpherTimelockController
 * @notice TimelockController that uses centralized MorpherAccessControl for role management
 * @dev Overrides hasRole to check against MorpherAccessControl instead of internal storage
 *
 * Roles are managed via MorpherAccessControl:
 * - TIMELOCK_PROPOSER_ROLE: Can schedule operations
 * - TIMELOCK_EXECUTOR_ROLE: Can execute ready operations (or address(0) for open execution)
 * - TIMELOCK_CANCELLER_ROLE: Can cancel pending operations
 * - TIMELOCK_ADMIN_ROLE: Can manage timelock configuration
 */
contract MorpherTimelockController is TimelockControllerUpgradeable {
    /// @notice MorpherState contract for accessing MorpherAccessControl
    MorpherState public morpherState;

    /// @notice Role for proposing timelock operations (maps to PROPOSER_ROLE)
    bytes32 public constant TIMELOCK_PROPOSER_ROLE = keccak256("TIMELOCK_PROPOSER_ROLE");

    /// @notice Role for executing timelock operations (maps to EXECUTOR_ROLE)
    bytes32 public constant TIMELOCK_EXECUTOR_ROLE = keccak256("TIMELOCK_EXECUTOR_ROLE");

    /// @notice Role for cancelling timelock operations (maps to CANCELLER_ROLE)
    bytes32 public constant TIMELOCK_CANCELLER_ROLE = keccak256("TIMELOCK_CANCELLER_ROLE");

    /// @notice Role for timelock administration (maps to DEFAULT_ADMIN_ROLE)
    bytes32 public constant TIMELOCK_ADMIN_ROLE = keccak256("TIMELOCK_ADMIN_ROLE");

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

        // Initialize parent with empty arrays - we'll use MorpherAccessControl for role checks
        // Pass address(0) as admin since we don't want internal admin role storage
        address[] memory emptyProposers = new address[](0);
        address[] memory emptyExecutors = new address[](0);
        __TimelockController_init(minDelay, emptyProposers, emptyExecutors, address(0));

        // Grant this contract the admin role on itself for self-administration
        // This is needed for updateDelay to work
        _grantRole(DEFAULT_ADMIN_ROLE, address(this));
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
     * @dev Map internal TimelockController roles to MorpherAccessControl roles
     */
    function _mapRole(bytes32 role) internal pure returns (bytes32) {
        if (role == PROPOSER_ROLE) {
            return TIMELOCK_PROPOSER_ROLE;
        } else if (role == EXECUTOR_ROLE) {
            return TIMELOCK_EXECUTOR_ROLE;
        } else if (role == CANCELLER_ROLE) {
            return TIMELOCK_CANCELLER_ROLE;
        } else if (role == DEFAULT_ADMIN_ROLE) {
            return TIMELOCK_ADMIN_ROLE;
        }
        // For any other role, use it as-is
        return role;
    }

    /**
     * @notice Check if account has role - delegates to MorpherAccessControl
     * @dev Overrides AccessControlUpgradeable.hasRole to use centralized access control
     * @param role The role to check (will be mapped to TIMELOCK_* role in MorpherAccessControl)
     * @param account The account to check
     * @return True if account has the role
     */
    function hasRole(bytes32 role, address account) public view virtual override returns (bool) {
        // Special case: address(0) check for open execution role
        if (role == EXECUTOR_ROLE && account == address(0)) {
            return openExecution;
        }

        // Special case: timelock itself always has admin role for self-administration
        if (role == DEFAULT_ADMIN_ROLE && account == address(this)) {
            return true;
        }

        // Map the role and check against MorpherAccessControl
        bytes32 mappedRole = _mapRole(role);
        return _getAccessControl().hasRole(mappedRole, account);
    }

    /**
     * @notice Grant role - delegates to MorpherAccessControl
     * @dev Can only be called by accounts with admin role on MorpherAccessControl
     * @param role The role to grant
     * @param account The account to grant the role to
     */
    function grantRole(bytes32 role, address account) public virtual override {
        bytes32 mappedRole = _mapRole(role);
        // Caller must have admin for the mapped role on MorpherAccessControl
        MorpherAccessControl accessControl = _getAccessControl();
        require(
            accessControl.hasRole(accessControl.getRoleAdmin(mappedRole), _msgSender()),
            "MorpherTimelockController: must have admin role to grant"
        );
        accessControl.grantRole(mappedRole, account);
    }

    /**
     * @notice Revoke role - delegates to MorpherAccessControl
     * @dev Can only be called by accounts with admin role on MorpherAccessControl
     * @param role The role to revoke
     * @param account The account to revoke the role from
     */
    function revokeRole(bytes32 role, address account) public virtual override {
        bytes32 mappedRole = _mapRole(role);
        MorpherAccessControl accessControl = _getAccessControl();
        require(
            accessControl.hasRole(accessControl.getRoleAdmin(mappedRole), _msgSender()),
            "MorpherTimelockController: must have admin role to revoke"
        );
        accessControl.revokeRole(mappedRole, account);
    }

    /**
     * @notice Renounce role - delegates to MorpherAccessControl
     * @param role The role to renounce
     * @param callerConfirmation Must be _msgSender() for confirmation
     */
    function renounceRole(bytes32 role, address callerConfirmation) public virtual override {
        require(callerConfirmation == _msgSender(), "MorpherTimelockController: can only renounce for self");
        bytes32 mappedRole = _mapRole(role);
        _getAccessControl().renounceRole(mappedRole, _msgSender());
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

    /**
     * @notice Get the admin role for a given role
     * @dev Returns TIMELOCK_ADMIN_ROLE for all timelock roles
     */
    function getRoleAdmin(bytes32 role) public view virtual override returns (bytes32) {
        // All timelock roles are administered by TIMELOCK_ADMIN_ROLE
        if (role == PROPOSER_ROLE || role == EXECUTOR_ROLE || role == CANCELLER_ROLE) {
            return TIMELOCK_ADMIN_ROLE;
        }
        return DEFAULT_ADMIN_ROLE;
    }
}
