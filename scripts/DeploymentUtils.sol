    //SPDX-License-Identifier: MIT
    pragma solidity ^0.8.20;

    import {Script} from "forge-std/Script.sol";
    import {console} from "forge-std/console.sol";
    import {stdJson} from "forge-std/StdJson.sol";
    import {Strings} from "../lib/openzeppelin-contracts-5/contracts/utils/Strings.sol"; // Use non-upgradeable for utils

    abstract contract DeploymentUtils is Script {
        using stdJson for string;

        // Note: Removed proxyAdmin
        struct Addresses {
            address accessControl;
            address admin; // Assuming this is MorpherAdmin, keep name consistent
            address airdrop;
            address bridge;
            address interestRateManager;
            address mintingLimiter;
            address oracle;
            // address proxyAdmin; // REMOVED
            address state;
            address staking;
            address token;
            address tradeEngine;
            address userBlocking;
            // Add other contracts: MorpherSidechainToBaseMigration, MorpherSwapHelper?
            address sidechainMigration;
            address swapHelper;
            address adminFunctions;
        }

        function getAddressesPath() internal view virtual returns (string memory) {
            string memory root = vm.projectRoot();
            // Consider making the filename configurable or chain-specific
            return string.concat(root, "/deployments/", Strings.toString(block.chainid), ".json");
        }

        function loadAddress(string memory key) internal virtual returns (address) {
            string memory path = getAddressesPath();
            if (!vm.isFile(path)) {
                // Initialize the file if it doesn't exist to prevent errors on first load
                saveAddresses(getEmptyAddresses());
                return address(0);
            }
            string memory json = vm.readFile(path);
            // Use safe parsing: check if key exists before parsing
            bytes memory check = vm.parseJson(json, string.concat(".", key));
            if (check.length == 0) {
                 // Key might not exist yet or is null, return 0
                 return address(0);
            }
            // Key exists, parse the address
            return vm.parseJsonAddress(json, string.concat(".", key));
        }

         function saveAddress(string memory key, address value) internal virtual {
            string memory path = getAddressesPath();
            // Define the base JSON structure *without* proxyAdmin
            // Ensure all keys from the Addresses struct are present
            string memory baseJsonStructure = '{"MorpherAccessControl": "0x0", "MorpherAirdrop": "0x0", "MorpherInterestRateManager": "0x0", "MorpherMintingLimiter": "0x0", "MorpherOracle": "0x0", "MorpherSidechainToBaseMigration": "0x0", "MorpherState": "0x0", "MorpherStaking": "0x0", "MorpherToken": "0x0", "MorpherTradeEngine": "0x0", "MorpherSwapHelper": "0x0", "MorpherUserBlocking": "0x0", "MorpherBridge": "0x0", "MorpherAdminFunctions": "0x0"}'; // REMOVED proxyAdmin, added missing keys

            if (!vm.isFile(path)) {
                vm.writeFile(path, baseJsonStructure);
            }
            // This assumes the key exists in the base structure.
            vm.writeJson(vm.toString(value), path, string.concat(".", key));
        }

        function getEmptyAddresses() internal pure virtual returns (Addresses memory) {
            return Addresses(
                address(0), address(0), address(0), address(0),
                address(0), address(0), address(0), /* removed proxyAdmin */
                address(0), address(0), address(0), address(0),
                address(0), address(0), address(0), address(0) // Added sidechainMigration, swapHelper
            );
        }

        function saveAddresses(Addresses memory addrs) internal virtual {
            string memory path = getAddressesPath();
            string memory baseJsonStructure = '{"MorpherAccessControl": "0x0", "MorpherAirdrop": "0x0", "MorpherInterestRateManager": "0x0", "MorpherMintingLimiter": "0x0", "MorpherOracle": "0x0", "MorpherSidechainToBaseMigration": "0x0", "MorpherState": "0x0", "MorpherStaking": "0x0", "MorpherToken": "0x0", "MorpherTradeEngine": "0x0", "MorpherSwapHelper": "0x0", "MorpherUserBlocking": "0x0", "MorpherBridge": "0x0", "MorpherAdminFunctions": "0x0"}'; // REMOVED proxyAdmin, added missing keys

            if (!vm.isFile(path)) {
                vm.writeFile(path, baseJsonStructure);
            }

            // Write each address individually
            vm.writeJson(vm.toString(addrs.accessControl), path, ".MorpherAccessControl");
            vm.writeJson(vm.toString(addrs.admin), path, ".MorpherAdmin");
            vm.writeJson(vm.toString(addrs.airdrop), path, ".MorpherAirdrop");
            vm.writeJson(vm.toString(addrs.bridge), path, ".MorpherBridge");
            vm.writeJson(vm.toString(addrs.interestRateManager), path, ".MorpherInterestRateManager");
            vm.writeJson(vm.toString(addrs.mintingLimiter), path, ".MorpherMintingLimiter");
            vm.writeJson(vm.toString(addrs.oracle), path, ".MorpherOracle");
            vm.writeJson(vm.toString(addrs.sidechainMigration), path, ".MorpherSidechainToBaseMigration");
            vm.writeJson(vm.toString(addrs.state), path, ".MorpherState");
            vm.writeJson(vm.toString(addrs.staking), path, ".MorpherStaking");
            vm.writeJson(vm.toString(addrs.token), path, ".MorpherToken");
            vm.writeJson(vm.toString(addrs.tradeEngine), path, ".MorpherTradeEngine");
            vm.writeJson(vm.toString(addrs.swapHelper), path, ".MorpherSwapHelper");
            vm.writeJson(vm.toString(addrs.userBlocking), path, ".MorpherUserBlocking");
            vm.writeJson(vm.toString(addrs.adminFunctions), path, ".MorpherAdminFunctions");
        }

        function loadAddressesFromJson(string memory json) internal pure virtual returns (Addresses memory) {
            bytes memory data = vm.parseJson(json);
            // Ensure the struct definition matches the JSON structure being parsed
            return abi.decode(data, (Addresses));
        }

        // Optional: Add loadAddresses function back if needed elsewhere
        function loadAddresses() internal virtual returns (Addresses memory addrs) {
            string memory path = getAddressesPath();
            if (!vm.isFile(path)) {
                addrs = getEmptyAddresses();
                saveAddresses(addrs); // Initialize file on first load
                return addrs;
            }
            string memory json = vm.readFile(path);
            return loadAddressesFromJson(json);
        }
    }
