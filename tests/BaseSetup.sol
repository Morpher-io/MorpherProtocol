// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "../contracts/MorpherAccessControl.sol";
import "../contracts/MorpherState.sol";
import "../contracts/MorpherUserBlocking.sol";
import "../contracts/MorpherToken.sol";
import "../contracts/MorpherStaking.sol";
import "../contracts/MorpherMintingLimiter.sol";
import "../contracts/MorpherTradeEngine.sol";
import "../contracts/MorpherOracle.sol";
import "../contracts/MorpherAirdrop.sol";
import "../contracts/MorpherInterestRateManager.sol";
import "../contracts/MorpherSidechainToBaseMigration.sol";
import "../contracts/MorpherBridge.sol"; // Added MorpherBridge import

import "../lib/uniswap-v3-periphery/contracts/interfaces/external/IWETH9.sol";
import {ISwapRouter} from "../lib/uniswap-v3-periphery/contracts/interfaces/ISwapRouter.sol";


contract BaseSetup is Test {
	using stdStorage for StdStorage;

	bool isMainChain = true;
	bool initialMint = false;
	address treasuryAddress = msg.sender;
	bool recoveryEnabled_baseSetup = false;
	ISwapRouter swapRouter_baseSetup = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

	MorpherAccessControl internal morpherAccessControl;
	MorpherState internal morpherState;
	MorpherUserBlocking internal morpherUserBlocking;
	MorpherToken internal morpherToken;
	MorpherStaking internal morpherStaking;
	MorpherMintingLimiter internal morpherMintingLimiter;
	MorpherTradeEngine internal morpherTradeEngine;
	MorpherOracle internal morpherOracle;
	MorpherInterestRateManager internal morpherInterestRateManager;
	MorpherAirdrop internal morpherAirdrop;
	MorpherSidechainToBaseMigration internal morpherMigration;
	MorpherBridge internal morpherBridge; // Added MorpherBridge variable

	function setUp() public virtual {
		//deploy Access Control
		morpherAccessControl = new MorpherAccessControl();
		morpherAccessControl.initialize();

		//deploy state
		morpherState = new MorpherState();
		morpherState.initialize(isMainChain, address(morpherAccessControl));

		morpherAccessControl.grantRole(morpherState.ADMINISTRATOR_ROLE(), address(this));

		//deploy userblocking
		morpherUserBlocking = new MorpherUserBlocking();
		morpherUserBlocking.initialize(address(morpherState));

		morpherState.setMorpherUserBlocking(address(morpherUserBlocking));

		//deploy token
		morpherToken = new MorpherToken();
		// Add the permit name argument (e.g., "Morpher")
		morpherToken.initialize(address(morpherAccessControl), address(morpherState), "Morpher");
		morpherState.setMorpherToken(address(morpherToken));
		if (initialMint) {
			morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(this));
			if (isMainChain) {
				morpherToken.mint(treasuryAddress, 425000000 ether);
			} else {
				morpherToken.mint(treasuryAddress, 575000000 ether);
			}
			morpherAccessControl.revokeRole(morpherToken.MINTER_ROLE(), address(this));
		}
		morpherToken.setRestrictTransfers(!isMainChain);

		//deploy interest rate manager
		vm.warp(1617094819);
		morpherInterestRateManager = new MorpherInterestRateManager();
		morpherInterestRateManager.initialize(address(morpherState));
		morpherInterestRateManager.addInterestRate(15000, 1617094819);
		morpherInterestRateManager.addInterestRate(30000, 1644491427);
		morpherState.setMorpherInterestRateManager(address(morpherInterestRateManager));
		vm.warp(1);

		//deploy staking
 		//deploy staking
 		vm.warp(1617094819);
 		morpherStaking = new MorpherStaking();
 		// Initialize with PRECISION (1e8) and current timestamp for tests
 		morpherStaking.initialize(address(morpherState), 10**8, block.timestamp);
 		morpherAccessControl.grantRole(morpherToken.BURNER_ROLE(), address(morpherStaking));
 		morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(morpherStaking));
 		morpherState.setMorpherStakingAddress(payable(address(morpherStaking)));
		morpherAccessControl.grantRole(morpherStaking.STAKINGADMIN_ROLE(), address(this));
		morpherStaking.setInterestRate(50000);
		vm.warp(1);

		//deploy mintingLimiter
		morpherMintingLimiter = new MorpherMintingLimiter();
		morpherMintingLimiter.initialize(
			address(morpherState),
			500000000000000000000000,
			5000000000000000000000000,
			260000);
		morpherState.setMorpherMintingLimiter(address(morpherMintingLimiter));
		morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(morpherMintingLimiter));

		//deploy tradeEngine
		morpherTradeEngine = new MorpherTradeEngine();
		morpherTradeEngine.initialize(address(morpherState), false, 1613399217);
		morpherAccessControl.grantRole(morpherToken.BURNER_ROLE(), address(morpherTradeEngine));
		morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(morpherTradeEngine));
		morpherAccessControl.grantRole(morpherTradeEngine.POSITIONADMIN_ROLE(), address(morpherTradeEngine));
		morpherState.setMorpherTradeEngine(address(morpherTradeEngine));
		// enable 1 market
		morpherState.activateMarket(keccak256("CRYPTO_BTC"));

		//deploy oracle
		morpherOracle = new MorpherOracle();
		// Add EIP712 name ("MorpherOracle") and version ("1") arguments
		morpherOracle.initialize(address(morpherState), payable(address(this)), 0, "MorpherOracle", "1");
		morpherAccessControl.grantRole(morpherTradeEngine.ORACLE_ROLE(), address(morpherOracle));
		morpherAccessControl.grantRole(morpherOracle.ORACLEOPERATOR_ROLE(), address(this));

		//deploy MorpherBridge
		address morpherBridgeImplementation = address(new MorpherBridge());
		bytes memory bridgeInitializerCall = abi.encodeCall(
			MorpherBridge.initialize,
			(address(morpherState), recoveryEnabled_baseSetup, swapRouter_baseSetup)
		);
		// Using a generic key for proxy deployment within BaseSetup, assuming a helper or direct UUPS deployment
		// For simplicity, directly instantiating the proxy logic here if no generic helper exists in BaseSetup.
		// This part might need adjustment if BaseSetup has a specific proxy deployment pattern.
		// For now, we'll assume a direct UUPS deployment pattern similar to how tests might do it.
		// However, since we removed Upgrades.sol, we'll deploy it as a simple contract for now and tests can wrap it if needed,
		// or we assume a proxy deployment mechanism is available.
		// For test purposes, direct instantiation of the logic contract is often sufficient if proxy behavior isn't the focus.
		// Let's deploy it as a UUPS proxy using a basic pattern if Upgrades.sol is not available.
		// We'll use a simple proxy pattern for now.
		// NOTE: For robust UUPS testing, a proper proxy deployment mechanism is needed.
		// This is a simplified approach for BaseSetup.
		bytes memory proxyCode = MinimalProxy.getCreationCode(morpherBridgeImplementation);
        address payable bridgeProxyAddress;
        assembly {
            bridgeProxyAddress := create(0, add(proxyCode, 0x20), mload(proxyCode))
        }
        require(bridgeProxyAddress != address(0), "Bridge proxy deployment failed");
        morpherBridge = MorpherBridge(bridgeProxyAddress);
        (bool success, ) = bridgeProxyAddress.call(bridgeInitializerCall);
        require(success, "Bridge initialization failed");


		morpherState.setMorpherBridgeAddress(address(morpherBridge));
		morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(morpherBridge));
		morpherAccessControl.grantRole(morpherToken.BURNER_ROLE(), address(morpherBridge));
		// Grant bridge admin and operator roles to the test contract (address(this)) for now
		// Specific tests can re-assign these to dedicated accounts if needed.
		morpherAccessControl.grantRole(morpherBridge.ADMINISTRATOR_ROLE(), address(this));
		morpherAccessControl.grantRole(morpherBridge.SIDECHAINOPERATOR_ROLE(), address(this));


		morpherAccessControl.revokeRole(morpherState.ADMINISTRATOR_ROLE(), address(this));
	}
}

// Minimal Proxy contract code (EIP-1167)
contract MinimalProxy {
    // Adapted from https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/ERC1967/ERC1967Proxy.sol
    // This is a very basic version for EIP-1167.
    // A more robust UUPS proxy would typically use ERC1967Proxy.
    // solhint-disable-next-line func-name-mixedcase
    function getCreationCode(address _logic) internal pure returns (bytes memory) {
        bytes20 logic_ = bytes20(_logic);
        return abi.encodePacked(
            hex"3d602d80600a3d3981f3363d3d373d3d3d363d73",
            logic_,
            hex"5af43d82803e903d91602b57fd5bf3"
        );
    }
}
