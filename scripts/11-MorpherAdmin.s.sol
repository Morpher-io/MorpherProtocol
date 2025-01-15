//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {MorpherState} from "../contracts/MorpherState.sol";
import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Upgrades} from "../lib/openzeppelin-foundry-upgrades/src/LegacyUpgrades.sol";
import {Options} from "../lib/openzeppelin-foundry-upgrades/src/Options.sol";

import {DeployOrUpgrade} from "./deployOrUpgrade.sol";

//morpher contracts
import {MorpherAdmin} from "../contracts/MorpherAdmin.sol";
import {MorpherState} from "../contracts/MorpherState.sol";

contract DeployMorpherAdmin is DeployOrUpgrade {
    using stdJson for string;

    function run() public {
        vm.startBroadcast();

        // Load State address - required for Admin initialization
        address stateAddress = loadAddress("MorpherState");
        require(stateAddress != address(0), "MorpherState must be deployed first");

        // Deploy or upgrade MorpherAdmin
        address existingAdmin = loadAddress("MorpherAdmin");
        MorpherAdmin implementation = new MorpherAdmin();
        
        address admin = deployOrUpgrade(
            existingAdmin,
            address(implementation),
            abi.encodeCall(
                MorpherAdmin.initialize,
                (stateAddress)
            ),
            "MorpherAdmin.sol"
        );
        
        saveAddress("MorpherAdmin", admin);
        console.log("MorpherAdmin at:", admin);

        // Read and process markets.json
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/docs/markets.json");
        string memory json = vm.readFile(path);
        bytes memory marketsRaw = json.parseRaw(".");
        
        // Parse the JSON array
        bytes[] memory marketIds = abi.decode(marketsRaw, (bytes[]));
        
        // Process markets in batches of 20
        bytes32[] memory marketsToAdd = new bytes32[](20);
        uint256 batchCount = 0;
        
        for (uint256 i = 0; i < marketIds.length; i++) {
            // Extract market ID from the JSON object
            bytes memory marketData = marketIds[i];
            string memory marketId = abi.decode(marketData, (string));
            
            // Add market to current batch
            marketsToAdd[i % 20] = keccak256(bytes(marketId));
            
            // When batch is full or we're at the end, process it
            if ((i + 1) % 20 == 0 || i == marketIds.length - 1) {
                uint256 batchSize = (i % 20) + 1;
                bytes32[] memory currentBatch = new bytes32[](batchSize);
                for (uint256 j = 0; j < batchSize; j++) {
                    currentBatch[j] = marketsToAdd[j];
                }
                
                MorpherAdmin(admin).bulkActivateMarkets(currentBatch);
                console.log("Added batch", batchCount, "with", batchSize, "markets");
                batchCount++;
            }
        }
        
        vm.stopBroadcast();
    }
}
