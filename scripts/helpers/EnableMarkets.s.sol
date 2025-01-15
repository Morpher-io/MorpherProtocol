//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {MorpherAccessControl} from "../../contracts/MorpherAccessControl.sol";
import {MorpherAdmin} from "../../contracts/MorpherAdmin.sol";
import {DeployOrUpgrade} from "../deployOrUpgrade.sol";

//pre processing of the market ids: 
// jq '[.[].id]' deployments/markets.json > deployments/market_ids.json

contract EnableMarkets is DeployOrUpgrade {
    using stdJson for string;


    function run() public {
        // Read and process markets.json
        vm.startBroadcast();

        // Deploy or upgrade MorpherAdmin
        address existingAdmin = loadAddress("MorpherAdmin");
        require(existingAdmin != address(0x0), "MorpherAdmin must be deployed for this network");

        address accessControlAddress = loadAddress("MorpherAccessControl");
        console.log("AccessControl address:", accessControlAddress);
        console.log("Granting ADMINISTRATOR_ROLE to:", existingAdmin);
        
        // Verify MorpherAdmin is initialized
        try MorpherAdmin(existingAdmin).state() returns (address stateAddr) {
            console.log("MorpherAdmin state address:", stateAddr);
            require(stateAddr != address(0), "MorpherAdmin not properly initialized");
        } catch {
            revert("Failed to query MorpherAdmin state - contract may not be initialized");
        }
        
        MorpherAccessControl(accessControlAddress).grantRole(keccak256("ADMINISTRATOR_ROLE"), existingAdmin);

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/market_ids.json");
        string memory json = vm.readFile(path);
        string[] memory marketIds = abi.decode(
            vm.parseJson(json, ""),
            (string[])
        );

        console.log(marketIds[19]);

       
        uint256 batchCount = 0;
        
        bytes32[] memory marketsToAdd = new bytes32[](20);
        for (uint256 i = 0; i < marketIds.length; i++) {
            // Add market to current batch
             // Process markets in batches of 20
            marketsToAdd[i % 20] = keccak256(abi.encodePacked(marketIds[i]));
            
            // When batch is full or we're at the end, process it
            if ((i + 1) % 20 == 0 || i == marketIds.length - 1) {
                // Validate the batch
                uint256 validCount = 0;
                for(uint256 j = 0; j < marketsToAdd.length; j++) {
                    if(marketsToAdd[j] != bytes32(0)) {
                        validCount++;
                        console.log("Market hash at index", j);
                        console.logBytes32(marketsToAdd[j]);
                    }
                }
                
                console.log("Processing batch", batchCount, "with", validCount, "valid markets");
                console.log("Calling bulkActivateMarkets from address:", address(this));
                console.log("MorpherAdmin address:", existingAdmin);
                
                try MorpherAdmin(existingAdmin).bulkActivateMarkets(marketsToAdd) {
                    console.log("Successfully added batch", batchCount);
                } catch Error(string memory reason) {
                    console.log("Failed to add batch with reason:", reason);
                    revert(reason);
                } catch (bytes memory) {
                    console.log("Failed to add batch with no reason");
                    revert("Transaction reverted silently");
                }
                
                batchCount++;
                marketsToAdd = new bytes32[](20);
            }
        }

        vm.stopBroadcast();
    }
}
