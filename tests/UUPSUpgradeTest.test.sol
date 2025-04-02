// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol"; // Use V5 Upgrades
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import "../contracts/MorpherAccessControl.sol";
import "../contracts/MorpherState.sol"; // Needed for Token init
import "../contracts/MorpherToken.sol"; // V1 Implementation
import "../contracts/mocks/MorpherTokenV2.sol"; // V2 Implementation Mock

contract UUPSUpgradeTest is Test {

    // Use V1 contract type for proxy interaction initially
    MorpherToken internal morpherTokenProxy;
    MorpherAccessControl internal accessControlProxy;
    MorpherState internal stateProxy; // Need state for token init

    address internal tokenProxyAddress;
    address internal accessControlAddress;
    address internal stateAddress;

    // --- Contract Names for Upgrades Plugin ---
    string constant ACCESS_CONTROL_V1 = "contracts/MorpherAccessControl.sol:MorpherAccessControl";
    string constant STATE_V1 = "contracts/MorpherState.sol:MorpherState";
    string constant TOKEN_V1 = "contracts/MorpherToken.sol:MorpherToken";
    string constant TOKEN_V2_MOCK = "contracts/mocks/MorpherTokenV2.sol:MorpherTokenV2";

    // --- Initializer Args ---
    string constant TOKEN_PERMIT_NAME = "Morpher";

    // --- Roles ---
    bytes32 constant PROXYUPDATER_ROLE = keccak256("PROXYUPDATER_ROLE");

    address deployer; // Address running the test setup
    address unauthorizedUser = makeAddr("unauthorizedUser");

    function setUp() public virtual {
        deployer = address(this);

        // 1. Deploy Access Control via Proxy
        bytes memory acInitData = abi.encodeCall(MorpherAccessControl.initialize, ());
        accessControlAddress = Upgrades.deployUUPSProxy(ACCESS_CONTROL_V1, acInitData, Options({}));
        accessControlProxy = MorpherAccessControl(accessControlAddress);

        // Grant deployer admin role on AccessControl for setup
        // Note: Initializer already grants DEFAULT_ADMIN_ROLE and PROXYUPDATER_ROLE to deployer
        // accessControlProxy.grantRole(accessControlProxy.DEFAULT_ADMIN_ROLE(), deployer);

        // 2. Deploy State via Proxy (needed for Token)
        bytes memory stateInitData = abi.encodeCall(MorpherState.initialize, (true, accessControlAddress));
        stateAddress = Upgrades.deployUUPSProxy(STATE_V1, stateInitData, Options({}));
        stateProxy = MorpherState(stateAddress);

        // 3. Deploy MorpherToken V1 via Proxy
        bytes memory tokenInitData = abi.encodeCall(MorpherToken.initialize, (accessControlAddress, stateAddress, TOKEN_PERMIT_NAME));
        tokenProxyAddress = Upgrades.deployUUPSProxy(TOKEN_V1, tokenInitData, Options({}));
        morpherTokenProxy = MorpherToken(tokenProxyAddress);

        // 4. Set Token address in State (needed by Token's _authorizeUpgrade)
        stateProxy.setMorpherToken(tokenProxyAddress);
    }

    // --- Test Cases ---

    function test_UUPSUpgrade_Fail_Unauthorized() public {
        // V2 implementation is needed for the upgrade attempt
        // Deploying it here just to get the artifact name, Upgrades.upgradeProxy deploys it again
        // MorpherTokenV2 implV2 = new MorpherTokenV2(); // Not strictly needed

        // Attempt upgrade from an unauthorized address
        vm.prank(unauthorizedUser);

        // Expect revert from _authorizeUpgrade (or AccessControl if role check fails there)
        vm.expectRevert(bytes("MorpherToken: Caller is not the proxy updater")); // Match error in MorpherToken V1's _authorizeUpgrade
        Upgrades.upgradeProxy(tokenProxyAddress, TOKEN_V2_MOCK, "", Options({}));
    }

    function test_UUPSUpgrade_Success() public {
        // V2 implementation artifact name is needed
        // MorpherTokenV2 implV2 = new MorpherTokenV2(); // Not strictly needed

        // Grant PROXYUPDATER_ROLE to the deployer (address(this))
        // Note: Deployer should already have this from AccessControl initializer
        // accessControlProxy.grantRole(PROXYUPDATER_ROLE, deployer);
        assertTrue(accessControlProxy.hasRole(PROXYUPDATER_ROLE, deployer), "Deployer should have PROXYUPDATER_ROLE");

        // Get implementation address before upgrade
        address implV1Address = Upgrades.getImplementationAddress(tokenProxyAddress);

        // Perform upgrade as the authorized deployer
        vm.prank(deployer);
        // Use upgradeProxy - it deploys V2 and calls upgradeTo on the proxy
        Upgrades.upgradeProxy(tokenProxyAddress, TOKEN_V2_MOCK, "", Options({}));

        // Verify implementation address changed
        address implV2Address = Upgrades.getImplementationAddress(tokenProxyAddress);
        assertNotEq(implV1Address, implV2Address, "Implementation address should change after upgrade");

        // Interact with V2 via the *same proxy address*
        MorpherTokenV2 morpherTokenV2 = MorpherTokenV2(tokenProxyAddress);
        assertEq(morpherTokenV2.getVersion(), 2, "Proxy should now point to V2 logic");
    }

     function test_UUPSUpgrade_Success_WithInitializer() public {
        // Grant PROXYUPDATER_ROLE to the deployer
        assertTrue(accessControlProxy.hasRole(PROXYUPDATER_ROLE, deployer), "Deployer should have PROXYUPDATER_ROLE");

        // Prepare V2 initializer call data
        bytes memory upgradeData = abi.encodeCall(MorpherTokenV2.initializeV2, (accessControlAddress));

        // Perform upgrade as the authorized deployer, including the call data
        vm.prank(deployer);
        Upgrades.upgradeProxy(tokenProxyAddress, TOKEN_V2_MOCK, upgradeData, Options({}));

        // Interact with V2 via the proxy address
        MorpherTokenV2 morpherTokenV2 = MorpherTokenV2(tokenProxyAddress);
        assertEq(morpherTokenV2.getVersion(), 2, "Proxy should now point to V2 logic after upgrade+init");
        assertEq(morpherTokenV2.accessControl(), accessControlAddress, "V2 initializer should have set AC address");
    }
}
