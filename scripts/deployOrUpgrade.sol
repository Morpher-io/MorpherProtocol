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
            return getEmptyAddresses();
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

    function loadAddressesFromJson(string memory json) internal returns (Addresses memory addrs) {
        // Load first batch of addresses
        addrs.proxyAdmin = json.readAddress(".proxyAdmin");
        addrs.accessControl = json.readAddress(".accessControl");
        addrs.state = json.readAddress(".state");
        addrs.userBlocking = json.readAddress(".userBlocking");
        addrs.token = json.readAddress(".token");
        addrs.staking = json.readAddress(".staking");
        
        // Load second batch of addresses
        addrs.mintingLimiter = json.readAddress(".mintingLimiter");
        addrs.tradeEngine = json.readAddress(".tradeEngine");
        addrs.oracle = json.readAddress(".oracle");
        addrs.bridge = json.readAddress(".bridge");
        addrs.admin = json.readAddress(".admin");
        addrs.interestRateManager = json.readAddress(".interestRateManager");
        addrs.airdrop = json.readAddress(".airdrop");
        
        return addrs;
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
