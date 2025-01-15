//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Upgrades} from "../lib/openzeppelin-foundry-upgrades/src/LegacyUpgrades.sol";
import {Options} from "../lib/openzeppelin-foundry-upgrades/src/Options.sol";

import {DeployOrUpgrade} from "./deployOrUpgrade.sol";

//morpher contracts
import {MorpherInterestRateManager} from "../contracts/MorpherInterestRateManager.sol";
import {MorpherState} from "../contracts/MorpherState.sol";

contract DeployMorpherInterestRateManager is DeployOrUpgrade {
    using stdJson for string;

    function run() public {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);

        // Load State address - required for InterestRateManager initialization
        address stateAddress = loadAddress("MorpherState");
        require(stateAddress != address(0), "MorpherState must be deployed first");

        // Deploy or upgrade MorpherInterestRateManager
        address existingInterestRateManager = loadAddress("MorpherInterestRateManager");
        MorpherInterestRateManager implementation = new MorpherInterestRateManager();
        
        address interestRateManager = deployOrUpgrade(
            existingInterestRateManager,
            address(implementation),
            abi.encodeCall(MorpherInterestRateManager.initialize, (stateAddress)),
            "MorpherInterestRateManager.sol"
        );
        
        saveAddress("MorpherInterestRateManager", interestRateManager);
        console.log("MorpherInterestRateManager at:", interestRateManager);

        // Configure if this is a new deployment
        if (existingInterestRateManager == address(0)) {
            MorpherInterestRateManager manager = MorpherInterestRateManager(interestRateManager);
            
            // Set initial interest rates as per BaseSetup
            uint256 initialTimestamp = 1617094819;
            manager.addInterestRate(15000, initialTimestamp);
            manager.addInterestRate(30000, 1644491427);

            // Set InterestRateManager in State
            MorpherState(stateAddress).setMorpherInterestRateManager(interestRateManager);
        }
        
        vm.stopBroadcast();
    }
}
