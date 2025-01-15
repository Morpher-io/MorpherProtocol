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

        MorpherAccessControl(loadAddress("MorpherAccessControl")).grantRole(keccak256("ADMINISTRATOR_ROLE"),existingAdmin);

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
                console.logBytes32(marketsToAdd[19]);
                MorpherAdmin(existingAdmin).bulkActivateMarkets(marketsToAdd);
                console.log("Added batch", batchCount);
                batchCount++;
                marketsToAdd = new bytes32[](20);
            }
        }

        vm.stopBroadcast();
    }
}
