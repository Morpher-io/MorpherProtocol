//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Upgrades} from "../lib/openzeppelin-foundry-upgrades/src/LegacyUpgrades.sol";

contract DeployOrUpgrade is Script {
    using stdJson for string;

    struct Addresses {
        address proxyAdmin;
        address accessControl;
        address state;
        address userBlocking;
        address token;
        address staking;
        address mintingLimiter;
        address tradeEngine;
        address oracle;
        address bridge;
        address admin;
        address interestRateManager;
        address airdrop;
    }

    function getAddressesPath() internal view returns (string memory) {
        string memory root = vm.projectRoot();
        return string.concat(root, "/deployments/", Strings.toString(block.chainid), ".json");
    }

    function loadAddresses() internal view returns (Addresses memory) {
        string memory path = getAddressesPath();
        if (!vm.isFile(path)) {
            return Addresses(address(0), address(0), address(0), address(0), address(0), address(0), address(0), address(0), address(0), address(0), address(0), address(0), address(0));
        }

        string memory json = vm.readFile(path);
        return Addresses({
            proxyAdmin: json.readAddress(".proxyAdmin"),
            accessControl: json.readAddress(".accessControl"),
            state: json.readAddress(".state"),
            userBlocking: json.readAddress(".userBlocking"),
            token: json.readAddress(".token"),
            staking: json.readAddress(".staking"),
            mintingLimiter: json.readAddress(".mintingLimiter"),
            tradeEngine: json.readAddress(".tradeEngine"),
            oracle: json.readAddress(".oracle"),
            bridge: json.readAddress(".bridge"),
            admin: json.readAddress(".admin"),
            interestRateManager: json.readAddress(".interestRateManager"),
            airdrop: json.readAddress(".airdrop")
        });
    }

    function saveAddresses(Addresses memory addrs) internal {
        string memory path = getAddressesPath();
        string memory json = string(
            abi.encodePacked(
                '{"proxyAdmin":"', vm.toString(addrs.proxyAdmin),
                '","accessControl":"', vm.toString(addrs.accessControl),
                '","state":"', vm.toString(addrs.state),
                '","userBlocking":"', vm.toString(addrs.userBlocking),
                '","token":"', vm.toString(addrs.token),
                '","staking":"', vm.toString(addrs.staking),
                '","mintingLimiter":"', vm.toString(addrs.mintingLimiter),
                '","tradeEngine":"', vm.toString(addrs.tradeEngine),
                '","oracle":"', vm.toString(addrs.oracle),
                '","bridge":"', vm.toString(addrs.bridge),
                '","admin":"', vm.toString(addrs.admin),
                '","interestRateManager":"', vm.toString(addrs.interestRateManager),
                '","airdrop":"', vm.toString(addrs.airdrop),
                '"}'
            )
        );
        vm.writeFile(path, json);
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
        Upgrades.validateUpgrade(contractName);
    }

    function deployOrUpgrade(
        address existingProxy,
        address implementation,
        address admin,
        bytes memory initData
    ) internal returns (address) {
        if (existingProxy == address(0)) {
            // Deploy new proxy
            return deployProxy(
                implementation,
                admin,
                initData
            );
        } else {
            // Validate and upgrade existing proxy
            validateUpgrade(type(TransparentUpgradeableProxy).name);
            upgradeProxy(
                existingProxy,
                implementation,
                admin
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
