// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/LegacyUpgrades.sol";
import "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {Script} from "forge-std/Script.sol";
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol";
import {ProxyAdmin} from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

import {MorpherOracle} from "../contracts/MorpherOracle.sol";
import {MorpherState} from "../contracts/MorpherState.sol";
import {MorpherToken} from "../contracts/MorpherToken.sol";
import {MorpherTradeEngine} from "../contracts/MorpherTradeEngine.sol";
import {MorpherPriceOracle} from "../contracts/MorpherPriceOracle.sol";
import {MorpherTokenPaymaster} from "../contracts/MorpherTokenPaymaster.sol";
import {OracleHelper} from "account-abstraction-v7/samples/utils/OracleHelper.sol";
import {IOracle} from "account-abstraction-v7/samples/utils/IOracle.sol";
import {UniswapHelper} from "account-abstraction-v7/samples/utils/UniswapHelper.sol";
import {ISwapRouter} from "uniswap-v3-periphery/interfaces/ISwapRouter.sol";

import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";

import {ITransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// Test if callbacks are working
// forge test --match-test testCallbackOracle --fork-url=...
contract CallbackTrade is Test {
	address tradeEngineAddress = 0x005cb9Ad7C713bfF25ED07F3d9e1C3945e543cd5;
	address oracleProxyAddress = 0x21Fd95b46FC655BfF75a8E74267Cfdc7efEBdb6A;
	address morpherStateAddress = 0x1ce1efda5d52dE421BD3BC1CCc85977D7a0a0F1e;

	bytes32 public constant CRYPTO_BTC = keccak256("CRYPTO_BTC");
	bytes32 public constant CRYPTO_ETH = keccak256("CTYPTO_ETH");

	function testCallbackOracle() public {

		MorpherState state = MorpherState(morpherStateAddress);
		MorpherTradeEngine tradeEngine = MorpherTradeEngine(tradeEngineAddress);
		MorpherOracle oracle = MorpherOracle(oracleProxyAddress);
        MorpherToken morpherToken = MorpherToken(state.morpherTokenAddress());
        ProxyAdmin admin = ProxyAdmin(0x3cFa9C5F4238fe6200b73038b1e6daBb5F6b8A0a);

		vm.startPrank(0x51c5cE7C4926D5cA74f4824e11a062f1Ef491762);
        MorpherOracle newOracle = new MorpherOracle();
		admin.upgrade(ITransparentUpgradeableProxy(oracleProxyAddress), address(newOracle));

		MorpherTradeEngine newTradeEngine = new MorpherTradeEngine();
		admin.upgrade(ITransparentUpgradeableProxy(tradeEngineAddress), address(newTradeEngine));
		MorpherAccessControl newAccessControl = new MorpherAccessControl();
		admin.upgrade(ITransparentUpgradeableProxy(state.morpherAccessControlAddress()), address(newAccessControl));
		MorpherAccessControl morpherAccessControl = MorpherAccessControl(0x139950831d8338487db6807c6FdAeD1827726dF2);
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
		oracle.__callback(
			orderId,
			50000*1e9,
			50000*1e9,
			500*1e9,
			0,
			block.timestamp * 1000,
			0
		);
		vm.stopPrank();
	}
}
