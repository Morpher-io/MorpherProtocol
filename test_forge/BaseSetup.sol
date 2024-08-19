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
		vm.warp(1617094819);
		morpherStaking = new MorpherStaking();
		morpherStaking.initialize(address(morpherState));
		morpherAccessControl.grantRole(
      		morpherStaking.STAKINGADMIN_ROLE(),
			address(this)
    	);
    	morpherStaking.addInterestRate(15000,1617094819);
    	morpherStaking.addInterestRate(30000,1644491427);
    	morpherAccessControl.grantRole(
      		morpherToken.BURNER_ROLE(),
      		address(morpherStaking)
		);
		morpherAccessControl.grantRole(
			morpherToken.MINTER_ROLE(),
			address(morpherStaking)
		);
    	morpherState.setMorpherStaking(payable(address(morpherStaking)));
		vm.warp(1);

		//deploy mintingLimiter
		morpherMintingLimiter = new MorpherMintingLimiter(
			address(morpherState),
			500000000000000000000000,
			5000000000000000000000000,
			260000
		);
		morpherState.setMorpherMintingLimiter(address(morpherMintingLimiter));
		morpherAccessControl.grantRole(
			morpherToken.MINTER_ROLE(),
			address(morpherMintingLimiter)
		);

		//deploy tradeEngine
		morpherTradeEngine = new MorpherTradeEngine();
		morpherTradeEngine.initialize(address(morpherState), false, 1613399217);
  		for (uint i = 0; i < morpherStaking.numInterestRates(); i++) {
			(uint256 validFrom, uint256 rate) = morpherStaking.interestRates(i);
			vm.warp(validFrom-100);
			morpherTradeEngine.addInterestRate(rate, validFrom);
		}
		vm.warp(1);
		morpherAccessControl.grantRole(
			morpherToken.BURNER_ROLE(),
			address(morpherTradeEngine)
		);
		morpherAccessControl.grantRole(
			morpherTradeEngine.POSITIONADMIN_ROLE(),
			address(morpherTradeEngine)
		);
		morpherState.setMorpherTradeEngine(address(morpherTradeEngine));

		//deploy oracle
		morpherOracle = new MorpherOracle();
		morpherOracle.initialize(address(morpherState), payable(address(this)), 0);
		morpherAccessControl.grantRole(morpherOracle.ORACLEOPERATOR_ROLE(), address(this));

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
