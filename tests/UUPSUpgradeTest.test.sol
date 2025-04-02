// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
// --- Use UnsafeUpgrades ---
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
// Remove Options import as UnsafeUpgrades doesn't use it
// import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import "../contracts/MorpherAccessControl.sol";
import "../contracts/MorpherState.sol"; // Needed for Token init
import "../contracts/MorpherToken.sol"; // V1 Implementation
import "../contracts/mocks/MorpherTokenV2.sol"; // V2 Implementation Mock
// Import proxy interface for try/catch
import {IUpgradeableProxy} from "../lib/openzeppelin-foundry-upgrades/src/internal/interfaces/IUpgradeableProxy.sol";


contract UUPSUpgradeTest is Test {

    // Use V1 contract type for proxy interaction initially
    MorpherToken internal morpherTokenProxy;
    MorpherAccessControl internal accessControlProxy;
    MorpherState internal stateProxy; // Need state for token init

    address internal tokenProxyAddress;
    address internal accessControlAddress;
    address internal stateAddress;

    // --- Implementation Instances (needed for UnsafeUpgrades) ---
    MorpherAccessControl internal accessControlImpl;
    MorpherState internal stateImpl;
    MorpherToken internal tokenImpl;

    // --- Remove Contract Names (not used by UnsafeUpgrades) ---
    // string constant ACCESS_CONTROL_V1 = "contracts/MorpherAccessControl.sol:MorpherAccessControl";
    // string constant STATE_V1 = "contracts/MorpherState.sol:MorpherState";
    // string constant TOKEN_V1 = "contracts/MorpherToken.sol:MorpherToken";
    // string constant TOKEN_V2_MOCK = "contracts/mocks/MorpherTokenV2.sol:MorpherTokenV2";

    // --- Initializer Args ---
    string constant TOKEN_PERMIT_NAME = "Morpher";

    // --- Roles ---
    bytes32 constant PROXYUPDATER_ROLE = keccak256("PROXYUPDATER_ROLE");

    address deployer; // Address running the test setup
    address unauthorizedUser = makeAddr("unauthorizedUser");

    function setUp() public virtual {
        deployer = address(this);

        // 1. Deploy Implementations first
        accessControlImpl = new MorpherAccessControl();
        stateImpl = new MorpherState();
        tokenImpl = new MorpherToken();

        // 2. Deploy Access Control via Proxy using UnsafeUpgrades
        bytes memory acInitData = abi.encodeCall(MorpherAccessControl.initialize, ());
        accessControlAddress = UnsafeUpgrades.deployUUPSProxy(address(accessControlImpl), acInitData);
        accessControlProxy = MorpherAccessControl(accessControlAddress);

        // Grant deployer admin role on AccessControl for setup
        // Note: Initializer already grants DEFAULT_ADMIN_ROLE and PROXYUPDATER_ROLE to deployer
        // accessControlProxy.grantRole(accessControlProxy.DEFAULT_ADMIN_ROLE(), deployer);

        // 3. Deploy State via Proxy (needed for Token)
        bytes memory stateInitData = abi.encodeCall(MorpherState.initialize, (true, accessControlAddress));
        stateAddress = UnsafeUpgrades.deployUUPSProxy(address(stateImpl), stateInitData);
        stateProxy = MorpherState(stateAddress);

        // 4. Deploy MorpherToken V1 via Proxy
        bytes memory tokenInitData = abi.encodeCall(MorpherToken.initialize, (accessControlAddress, stateAddress, TOKEN_PERMIT_NAME));
        // Use UnsafeUpgrades with implementation address
        tokenProxyAddress = UnsafeUpgrades.deployUUPSProxy(address(tokenImpl), tokenInitData);
        morpherTokenProxy = MorpherToken(tokenProxyAddress);

        // 5. Set Token address in State (needed by Token's _authorizeUpgrade) // Update comment number
        accessControlProxy.grantRole(stateProxy.ADMINISTRATOR_ROLE(), deployer);
        stateProxy.setMorpherToken(tokenProxyAddress);
    }

    // --- Test Cases ---

    function test_UUPSUpgrade_Fail_Unauthorized() public {
        // Deploy V2 implementation manually
        MorpherTokenV2 implV2 = new MorpherTokenV2();
        IUpgradeableProxy proxy = IUpgradeableProxy(tokenProxyAddress);

        // Attempt upgrade from an unauthorized address using try/catch
        vm.prank(unauthorizedUser); // Use regular prank for the try/catch block
        try proxy.upgradeToAndCall(address(implV2), "") {
            // If the call succeeds, the test should fail
            revert("Upgrade by unauthorized user should have reverted");
        } catch Error(string memory reason) {
            // Assert that the revert reason matches the one from _authorizeUpgrade
            assertEq(reason, "MorpherToken: Caller is not the proxy updater", "Incorrect revert reason");
        } catch (bytes memory /*lowLevelData*/) {
            // Catch other potential revert types (Panic, etc.) and fail
            revert("Upgrade reverted with unexpected error type");
        }
        // Note: We are not calling UnsafeUpgrades.upgradeProxy here,
        // as we are directly testing the proxy call that fails.
    }

    function test_UUPSUpgrade_Success() public {
        // Deploy V2 implementation manually
        MorpherTokenV2 implV2 = new MorpherTokenV2();

        // Grant PROXYUPDATER_ROLE to the deployer (address(this))
        // Note: Deployer should already have this from AccessControl initializer
        // accessControlProxy.grantRole(PROXYUPDATER_ROLE, deployer);
        assertTrue(accessControlProxy.hasRole(PROXYUPDATER_ROLE, deployer), "Deployer should have PROXYUPDATER_ROLE");

        // Get implementation address before upgrade
        address implV1Address = UnsafeUpgrades.getImplementationAddress(tokenProxyAddress);

        // Perform upgrade as the authorized deployer
        vm.prank(deployer);
        // Use UnsafeUpgrades.upgradeProxy with implementation address
        UnsafeUpgrades.upgradeProxy(tokenProxyAddress, address(implV2), "");

        // Verify implementation address changed
        address implV2Address = UnsafeUpgrades.getImplementationAddress(tokenProxyAddress);
        assertNotEq(implV1Address, implV2Address, "Implementation address should change after upgrade");

        // Interact with V2 via the *same proxy address*
        MorpherTokenV2 morpherTokenV2 = MorpherTokenV2(tokenProxyAddress);
        assertEq(morpherTokenV2.getVersion(), 2, "Proxy should now point to V2 logic");
    }

     function test_UUPSUpgrade_Success_WithInitializer() public {
        // Deploy V2 implementation manually
        MorpherTokenV2 implV2 = new MorpherTokenV2();

        // Grant PROXYUPDATER_ROLE to the deployer
        assertTrue(accessControlProxy.hasRole(PROXYUPDATER_ROLE, deployer), "Deployer should have PROXYUPDATER_ROLE");

        // Prepare V2 initializer call data
        bytes memory upgradeData = abi.encodeCall(MorpherTokenV2.initializeV2, (accessControlAddress));

        // Perform upgrade as the authorized deployer, including the call data
        vm.prank(deployer);
        // Use UnsafeUpgrades.upgradeProxy with implementation address
        UnsafeUpgrades.upgradeProxy(tokenProxyAddress, address(implV2), upgradeData);

        // Interact with V2 via the proxy address
        MorpherTokenV2 morpherTokenV2 = MorpherTokenV2(tokenProxyAddress);
        assertEq(morpherTokenV2.getVersion(), 2, "Proxy should now point to V2 logic after upgrade+init");
        assertEq(morpherTokenV2.accessControl(), accessControlAddress, "V2 initializer should have set AC address");
    }
}
