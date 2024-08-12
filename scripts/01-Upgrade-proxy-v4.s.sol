//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Upgrades} from "openzeppelin-foundry-upgrades/LegacyUpgrades.sol";
import "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {Script} from "forge-std/Script.sol";
import {MorpherAccessControl} from "../contracts/MorpherAccessControl.sol";
import {ProxyAdmin} from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

import {MorpherToken} from "../contracts/MorpherToken.sol";
import {MorpherOracle} from "../contracts/MorpherOracle.sol";
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

contract UpgradeProxyV4Versions is Script {
	// address constant CHEATCODE_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

	function run() public {
		uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
		vm.startBroadcast(deployerPrivateKey);
		// _tryUpBalance(msg.sender);
		// vm.startBroadcast();
		ProxyAdmin admin = ProxyAdmin(0x3cFa9C5F4238fe6200b73038b1e6daBb5F6b8A0a);
		console.log(admin.owner());
		console.log(address(this));
		console.log(msg.sender);
		console.log(address(msg.sender).balance);

		Options memory opts;
		Upgrades.validateUpgrade("MorpherAccessControl.sol", opts);
		Upgrades.validateUpgrade("MorpherState.sol", opts);
		Upgrades.validateUpgrade("MorpherToken.sol", opts);
		Upgrades.validateUpgrade("MorpherTradeEngine.sol", opts);
		Upgrades.validateUpgrade("MorpherOracle.sol", opts);

		address oracleProxyAddress = 0x21Fd95b46FC655BfF75a8E74267Cfdc7efEBdb6A;
		MorpherOracle newOracle = new MorpherOracle();
		
		admin.upgrade(ITransparentUpgradeableProxy(oracleProxyAddress), address(newOracle));
		MorpherOracle oracleInstance = MorpherOracle(oracleProxyAddress);
		oracleInstance.setWmaticAddress(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

		address tradeEngineAddress = 0x005cb9Ad7C713bfF25ED07F3d9e1C3945e543cd5;
		MorpherTradeEngine newTradeEngine = new MorpherTradeEngine();
		admin.upgrade(ITransparentUpgradeableProxy(tradeEngineAddress), address(newTradeEngine));

		address morpherTokenAddress = 0x65C9e3289e5949134759119DBc9F862E8d6F2fBE;
		MorpherToken newMorpherToken = new MorpherToken();
		admin.upgrade(ITransparentUpgradeableProxy(morpherTokenAddress), address(newMorpherToken));
		MorpherToken tokenProxy = MorpherToken(morpherTokenAddress);
		tokenProxy.setHashedName("MorpherToken");
		tokenProxy.setHashedVersion("1");

		address wmaticAddress = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
		address uniswapQuoterAddress = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;

		MorpherPriceOracle morpherPriceOracle = new MorpherPriceOracle(
			morpherTokenAddress,
			wmaticAddress,
			uniswapQuoterAddress
		);

		console.log("Price Oracle", address(morpherPriceOracle));

		address entryPointV6Address = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
		address uniswapV3Router2Address = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

		MorpherTokenPaymaster.TokenPaymasterConfig memory tokenPaymasterConfig = MorpherTokenPaymaster
			.TokenPaymasterConfig(1e26, 100000000000000, 20000, 60);
		OracleHelper.OracleHelperConfig memory oracleHelperConfig = OracleHelper.OracleHelperConfig(
			60,
			60,
			IOracle(address(morpherPriceOracle)),
			IOracle(address(0)),
			true,
			false,
			false,
			100000
		);

		UniswapHelper.UniswapHelperConfig memory uniswapHelperConfig = UniswapHelper.UniswapHelperConfig(
			100000000,
			300,
			100
		);
		MorpherTokenPaymaster tokenPaymaster = new MorpherTokenPaymaster(
			IERC20Metadata(morpherTokenAddress),
			IEntryPoint(entryPointV6Address),
			IERC20Metadata(wmaticAddress),
			ISwapRouter(uniswapV3Router2Address),
			tokenPaymasterConfig,
			oracleHelperConfig,
			uniswapHelperConfig,
			msg.sender
		);
		console.log("Token Paymaster", address(tokenPaymaster));
	}
}
