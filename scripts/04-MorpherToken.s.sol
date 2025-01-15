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

import {DeployOrUpgrade} from "./deployOrUpgrade.sol";

//morpher contracts
import {MorpherToken} from "../contracts/MorpherToken.sol";
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol";

contract DeployMorpherToken is DeployOrUpgrade {
    using stdJson for string;

    function run() public {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);

        // Load AccessControl address - required for Token initialization
        address accessControlAddress = loadAddress("MorpherAccessControl");
        require(accessControlAddress != address(0), "AccessControl must be deployed first");

        // Deploy or upgrade MorpherToken
        address existingToken = loadAddress("MorpherToken");
        MorpherToken implementation = new MorpherToken();
        
        address token = deployOrUpgrade(
            existingToken,
            address(implementation),
            abi.encodeCall(MorpherToken.initialize, (accessControlAddress)),
            "MorpherToken.sol"
        );
        
        saveAddress("MorpherToken", token);
        console.log("MorpherToken at:", token);

        // Only set roles and mint for new deployments
        if (existingToken == address(0)) {
            MorpherAccessControl accessControl = MorpherAccessControl(accessControlAddress);
            MorpherToken tokenContract = MorpherToken(token);
            
            // Grant initial roles to deployer
            accessControl.grantRole(implementation.PAUSER_ROLE(), vm.addr(deployerPrivateKey));
            accessControl.grantRole(implementation.ADMINISTRATOR_ROLE(), vm.addr(deployerPrivateKey));
            accessControl.grantRole(implementation.MINTER_ROLE(), vm.addr(deployerPrivateKey));

            // Get treasury address from environment or use deployer
            address treasuryAddress = vm.envOr("MORPHER_TREASURY", vm.addr(deployerPrivateKey));

            // Mint tokens and set other chain balance
            uint256 _mainChainMint = 425_000_000 ether;
            // uint256 _sideChainMint = 575_000_000 ether;
            
            tokenContract.mint(treasuryAddress, _mainChainMint);
            tokenContract.setTotalTokensOnOtherChain(_sideChainMint);

            // Configure State with token address
            address stateAddress = loadAddress("MorpherState");
            if (stateAddress != address(0)) {
                MorpherState state = MorpherState(stateAddress);
                state.setMorpherToken(token);
            }

            // Revoke minter role from deployer
            accessControl.revokeRole(implementation.MINTER_ROLE(), vm.addr(deployerPrivateKey));
        }
        
        vm.stopBroadcast();
    }
}
