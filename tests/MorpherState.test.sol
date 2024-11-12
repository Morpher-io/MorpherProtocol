// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "./BaseSetup.sol";
import "../contracts/MorpherUserBlocking.sol";

contract MorpherStateTest is BaseSetup, MorpherState {
	address _newAddress = address(0xffff);
	address _admin = address(0xaaaa);

	function setUp() public override {
		super.setUp();
		morpherAccessControl.grantRole(ADMINISTRATOR_ROLE, _admin);
	}

	function generatePosition(bytes32 market, address user) public {
		morpherAccessControl.grantRole(keccak256("MINTER_ROLE"), address(this));
		morpherToken.mint(user, 100 * 10 ** 18);
		morpherAccessControl.revokeRole(keccak256("MINTER_ROLE"), address(this));

		vm.prank(address(morpherOracle));
		bytes32 orderId = morpherTradeEngine.requestOrderId(user, market, 0, 100 * 10 ** 18, true, 10 ** 8);

		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(orderId, 1000 * 10 ** 8, 10 ** 8, 0, block.timestamp * 1000);
	}

	function testAddressSetting() public {
		vm.startPrank(_admin);

		vm.expectEmit(true, true, false, false);
		emit SetMorpherAirdropAddress(morpherState.morpherAirdropAddress(), _newAddress);
		morpherState.setMorpherAirdrop(_newAddress);
		assertEq(morpherState.morpherAirdropAddress(), _newAddress);

		vm.expectEmit(true, true, false, false);
		emit SetMorpherBridgeAddress(morpherState.morpherBridgeAddress(), _newAddress);
		morpherState.setMorpherBridge(_newAddress);
		assertEq(morpherState.morpherBridgeAddress(), _newAddress);

		vm.expectEmit(true, true, false, false);
		emit SetMorpherFaucetAddress(morpherState.morpherFaucetAddress(), _newAddress);
		morpherState.setMorpherFaucet(_newAddress);
		assertEq(morpherState.morpherFaucetAddress(), _newAddress);

		vm.expectEmit(true, true, false, false);
		emit SetMorpherGovernanceAddress(morpherState.morpherGovernanceAddress(), _newAddress);
		morpherState.setMorpherGovernance(_newAddress);
		assertEq(morpherState.morpherGovernanceAddress(), _newAddress);

		vm.expectEmit(true, true, false, false);
		emit SetMorpherMintingLimiterAddress(morpherState.morpherMintingLimiterAddress(), _newAddress);
		morpherState.setMorpherMintingLimiter(_newAddress);
		assertEq(morpherState.morpherMintingLimiterAddress(), _newAddress);

		vm.expectEmit(true, true, false, false);
		emit SetMorpherOracleAddress(morpherState.morpherOracleAddress(), _newAddress);
		morpherState.setMorpherOracle(_newAddress);
		assertEq(morpherState.morpherOracleAddress(), _newAddress);

		vm.expectEmit(true, true, false, false);
		emit SetMorpherStakingAddress(morpherState.morpherStakingAddress(), _newAddress);
		morpherState.setMorpherStaking(payable(_newAddress));
		assertEq(morpherState.morpherStakingAddress(), _newAddress);

		vm.expectEmit(true, true, false, false);
		emit SetMorpherTokenAddress(morpherState.morpherTokenAddress(), _newAddress);
		morpherState.setMorpherToken(_newAddress);
		assertEq(morpherState.morpherTokenAddress(), _newAddress);

		vm.expectEmit(true, true, false, false);
		emit SetMorpherTradeEngineAddress(morpherState.morpherTradeEngineAddress(), _newAddress);
		morpherState.setMorpherTradeEngine(_newAddress);
		assertEq(morpherState.morpherTradeEngineAddress(), _newAddress);

		vm.expectEmit(true, true, false, false);
		emit SetMorpherUserBlockingAddress(morpherState.morpherUserBlockingAddress(), _newAddress);
		morpherState.setMorpherUserBlocking(_newAddress);
		assertEq(morpherState.morpherUserBlockingAddress(), _newAddress);

		vm.expectEmit(true, true, false, false);
		emit SetMorpherInterestRateManagerAddress(morpherState.morpherInterestRateManagerAddress(), _newAddress);
		morpherState.setMorpherInterestRateManager(_newAddress);
		assertEq(morpherState.morpherInterestRateManagerAddress(), _newAddress);

		vm.expectEmit(true, true, false, false);
		emit SetMorpherAccessControlAddress(morpherState.morpherAccessControlAddress(), _newAddress);
		morpherState.setMorpherAccessControl(_newAddress);
		assertEq(morpherState.morpherAccessControlAddress(), _newAddress);

		vm.stopPrank();
	}

	function testActivateMarket() public {
		vm.startPrank(_admin);
		bytes32 marketId = keccak256("CRYPTO_DOGE");

		bool active = morpherState.getMarketActive(marketId);
		assertEq(active, false);

		vm.expectEmit(true, true, true, true);
		emit MarketActivated(marketId);
		morpherState.activateMarket(marketId);

		active = morpherState.getMarketActive(marketId);
		assertEq(active, true);

		vm.expectEmit(true, true, true, true);
		emit MarketDeActivated(marketId);
		morpherState.deActivateMarket(marketId);

		active = morpherState.getMarketActive(marketId);
		assertEq(active, false);
	}

	function testMaximumLeverage() public {
		uint256 newLeverage = 50 * 10 ** 8;

		vm.prank(_admin);
		vm.expectEmit(true, true, true, true);
		emit MaximumLeverageChange(newLeverage);
		morpherState.setMaximumLeverage(newLeverage);

		uint256 maxLeverage = morpherState.getMaximumLeverage();
		assertEq(maxLeverage, newLeverage);
	}

	function testBackwardCompatibilityPositionFunctions() public {
		address user = address(0xabc);
		vm.warp(1700000000);
		generatePosition(keccak256("CRYPTO_BTC"), user);

		(
			uint256 longShares,
			uint256 shortShares,
			uint256 meanEntryPrice,
			uint256 meanEntrySpread,
			uint256 meanEntryLeverage,
			uint256 liquidationPrice
		) = morpherState.getPosition(user, keccak256("CRYPTO_BTC"));

		assertEq(longShares, 999000999);
		assertEq(shortShares, 0);
		assertEq(meanEntryPrice, 1000 * 10 ** 8);
		assertEq(meanEntrySpread, 10 ** 8);
		assertEq(meanEntryLeverage, 10 ** 8);
		assertEq(liquidationPrice, 0);

		uint256 lastUpdated = morpherState.getLastUpdated(user, keccak256("CRYPTO_BTC"));
		assertEq(lastUpdated, block.timestamp * 1000);
	}

	function testBackwardCompatibilityTotalToken() public {
		morpherAccessControl.grantRole(keccak256("MINTER_ROLE"), address(this));
		morpherToken.mint(address(0x11), 100 * 10 ** 18);
		morpherAccessControl.revokeRole(keccak256("MINTER_ROLE"), address(this));
		
		uint256 totalTokens = morpherState.totalToken();
		assertEq(totalTokens, 100 * 10 ** 18);
	}
}
