//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {MorpherAdmin} from "../../contracts/MorpherAdmin.sol";

contract EnableMarkets is Script {
    using stdJson for string;

    function enableMarketsFromJson(address admin) public {
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
    }
}
