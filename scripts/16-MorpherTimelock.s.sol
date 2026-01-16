//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
import {DeploymentUtils} from "./DeploymentUtils.sol";
import {MorpherTimelockController} from "../contracts/MorpherTimelockController.sol";
import {ERC1967Proxy} from "../lib/openzeppelin-contracts-5/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployMorpherTimelock
 * @notice Deploys the MorpherTimelockController for governance
 * @dev Uses centralized MorpherAccessControl for role management
 *
 * Configuration:
 * - Min delay: 2 days (172,800 seconds)
 * - Open execution: true (anyone can execute ready operations)
 *
 * Role setup (done in 17-MorpherGovernor.s.sol):
 * - Governor gets: PROPOSER_ROLE, CANCELLER_ROLE
 * - Timelock gets: PROXYUPDATER_ROLE, ADMINISTRATOR_ROLE, GOVERNANCE_ROLE
 */
contract DeployMorpherTimelock is DeploymentUtils {

    string constant CONTRACT_KEY = "MorpherTimelock";

    // 2 days in seconds
    uint256 constant MIN_DELAY = 2 days;

    // Anyone can execute ready operations
    bool constant OPEN_EXECUTION = true;

    function run() public {
        // Load dependencies
        address stateAddress = loadAddress("MorpherState");
        require(stateAddress != address(0), "MorpherState must be deployed first");

        address accessControlAddress = loadAddress("MorpherAccessControl");
        require(accessControlAddress != address(0), "MorpherAccessControl must be deployed first");

        address existingTimelock = loadAddress(CONTRACT_KEY);

        if (existingTimelock != address(0)) {
            console.log("MorpherTimelock already deployed at:", existingTimelock);
            console.log("Skipping deployment. To redeploy, remove the address from deployments JSON.");
            return;
        }

        vm.startBroadcast();

        // Deploy implementation
        MorpherTimelockController implementation = new MorpherTimelockController();
        console.log("MorpherTimelockController implementation deployed at:", address(implementation));

        // Deploy proxy with initialization data
        bytes memory initData = abi.encodeCall(
            MorpherTimelockController.initialize,
            (stateAddress, MIN_DELAY, OPEN_EXECUTION)
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        address timelockAddress = address(proxy);

        console.log("MorpherTimelock proxy deployed at:", timelockAddress);
        console.log("Min delay:", MIN_DELAY / 1 days, "days");
        console.log("Open execution:", OPEN_EXECUTION);

        // Save address to deployments
        saveAddress(CONTRACT_KEY, timelockAddress);

        console.log("");
        console.log("NEXT: Deploy MorpherGovernor (17-MorpherGovernor.s.sol)");
        console.log("The Governor script will configure all necessary roles.");

        vm.stopBroadcast();
    }
}
