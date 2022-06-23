// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

import "forge-std/Test.sol";
import "../contracts/MorpherAccessControl.sol";
import "../contracts/MorpherState.sol";
import "../contracts/MorpherUserBlocking.sol";
import "../contracts/MorpherToken.sol";
import "../contracts/MorpherStaking.sol";
import "../contracts/MorpherMintingLimiter.sol";
import "../contracts/MorpherTradeEngine.sol";
import "../contracts/MorpherOracle.sol";
import "../contracts/MorpherBridge.sol";

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract BaseSetup is Test {
	using stdStorage for StdStorage;

	bool isMainChain = false;
	bool initialMint = false;
	address treasuryAddress = msg.sender;
	bool recoveryEnabled_baseSetup = false;
	ISwapRouter swapRouter_baseSetup =
		ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

	MorpherAccessControl internal morpherAccessControl;
	MorpherState internal morpherState;
	MorpherUserBlocking internal morpherUserBlocking;
	MorpherToken internal morpherToken;
	MorpherStaking internal morpherStaking;
	MorpherMintingLimiter internal morpherMintingLimiter;
	MorpherTradeEngine internal morpherTradeEngine;
	MorpherOracle internal morpherOracle;
	MorpherBridge internal morpherBridge;

	function setUp() public virtual {
		//deploy Access Control
		morpherAccessControl = new MorpherAccessControl();
		morpherAccessControl.initialize();

		//deploy state
		morpherState = new MorpherState();
		morpherState.initialize(isMainChain, address(morpherAccessControl));

		morpherAccessControl.grantRole(
			morpherState.ADMINISTRATOR_ROLE(),
			address(this)
		);
		//deploy userblocking
		morpherUserBlocking = new MorpherUserBlocking();
		morpherUserBlocking.initialize(address(morpherState));

		morpherState.setMorpherUserBlocking(address(morpherUserBlocking));

		//deploy token
		morpherToken = new MorpherToken();
		morpherToken.initialize(address(morpherAccessControl));
		morpherState.setMorpherToken(address(morpherToken));
		if (initialMint) {
			morpherAccessControl.grantRole(
				morpherToken.MINTER_ROLE(),
				address(this)
			);
			if (isMainChain) {
				morpherToken.mint(treasuryAddress, 425000000 ether);
				morpherToken.setTotalTokensOnOtherChain(575000000 ether);
			} else {
				morpherToken.mint(treasuryAddress, 575000000 ether);
				morpherToken.setTotalTokensOnOtherChain(425000000 ether);
			}
			morpherAccessControl.revokeRole(
				morpherToken.MINTER_ROLE(),
				address(this)
			);
		}
		morpherToken.setRestrictTransfers(!isMainChain);

		//deploy staking
		//TODO

		//deploy mintingLimiter
		//TODO

		//deploy tradeEngine
		//TODO

		//deploy oracle
		//TODO

		//deploy bridge
		morpherBridge = new MorpherBridge();
		morpherBridge.initialize(
			address(morpherState),
			recoveryEnabled_baseSetup,
			swapRouter_baseSetup
		);
		morpherState.setMorpherBridge(address(morpherBridge));
		morpherAccessControl.grantRole(
			morpherToken.BURNER_ROLE(),
			address(morpherBridge)
		);
		morpherAccessControl.grantRole(
			morpherToken.MINTER_ROLE(),
			address(morpherBridge)
		);
		morpherAccessControl.grantRole(
			morpherBridge.SIDECHAINOPERATOR_ROLE(),
			address(this)
		);

		morpherAccessControl.revokeRole(
			morpherState.ADMINISTRATOR_ROLE(),
			address(this)
		);
	}
}
