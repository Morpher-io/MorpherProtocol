//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {DeployOrUpgrade} from "./deployOrUpgrade.sol";
import {MorpherSwapHelper} from "./MorpherSwapHelper.sol";
import {MorpherOracle} from "../contracts/MorpherOracle.sol";

contract DeploySwapHelper is DeployOrUpgrade {
    using stdJson for string;

    // Universal Router and Permit2 addresses - will be set based on chainId
    address public UNIVERSAL_ROUTER;
    address public PERMIT2;

    // Set up addresses based on the chain we're deploying to
    function setupAddresses() internal {
        uint256 chainId = block.chainid;
    
        if (chainId == 8453) {
            // Base Mainnet
            UNIVERSAL_ROUTER = 0x6ff5693b99212da76ad316178a184ab56d299b43;
            PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        } else if (chainId == 84532) {
            // Base Sepolia
            UNIVERSAL_ROUTER = 0x492e6456d9528771018deb9e87ef7750ef184104;
            PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        } else {
            revert("Unsupported chain ID");
        }
    }

    function run() public {
        // Set up the correct addresses based on the chain
        setupAddresses();
        
        vm.startBroadcast();

        console.log("Deploying MorpherSwapHelper on chain ID:", uint256(block.chainid));
        console.log("Using Universal Router:", UNIVERSAL_ROUTER);
        console.log("Using Permit2:", PERMIT2);
        
        // Deploy the MorpherSwapHelper
        MorpherSwapHelper swapHelper = new MorpherSwapHelper(UNIVERSAL_ROUTER, PERMIT2);
        console.log("MorpherSwapHelper deployed at:", address(swapHelper));
        
        // Save the address
        saveAddress("MorpherSwapHelper", address(swapHelper));
        
        // Get MorpherOracle address
        address oracleAddress = loadAddress("MorpherOracle");
        if (oracleAddress != address(0)) {
            // Set the helper address in the Oracle
            MorpherOracle oracle = MorpherOracle(oracleAddress);
            oracle.setMorpherSwapHelperAddress(address(swapHelper));
            console.log("Set helper address in MorpherOracle");
        } else {
            console.log("MorpherOracle not found, skipping helper address setup");
        }
        
        vm.stopBroadcast();
    }
}
