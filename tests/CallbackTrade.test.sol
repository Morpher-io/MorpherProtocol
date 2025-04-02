// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20; // Update pragma if needed

import "forge-std/Test.sol";
// --- Use UnsafeUpgrades ---
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {Script} from "forge-std/Script.sol";
// --- Use V5 Contracts ---
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol";
// Remove ProxyAdmin import
// import {ProxyAdmin} from "openzeppelin-contracts-5/contracts/proxy/transparent/ProxyAdmin.sol";
// Remove Options import
// import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

import {MorpherOracle} from "../contracts/MorpherOracle.sol";
import {MorpherState} from "../contracts/MorpherState.sol";
import {MorpherToken} from "../contracts/MorpherToken.sol";
import {MorpherTradeEngine} from "../contracts/MorpherTradeEngine.sol";
import {OracleHelper} from "account-abstraction-v7/samples/utils/OracleHelper.sol";
import {IOracle} from "account-abstraction-v7/samples/utils/IOracle.sol";
import {UniswapHelper} from "account-abstraction-v7/samples/utils/UniswapHelper.sol";
import {ISwapRouter} from "uniswap-v3-periphery/interfaces/ISwapRouter.sol";

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol"; // Keep if used

// Remove ITransparentUpgradeableProxy import
// import {ITransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol"; // Keep if used

interface UniswapQuoter {
	function factory() external view returns (address);
	function WETH9() external view returns (address);

	function quoteExactOutputSingle(
		address tokenIn,
		address tokenOut,
		uint24 fee,
		uint256 amountOut,
		uint160 sqrtPriceLimitX96
	) external view returns (uint256 amountIn);
}
// Test if callbacks are working
// forge test --match-test testCallbackOracle --fork-url=...
contract CallbackTrade is Test {
	address tradeEngineAddress = 0x005cb9Ad7C713bfF25ED07F3d9e1C3945e543cd5;
	address oracleProxyAddress = 0x21Fd95b46FC655BfF75a8E74267Cfdc7efEBdb6A;
	address morpherStateAddress = 0x1ce1efda5d52dE421BD3BC1CCc85977D7a0a0F1e;

	bytes32 public constant CRYPTO_BTC = keccak256("CRYPTO_BTC");
	bytes32 public constant CRYPTO_ETH = keccak256("CTYPTO_ETH");

	// Define PROXYUPDATER_ROLE for clarity
	bytes32 constant PROXYUPDATER_ROLE = keccak256("PROXYUPDATER_ROLE");

	function _testCallbackOracle() public {
		// --- Use V5 contract interfaces ---
		MorpherState state = MorpherState(morpherStateAddress);
		MorpherOracle oracle = MorpherOracle(oracleProxyAddress);
		MorpherToken morpherToken = MorpherToken(state.morpherTokenAddress());
		MorpherAccessControl morpherAccessControl = MorpherAccessControl(state.morpherAccessControlAddress());
		// Remove ProxyAdmin

		// --- Assume the prank address has PROXYUPDATER_ROLE for upgrades ---
		address proxyUpdater = 0x51c5cE7C4926D5cA74f4824e11a062f1Ef491762;
		// Grant the role if needed (might require another admin prank)
		// vm.startPrank(admin_address);
		// morpherAccessControl.grantRole(PROXYUPDATER_ROLE, proxyUpdater);
		// vm.stopPrank();

		vm.startPrank(proxyUpdater);
		// Deploy new implementations first
		MorpherOracle newOracleImpl = new MorpherOracle();
		MorpherTradeEngine newTradeEngineImpl = new MorpherTradeEngine();
		MorpherAccessControl newAccessControlImpl = new MorpherAccessControl();

		// Upgrade using UnsafeUpgrades
		UnsafeUpgrades.upgradeProxy(oracleProxyAddress, address(newOracleImpl), "");
		UnsafeUpgrades.upgradeProxy(tradeEngineAddress, address(newTradeEngineImpl), "");
		UnsafeUpgrades.upgradeProxy(state.morpherAccessControlAddress(), address(newAccessControlImpl), "");

		// Grant roles using the (potentially upgraded) access control instance
		morpherAccessControl.grantRole(oracle.ORACLEOPERATOR_ROLE(), 0x58f0442c8F9C9ecd2a09b9De3f1D834068387304);
		morpherAccessControl.grantRole(oracle.ORACLEOPERATOR_ROLE(), 0x1fdd1bB9AFc69F19ebBF55ceB5153c43b5C5bc1E);
		morpherAccessControl.grantRole(oracle.ORACLEOPERATOR_ROLE(), 0x181AD9eBA392b8001eeAD315e50E9fD9572116D2);
		morpherAccessControl.grantRole(oracle.ADMINISTRATOR_ROLE(), 0xA6c5c9c90910c9C12F31c0eB7997C24dDdc75AFE);
		morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), tradeEngineAddress);
		morpherAccessControl.grantRole(morpherToken.BURNER_ROLE(), tradeEngineAddress);
		vm.stopPrank();
		vm.startPrank(0xA6c5c9c90910c9C12F31c0eB7997C24dDdc75AFE);
		state.activateMarket(CRYPTO_BTC);
		state.activateMarket(CRYPTO_ETH);
		vm.stopPrank();
		vm.startPrank(0x5AD2d0Ebe451B9bC2550e600f2D2Acd31113053E);
		bytes32 orderId = oracle.createOrder(CRYPTO_BTC, 0, 10 ether, true, 1e9, 0, 0, 0, 0);
		vm.stopPrank();
		vm.startPrank(0x58f0442c8F9C9ecd2a09b9De3f1D834068387304);
		oracle.__callback(orderId, 50000 * 1e9, 50000 * 1e9, 500 * 1e9, 0, block.timestamp * 1000, 0);
		vm.stopPrank();
	}
	
}
