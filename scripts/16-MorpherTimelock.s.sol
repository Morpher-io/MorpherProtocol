//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
import {DeploymentUtils} from "./DeploymentUtils.sol";
import {TimelockControllerUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/governance/TimelockControllerUpgradeable.sol";
import {ERC1967Proxy} from "../lib/openzeppelin-contracts-5/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployMorpherTimelock
 * @notice Deploys the TimelockController for governance
 * @dev TimelockController is deployed as a proxy for upgradeability
 *
 * Configuration:
 * - Min delay: 2 days (172,800 seconds)
 * - Proposers: Will be set to Governor after Governor deployment
 * - Executors: Open (anyone can execute once ready)
 * - Admin: Deployer initially, should be renounced after full setup
 */
contract DeployMorpherTimelock is DeploymentUtils {

    string constant CONTRACT_KEY = "MorpherTimelock";

    // 2 days in seconds
    uint256 constant MIN_DELAY = 2 days;

    function run() public {
        address existingTimelock = loadAddress(CONTRACT_KEY);

        if (existingTimelock != address(0)) {
            console.log("MorpherTimelock already deployed at:", existingTimelock);
            console.log("Skipping deployment. To redeploy, remove the address from deployments JSON.");
            return;
        }

        // Initially no proposers - Governor will be added after it's deployed
        address[] memory proposers = new address[](0);

        // Anyone can execute once the timelock delay has passed
        address[] memory executors = new address[](1);
        executors[0] = address(0); // address(0) means anyone can execute

        // Admin is deployer initially - should be renounced after Governor is set up
        address admin = msg.sender;

        vm.startBroadcast();

        // Deploy implementation
        TimelockControllerUpgradeable implementation = new TimelockControllerUpgradeable();
        console.log("TimelockController implementation deployed at:", address(implementation));

        // Deploy proxy with initialization data
        bytes memory initData = abi.encodeCall(
            TimelockControllerUpgradeable.initialize,
            (MIN_DELAY, proposers, executors, admin)
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        address timelockAddress = address(proxy);

        console.log("MorpherTimelock proxy deployed at:", timelockAddress);
        console.log("Min delay:", MIN_DELAY, "seconds (", MIN_DELAY / 1 days, "days)");
        console.log("Admin:", admin);
        console.log("");
        console.log("IMPORTANT: After deploying MorpherGovernor:");
        console.log("1. Grant PROPOSER_ROLE to Governor on this Timelock");
        console.log("2. Grant CANCELLER_ROLE to Governor on this Timelock");
        console.log("3. Grant necessary roles (PROXYUPDATER_ROLE, ADMINISTRATOR_ROLE) to this Timelock on AccessControl");
        console.log("4. Renounce admin role from deployer after testing");

        // Save address to deployments
        saveAddress(CONTRACT_KEY, timelockAddress);

        vm.stopBroadcast();
    }
}
