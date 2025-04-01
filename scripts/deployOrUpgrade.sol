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

// --- Inherit from DeploymentUtils ---
import {DeploymentUtils} from "./DeploymentUtils.sol";

// --- Remove Morpher contract imports if not directly used ---

// --- Inherit from DeploymentUtils ---
abstract contract DeployOrUpgrade is DeploymentUtils {

    // --- Remove address management functions (now in DeploymentUtils) ---
    // --- Remove Addresses struct (now in DeploymentUtils) ---

    // --- Keep v4 specific helpers ---
    function deployProxyAdmin() internal returns (address proxyAdminAddr) {
        // Load the *v4* ProxyAdmin address
        proxyAdminAddr = loadAddress("proxyAdmin"); // Assumes "proxyAdmin" key exists for v4 deployments
        if (proxyAdminAddr == address(0)) {
            console.log("Deploying new V4 ProxyAdmin...");
            ProxyAdmin admin = new ProxyAdmin();
            proxyAdminAddr = address(admin);
            // Save the v4 proxy admin address using the specific key "proxyAdmin"
            saveAddress("proxyAdmin", proxyAdminAddr);
            console.log("Deployed V4 ProxyAdmin at:", proxyAdminAddr);
        }
        return proxyAdminAddr;
    }

    function deployProxy(
        string memory path = getAddressesPath();
        if (!vm.isFile(path)) {
            addrs = getEmptyAddresses();
            saveAddresses(addrs);
            return addrs;
        }
        string memory json = vm.readFile(path);
        return loadAddressesFromJson(json);
    }

    function loadAddress(string memory key) internal returns (address) {
        string memory path = getAddressesPath();
        if (!vm.isFile(path)) {
            Addresses memory addrs = getEmptyAddresses();
            saveAddresses(addrs);
            return address(0);
        }
        string memory json = vm.readFile(path);
        return vm.parseJsonAddress(json, string.concat(".", key));
    }

    function saveAddress(string memory key, address value) internal {
        string memory path = getAddressesPath();
         string memory jsonObj = '{"MorpherAccessControl": "0x0", "MorpherAdmin": "0x0", "MorpherAirdrop": "0x0", "MorpherBridge": "0x0", "MorpherInterestRateManager": "0x0", "MorpherMintingLimiter": "0x0", "MorpherOracle": "0x0", "proxyAdmin": "0x0", "MorpherSidechainToBaseMigration": "0x0", "MorpherState": "0x0", "MorpherStaking": "0x0", "MorpherToken": "0x0", "MorpherTradeEngine": "0x0", "MorpherSwapHelper": "0x0", "MorpherUserBlocking": "0x0"}';

        if (!vm.isFile(path)) {
            vm.writeFile(path, jsonObj);
        }
        vm.writeJson(vm.toString(value), path, string.concat(".", key));
    }

    function getEmptyAddresses() internal pure returns (Addresses memory) {
        return Addresses(
            address(0), address(0), address(0), address(0), 
            address(0), address(0), address(0), address(0), 
            address(0), address(0), address(0), address(0), 
            address(0)
        );
    }
    
    function loadAddressesFromJson(string memory json) internal pure returns (Addresses memory) {
        bytes memory data = vm.parseJson(json);
        return abi.decode(data, (Addresses));
    }

    function saveAddresses(Addresses memory addrs) internal {
        string memory path = getAddressesPath();
        string memory jsonObj = '{"MorpherAccessControl": "0x0", "MorpherAdmin": "0x0", "MorpherAirdrop": "0x0", "MorpherBridge": "0x0", "MorpherInterestRateManager": "0x0", "MorpherMintingLimiter": "0x0", "MorpherOracle": "0x0", "proxyAdmin": "0x0", "MorpherSidechainToBaseMigration": "0x0", "MorpherState": "0x0", "MorpherStaking": "0x0", "MorpherToken": "0x0", "MorpherTradeEngine": "0x0", "MorpherSwapHelper": "0x0", "MorpherUserBlocking": "0x0"}';

        if (!vm.isFile(path)) {
            vm.writeFile(path, jsonObj);
        }
        
        // Write each address individually to avoid stack too deep
        vm.writeJson(vm.toString(addrs.accessControl), path, ".MorpherAccessControl");
        vm.writeJson(vm.toString(addrs.admin), path, ".MorpherAdmin");
        vm.writeJson(vm.toString(addrs.airdrop), path, ".MorpherAirdrop");
        vm.writeJson(vm.toString(addrs.bridge), path, ".MorpherBridge");
        vm.writeJson(vm.toString(addrs.interestRateManager), path, ".MorpherInterestRateManager");
        vm.writeJson(vm.toString(addrs.mintingLimiter), path, ".MorpherMintingLimiter");
        vm.writeJson(vm.toString(addrs.oracle), path, ".MorpherOracle");
        vm.writeJson(vm.toString(addrs.proxyAdmin), path, ".proxyAdmin");
        vm.writeJson(vm.toString(addrs.state), path, ".MorpherState");
        vm.writeJson(vm.toString(addrs.staking), path, ".MorpherStaking");
        vm.writeJson(vm.toString(addrs.token), path, ".MorpherToken");
        vm.writeJson(vm.toString(addrs.tradeEngine), path, ".MorpherTradeEngine");
        vm.writeJson(vm.toString(addrs.tradeEngine), path, ".MorpherSwapHelper");
        vm.writeJson(vm.toString(addrs.userBlocking), path, ".MorpherUserBlocking");
    }

    function deployProxyAdmin() internal returns (address) {
        ProxyAdmin admin = new ProxyAdmin();
        return address(admin);
    }

    function deployProxy(
        address implementation,
        address admin,
        bytes memory data
    ) internal returns (address) {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            implementation,
            admin,
            data
        );
        return address(proxy);
    }

    function validateUpgrade(string memory contractName) internal {

		Options memory opts;
        Upgrades.validateUpgrade(contractName, opts);
    }

    function deployOrUpgrade(
        address existingProxy,
        address implementation,
        bytes memory initData,
        string memory contractName
    ) internal returns (address) {
        // Load or deploy ProxyAdmin as prerequisite
        address proxyAdmin = loadAddress("proxyAdmin");
        if (proxyAdmin == address(0)) {
            proxyAdmin = deployProxyAdmin();
            saveAddress("proxyAdmin", proxyAdmin);
            console.log("Deployed ProxyAdmin at:", proxyAdmin);
        }

        if (existingProxy == address(0)) {
            // Deploy new proxy
            return deployProxy(
                implementation,
                proxyAdmin,
                initData
            );
        } else {
            // Validate and upgrade existing proxy
            validateUpgrade(contractName);
            upgradeProxy(
                existingProxy,
                implementation,
                proxyAdmin
            );
            return existingProxy;
        }
    }

    function upgradeProxy(
        address proxy,
        address implementation,
        address admin
    ) internal {
        ProxyAdmin(admin).upgrade(
            ITransparentUpgradeableProxy(proxy),
            implementation
        );
    }
}
