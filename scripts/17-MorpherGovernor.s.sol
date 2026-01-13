//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
import {DeployOrUpgradeV5} from "./deployOrUpgradeV5.sol";
import {MorpherGovernor} from "../contracts/MorpherGovernor.sol";
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol";
import {MorpherState} from "../contracts/MorpherState.sol";
import {TimelockControllerUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/governance/TimelockControllerUpgradeable.sol";

/**
 * @title DeployMorpherGovernor
 * @notice Deploys the MorpherGovernor contract for on-chain governance
 * @dev Uses UUPS proxy pattern, follows existing deployment conventions
 *
 * Governance Parameters (for Base chain with ~2 second blocks):
 * - Voting Delay: 43,200 blocks (~1 day)
 * - Voting Period: 302,400 blocks (~7 days)
 * - Proposal Threshold: 10,000,000 MPH
 * - Quorum: 51% of circulating supply (custom implementation)
 */
contract DeployMorpherGovernor is DeployOrUpgradeV5 {

    string constant CONTRACT_KEY = "MorpherGovernor";
    string constant CONTRACT_NAME = "MorpherGovernor.sol";

    // Governance parameters for Base chain (~2 second blocks)
    // 1 day voting delay = 43,200 blocks
    uint48 constant VOTING_DELAY = 43200;
    // 7 day voting period = 302,400 blocks
    uint32 constant VOTING_PERIOD = 302400;
    // 10M MPH required to create a proposal
    uint256 constant PROPOSAL_THRESHOLD = 10_000_000 ether;

    function deployImplementation() internal override returns (address) {
        MorpherGovernor governor = new MorpherGovernor();
        return address(governor);
    }

    function run() public {
        // Load dependencies
        address stateAddress = loadAddress("MorpherState");
        require(stateAddress != address(0), "MorpherState must be deployed first");

        address accessControlAddress = loadAddress("MorpherAccessControl");
        require(accessControlAddress != address(0), "MorpherAccessControl must be deployed first");

        address timelockAddress = loadAddress("MorpherTimelock");
        require(timelockAddress != address(0), "MorpherTimelock must be deployed first (run 16-MorpherTimelock.s.sol)");

        // Check MorpherToken is set in MorpherState
        address tokenAddress = MorpherState(stateAddress).morpherTokenAddress();
        require(tokenAddress != address(0), "MorpherToken not set in MorpherState");

        // Check if new deployment or upgrade
        address existingProxy = loadAddress(CONTRACT_KEY);
        bool isNewDeployment = existingProxy == address(0);

        vm.startBroadcast();

        // Deploy or upgrade
        address governorProxy = deployOrUpgradeV5(
            CONTRACT_KEY,
            CONTRACT_NAME,
            abi.encodeCall(
                MorpherGovernor.initialize,
                (
                    stateAddress,
                    TimelockControllerUpgradeable(payable(timelockAddress)),
                    VOTING_DELAY,
                    VOTING_PERIOD,
                    PROPOSAL_THRESHOLD
                )
            ),
            bytes("")
        );

        console.log("MorpherGovernor deployed at:", governorProxy);
        console.log("Voting delay:", VOTING_DELAY, "blocks (~1 day)");
        console.log("Voting period:", VOTING_PERIOD, "blocks (~7 days)");
        console.log("Proposal threshold:", PROPOSAL_THRESHOLD / 1 ether, "MPH");
        console.log("Quorum: 51% of circulating supply");

        if (isNewDeployment) {
            console.log("");
            console.log("Configuring roles...");

            // Get contract instances
            TimelockControllerUpgradeable timelock = TimelockControllerUpgradeable(payable(timelockAddress));
            MorpherAccessControl accessControl = MorpherAccessControl(accessControlAddress);

            // Grant Governor the PROPOSER and CANCELLER roles on Timelock
            bytes32 proposerRole = timelock.PROPOSER_ROLE();
            bytes32 cancellerRole = timelock.CANCELLER_ROLE();

            timelock.grantRole(proposerRole, governorProxy);
            console.log("Granted PROPOSER_ROLE to Governor on Timelock");

            timelock.grantRole(cancellerRole, governorProxy);
            console.log("Granted CANCELLER_ROLE to Governor on Timelock");

            // Grant Timelock the necessary roles on MorpherAccessControl
            // These allow governance proposals to execute protocol changes

            // PROXYUPDATER_ROLE - for upgrading contracts
            bytes32 proxyUpdaterRole = accessControl.PROXYUPDATER_ROLE();
            accessControl.grantRole(proxyUpdaterRole, timelockAddress);
            console.log("Granted PROXYUPDATER_ROLE to Timelock on AccessControl");

            // ADMINISTRATOR_ROLE - for admin functions
            bytes32 adminRole = keccak256("ADMINISTRATOR_ROLE");
            accessControl.grantRole(adminRole, timelockAddress);
            console.log("Granted ADMINISTRATOR_ROLE to Timelock on AccessControl");

            // GOVERNANCE_ROLE - for governance-specific functions in MorpherState
            bytes32 governanceRole = keccak256("GOVERNANCE_ROLE");
            accessControl.grantRole(governanceRole, timelockAddress);
            console.log("Granted GOVERNANCE_ROLE to Timelock on AccessControl");

            console.log("");
            console.log("Initial setup complete!");
            console.log("");
            console.log("IMPORTANT NEXT STEPS:");
            console.log("1. Test governance with a low-risk proposal");
            console.log("2. Register on Tally (https://www.tally.xyz/add-a-dao)");
            console.log("3. After confidence period, consider:");
            console.log("   - Revoking ADMINISTRATOR_ROLE from EOA accounts");
            console.log("   - Renouncing DEFAULT_ADMIN_ROLE on Timelock");
        }

        vm.stopBroadcast();
    }
}
