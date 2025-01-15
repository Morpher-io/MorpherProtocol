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
import {MorpherTradeEngine} from "../contracts/MorpherTradeEngine.sol";
import {MorpherState} from "../contracts/MorpherState.sol";
import {MorpherToken} from "../contracts/MorpherToken.sol";
import {MorpherStaking} from "../contracts/MorpherStaking.sol";
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol";

contract DeployMorpherTradeEngine is DeployOrUpgrade {
    using stdJson for string;

    function run() public {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);

        // Load State address - required for TradeEngine initialization
        address stateAddress = loadAddress("MorpherState");
        require(stateAddress != address(0), "MorpherState must be deployed first");

        // Get configuration
        bool escrowEnabled = vm.envBool("ESCROW_ENABLED");
        uint256 deployedTimestamp = vm.envOr("DEPLOYED_TIMESTAMP", uint256(1613399217));

        // Deploy or upgrade MorpherTradeEngine
        address existingTradeEngine = loadAddress("MorpherTradeEngine");
        MorpherTradeEngine implementation = new MorpherTradeEngine();
        
        address tradeEngine = deployOrUpgrade(
            existingTradeEngine,
            address(implementation),
            abi.encodeCall(MorpherTradeEngine.initialize, (stateAddress, escrowEnabled, deployedTimestamp)),
            "MorpherTradeEngine.sol"
        );
        
        saveAddress("MorpherTradeEngine", tradeEngine);
        console.log("MorpherTradeEngine at:", tradeEngine);

        // Configure if this is a new deployment
        if (existingTradeEngine == address(0)) {
            MorpherTradeEngine tradeEngineContract = MorpherTradeEngine(tradeEngine);
            MorpherAccessControl accessControl = MorpherAccessControl(loadAddress("MorpherAccessControl"));
            

            // Configure permissions
            address tokenAddress = loadAddress("MorpherToken");
            if (tokenAddress != address(0)) {
                accessControl.grantRole(
                    MorpherToken(tokenAddress).BURNER_ROLE(),
                    tradeEngine
                );
            }

            // Grant position admin role
            accessControl.grantRole(
                tradeEngineContract.POSITIONADMIN_ROLE(),
                tradeEngine
            );

            // Set TradeEngine in State
            MorpherState(stateAddress).setMorpherTradeEngine(tradeEngine);
        }
        
        vm.stopBroadcast();
    }
}
