// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "forge-std/Test.sol";
import "../contracts/MorpherAccessControl.sol";
import "../contracts/MorpherState.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract SimpleProxy is Test {
	using stdStorage for StdStorage;

	MorpherAccessControl private morpherAccessControl;
	MorpherState private morpherState;
	TransparentUpgradeableProxy private transparentProxyState;
	TransparentUpgradeableProxy private transparentProxyAccessControl;
	ProxyAdmin private proxyAdmin;

	MorpherAccessControl private proxiedAccessControl;
	MorpherState private proxiedState;

	function setUp() public {
		// Deploy NFT contract
		morpherState = new MorpherState();
		morpherAccessControl = new MorpherAccessControl();

		transparentProxyAccessControl = new TransparentUpgradeableProxy(
			address(morpherAccessControl),
			address(this),
			""
		);
		transparentProxyState = new TransparentUpgradeableProxy(address(morpherState), address(this), "");

		proxyAdmin = new ProxyAdmin();

		ITransparentUpgradeableProxy(address(transparentProxyAccessControl)).changeAdmin(address(proxyAdmin));
		ITransparentUpgradeableProxy(address(transparentProxyState)).changeAdmin(address(proxyAdmin));

		MorpherAccessControl(address(transparentProxyAccessControl)).initialize();
		MorpherState(address(transparentProxyState)).initialize(false, address(transparentProxyAccessControl));

		proxiedAccessControl = MorpherAccessControl(address(transparentProxyAccessControl));
		proxiedState = MorpherState(address(transparentProxyState));
	}

	function testHasRole() public {
		assertEq(proxiedAccessControl.hasRole(proxiedState.ADMINISTRATOR_ROLE(), address(this)), false);

		proxiedAccessControl.grantRole(proxiedState.ADMINISTRATOR_ROLE(), address(this));

		assertEq(proxiedAccessControl.hasRole(proxiedState.ADMINISTRATOR_ROLE(), address(this)), true);
	}
}
