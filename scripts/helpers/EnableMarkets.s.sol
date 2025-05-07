//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {MorpherAccessControl} from "../../contracts/MorpherAccessControl.sol";
import {MorpherState} from "../../contracts/MorpherState.sol";
import {DeployOrUpgrade} from "../deployOrUpgrade.sol";

//pre processing of the market ids: 
// jq '[.[].id]' deployments/markets.json > deployments/market_ids.json

contract EnableMarkets is DeployOrUpgrade {
    using stdJson for string;

struct Markets {
    string marketid;
    // string markethash;
}

struct JsonFileStruct {
    Markets[] marketsarray;
    string name;
}
    function run() public {
        // Read and process markets.json
        vm.startBroadcast();
        address stateAddress = loadAddress("MorpherState");
        
       
        // MorpherAccessControl(accessControlAddress).grantRole(keccak256("ADMINISTRATOR_ROLE"), existingAdmin);

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/market_ids.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json, "");

        JsonFileStruct memory marketIds = abi.decode(data,(JsonFileStruct));

        console.log(marketIds.marketsarray[0].marketid);

       
        uint256 batchCount = 0;
        uint256 batchSize = 40;
        
        bytes32[] memory marketsToAdd = new bytes32[](batchSize);
        for (uint256 i = 0; i < marketIds.marketsarray.length; i++) {
            // Add market to current batch
             // Process markets in batches of 100
            marketsToAdd[i % batchSize] = keccak256(abi.encodePacked(marketIds.marketsarray[i].marketid));
            
            // When batch is full or we're at the end, process it
            if ((i + 1) % batchSize == 0 || i == marketIds.marketsarray.length - 1) {
                // Validate the batch
                uint256 validCount = 0;
                for(uint256 j = 0; j < marketsToAdd.length; j++) {
                    if(marketsToAdd[j] != bytes32(0)) {
                        validCount++;
                        console.log("Market hash at index", j);
                        console.logBytes32(marketsToAdd[j]);
                    }
                }
                
                // console.log(abi.encodePacked("Processing batch", string(batchCount), "with", string(validCount), "valid markets"));
                console.log("Calling bulkActivateMarkets from address:", address(this));
                console.log("MorpherState address:", stateAddress);
                
                try MorpherState(stateAddress).activateMarket(marketsToAdd) {
                    console.log("Successfully added batch", batchCount);
                } catch Error(string memory reason) {
                    console.log("Failed to add batch with reason:", reason);
                    revert(reason);
                } catch (bytes memory) {
                    console.log("Failed to add batch with no reason");
                    revert("Transaction reverted silently");
                }
                
                batchCount++;
                marketsToAdd = new bytes32[](batchSize);
            }
        }

        vm.stopBroadcast();
    }
}
