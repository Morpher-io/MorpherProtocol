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
import {MorpherState} from "../contracts/MorpherState.sol";


abstract contract DeployOrUpgrade is Script {
    using stdJson for string;

    struct Addresses {
        address accessControl;
        address admin;
        address airdrop;
        address bridge;
        address interestRateManager;
        address mintingLimiter;
        address oracle;
        address proxyAdmin;
        address state;
        address staking;
        address token;
        address tradeEngine;
        address userBlocking;
    }

    // function run() public {
    //     // Get deployer private key from environment
    //     uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
    //     vm.startBroadcast(deployerPrivateKey);

    //     // Load existing addresses
    //     Addresses memory addrs = loadAddresses();

    //     // Deploy ProxyAdmin if not already deployed
    //     if (addrs.proxyAdmin == address(0)) {
    //         addrs.proxyAdmin = deployProxyAdmin();
    //         console.log("Deployed ProxyAdmin at:", addrs.proxyAdmin);
    //     }

    //     // Deploy or upgrade MorpherAccessControl
    //     MorpherAccessControl implementation = new MorpherAccessControl();
    //     addrs.accessControl = deployOrUpgrade(
    //         addrs.accessControl,
    //         address(implementation),
    //         addrs.proxyAdmin,
    //         abi.encodeCall(MorpherAccessControl.initialize, ())
    //     );
    //     console.log("MorpherAccessControl at:", addrs.accessControl);

    //     // Deploy or upgrade MorpherState
    //     MorpherState stateImplementation = new MorpherState();
    //     addrs.state = deployOrUpgrade(
    //         addrs.state,
    //         address(stateImplementation),
    //         addrs.proxyAdmin,
    //         abi.encodeCall(MorpherState.initialize, (true, addrs.accessControl))
    //     );
    //     console.log("MorpherState at:", addrs.state);

    //     // Grant roles
    //     accessControl.grantRole(stateImplementation.ADMINISTRATOR_ROLE(), vm.addr(deployerPrivateKey));
    //     accessControl.grantRole(stateImplementation.GOVERNANCE_ROLE(), vm.addr(deployerPrivateKey));
        
    //     // Grant role to environment address if specified
    //     if (vm.envOr("MORPHER_ADMINISTRATOR", address(0)) != address(0)) {
    //         accessControl.grantRole(
    //             stateImplementation.ADMINISTRATOR_ROLE(),
    //             vm.envAddress("MORPHER_ADMINISTRATOR")
    //         );
    //     }

    //     // Save updated addresses
    //     saveAddresses(addrs);
        
    //     vm.stopBroadcast();
    // }

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
        if (!vm.isFile(path)) {
            string memory jsonObj = '{"accessControl": "0x0", "admin": "0x0", "airdrop": "0x0", "bridge": "0x0", "interestRateManager": "0x0", "mintingLimiter": "0x0", "oracle": "0x0", "proxyAdmin": "0x0", "state": "0x0", "staking": "0x0", "token": "0x0", "tradeEngine": "0x0", "userBlocking": "0x0"}';
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
        string memory jsonObj = '{"accessControl": "0x0", "admin": "0x0", "airdrop": "0x0", "bridge": "0x0", "interestRateManager": "0x0", "mintingLimiter": "0x0", "oracle": "0x0", "proxyAdmin": "0x0", "state": "0x0", "staking": "0x0", "token": "0x0", "tradeEngine": "0x0", "userBlocking": "0x0"}';

        if (!vm.isFile(path)) {
            vm.writeFile(path, jsonObj);
        }
        
        // Write each address individually to avoid stack too deep
        vm.writeJson(vm.toString(addrs.accessControl), path, ".accessControl");
        vm.writeJson(vm.toString(addrs.admin), path, ".admin");
        vm.writeJson(vm.toString(addrs.airdrop), path, ".airdrop");
        vm.writeJson(vm.toString(addrs.bridge), path, ".bridge");
        vm.writeJson(vm.toString(addrs.interestRateManager), path, ".interestRateManager");
        vm.writeJson(vm.toString(addrs.mintingLimiter), path, ".mintingLimiter");
        vm.writeJson(vm.toString(addrs.oracle), path, ".oracle");
        vm.writeJson(vm.toString(addrs.proxyAdmin), path, ".proxyAdmin");
        vm.writeJson(vm.toString(addrs.state), path, ".state");
        vm.writeJson(vm.toString(addrs.staking), path, ".staking");
        vm.writeJson(vm.toString(addrs.token), path, ".token");
        vm.writeJson(vm.toString(addrs.tradeEngine), path, ".tradeEngine");
        vm.writeJson(vm.toString(addrs.userBlocking), path, ".userBlocking");
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
