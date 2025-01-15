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


//morpher contracts
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol";


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

    function run() public {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);

        // Load existing addresses
        Addresses memory addrs = loadAddresses();

        // Deploy ProxyAdmin if not already deployed
        if (addrs.proxyAdmin == address(0)) {
            addrs.proxyAdmin = deployProxyAdmin();
            console.log("Deployed ProxyAdmin at:", addrs.proxyAdmin);
        }

        // Deploy or upgrade MorpherAccessControl
        MorpherAccessControl implementation = new MorpherAccessControl();
        addrs.accessControl = deployOrUpgrade(
            addrs.accessControl,
            address(implementation),
            addrs.proxyAdmin,
            abi.encodeCall(MorpherAccessControl.initialize, ())
        );
        console.log("MorpherAccessControl at:", addrs.accessControl);

        // Save updated addresses
        saveAddresses(addrs);
        
        vm.stopBroadcast();
    }

    function getAddressesPath() internal view returns (string memory) {
        string memory root = vm.projectRoot();
        return string.concat(root, "/deployments/", Strings.toString(block.chainid), ".json");
    }

    function loadAddresses() internal returns (Addresses memory addrs) {
        string memory path = getAddressesPath();
        if (!vm.isFile(path)) {
            addrs = getEmptyAddresses();
            saveAddresses(addrs);
            return addrs;

        }
        string memory json = vm.readFile(path);
        return loadAddressesFromJson(json);
    }

    function getEmptyAddresses() internal pure returns (Addresses memory) {
        return Addresses(
            address(0), address(0), address(0), address(0), 
            address(0), address(0), address(0), address(0), 
            address(0), address(0), address(0), address(0), 
            address(0)
        );
    }

    
    function loadAddressesFromJson(string memory json) internal view returns (Addresses memory) {
        bytes memory data = vm.parseJson(json);
        return abi.decode(data, (Addresses));
    }

    function saveAddresses(Addresses memory addrs) internal {
        string memory path = getAddressesPath();
        string memory jsonObj = '{"proxyAdmin": "0x0", "accessControl": "0x0", "state": "0x0", "userBlocking": "0x0", "token": "0x0", "staking": "0x0", "mintingLimiter": "0x0", "tradeEngine": "0x0", "oracle": "0x0", "bridge": "0x0", "admin": "0x0", "interestRateManager": "0x0", "airdrop": "0x0"}';

        if (!vm.isFile(path)) {
            vm.writeFile(path, jsonObj);
        }
        
        // Write each address individually to avoid stack too deep
        vm.writeJson(vm.toString(addrs.proxyAdmin), path, ".proxyAdmin");
        vm.writeJson(vm.toString(addrs.accessControl), path, ".accessControl"); 
        vm.writeJson(vm.toString(addrs.state), path, ".state");
        vm.writeJson(vm.toString(addrs.userBlocking), path, ".userBlocking");
        vm.writeJson(vm.toString(addrs.token), path, ".token");
        vm.writeJson(vm.toString(addrs.staking), path, ".staking");
        vm.writeJson(vm.toString(addrs.mintingLimiter), path, ".mintingLimiter");
        vm.writeJson(vm.toString(addrs.tradeEngine), path, ".tradeEngine");
        vm.writeJson(vm.toString(addrs.oracle), path, ".oracle");
        vm.writeJson(vm.toString(addrs.bridge), path, ".bridge");
        vm.writeJson(vm.toString(addrs.admin), path, ".admin");
        vm.writeJson(vm.toString(addrs.interestRateManager), path, ".interestRateManager");
        vm.writeJson(vm.toString(addrs.airdrop), path, ".airdrop");
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
