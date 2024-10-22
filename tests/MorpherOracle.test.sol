// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "./BaseSetup.sol";
import "../contracts/MorpherOracle.sol";

// using staking as one of the inheriting contracts
contract MorpherOracleTest is BaseSetup, MorpherOracle {
	function setUp() public override {
		super.setUp();
		morpherAccessControl.grantRole(morpherOracle.ADMINISTRATOR_ROLE(), address(this));
	}

	function testAdminFunctions() public {
		vm.expectEmit(true, true, true, true);
		emit LinkWMatic(address(0x01));
		morpherOracle.setWmaticAddress(address(0x01));
		assertEq(morpherOracle.wMaticAddress(), address(0x01));

		vm.expectEmit(true, true, true, true);
		emit SetGasForCallback(50000);
		morpherOracle.overrideGasForCallback(50000);
		assertEq(morpherOracle.gasForCallback(), 50000);

		vm.expectEmit(true, true, true, true);
		emit CallBackCollectionAddressChange(payable(address(0x02)));
		morpherOracle.setCallbackCollectionAddress(payable(address(0x02)));
		assertEq(morpherOracle.callBackCollectionAddress(), payable(address(0x02)));

		vm.expectEmit(true, true, true, true);
		emit LinkMorpherState(address(0x03));
		morpherOracle.setStateAddress(address(0x03));
	}

	function testGetTradeEngineFromOrderId() public {
		address res = morpherOracle.getTradeEngineFromOrderId(0);
		assertEq(res, address(morpherTradeEngine));
	}

	function testEmitOrderFailed() public {
		bytes32 orderId = keccak256("order");
		address addr = address(0x1234);
		bytes32 marketId = keccak256("CRYPTO_BTC");
		uint256 closeSharesAmount = 0;
		uint256 openMPHTokenAmount = 50 * 10e18;
		bool tradeDirection = true;
		uint256 orderLeverage = 10e8;
		uint256 onlyIfPriceBelow = 2000;
		uint256 onlyIfPriceAbove = 3000;
		uint256 goodFrom = 0;
		uint256 goodUntil = block.timestamp + 10;

		vm.expectEmit(true, true, true, true);
		emit OrderFailed(
			orderId,
			addr,
			marketId,
			closeSharesAmount,
			openMPHTokenAmount,
			tradeDirection,
			orderLeverage,
			onlyIfPriceBelow,
			onlyIfPriceAbove,
			goodFrom,
			goodUntil
		);
		morpherOracle.emitOrderFailed(
			orderId,
			addr,
			marketId,
			closeSharesAmount,
			openMPHTokenAmount,
			tradeDirection,
			orderLeverage,
			onlyIfPriceBelow,
			onlyIfPriceAbove,
			goodFrom,
			goodUntil
		);
	}
}
