// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "./BaseSetup.sol";
import "../contracts/MorpherTradeEngine.sol";

contract MorkpherTradingEngineTest is BaseSetup {
	uint public constant PRECISION = 10 ** 8;
	uint public constant SECOND_RATE_TS = 1644491427;

	event OrderIdRequested(
		bytes32 _orderId,
		address indexed _address,
		bytes32 indexed _marketId,
		uint256 _closeSharesAmount,
		uint256 _openMPHTokenAmount,
		bool _tradeDirection,
		uint256 _orderLeverage
	);

	function setUp() public override {
		super.setUp();
	}

	// POSITION VALUE ------------------------------------------------------------------------------

	function testCalculateMarginInterest() public {
		// 5x position on ETH after 5 days
		uint256 averagePrice = 3000 * PRECISION;
		uint256 averageLeverage = 5 * PRECISION;
		uint256 positionTimeStampInMs = SECOND_RATE_TS * 1000;

		vm.warp(SECOND_RATE_TS + 5 * 24 * 60 * 60);

		uint256 marginInterest = morpherTradeEngine.calculateMarginInterest(
			averagePrice,
			averageLeverage,
			positionTimeStampInMs
		);

		// 21.6
		assertEq(marginInterest, 2160000000);
	}

	function testGetLiquidationPriceForLongPosition() public {
		uint256 averagePrice = 3000 * PRECISION;
		uint256 averageLeverage = 5 * PRECISION;
		uint256 positionTimestampInMs = SECOND_RATE_TS * 1000;
		bool longPosition = true;

		vm.warp(SECOND_RATE_TS + 5 * 24 * 60 * 60);

		uint256 liquidationPrice = morpherTradeEngine.getLiquidationPrice(
			averagePrice,
			averageLeverage,
			longPosition,
			positionTimestampInMs
		);

		// 2404.32
		assertEq(liquidationPrice, 240432000000);
	}

	function testGetLiquidationPriceForShortPosition() public {
		uint256 averagePrice = 3000 * PRECISION;
		uint256 averageLeverage = 5 * PRECISION;
		uint256 positionTimestampInMs = SECOND_RATE_TS * 1000;
		bool longPosition = false;

		vm.warp(SECOND_RATE_TS + 5 * 24 * 60 * 60);

		uint256 liquidationPrice = morpherTradeEngine.getLiquidationPrice(
			averagePrice,
			averageLeverage,
			longPosition,
			positionTimestampInMs
		);

		// 3595.68
		assertEq(liquidationPrice, 359568000000);
	}

	function testLongShareValueNoLeverage() public {
		uint256 positionTimestampInMs = SECOND_RATE_TS * 1000;
		uint256 marketPrice = 3000 * PRECISION;
		uint256 marketSpread = 3 * PRECISION;
		uint256 orderLeverage = PRECISION;
		bool sell = false;

		vm.warp(SECOND_RATE_TS);

		uint256 shareValue = morpherTradeEngine.longShareValue(
			marketPrice,
			orderLeverage,
			positionTimestampInMs,
			marketPrice,
			marketSpread,
			orderLeverage,
			sell
		);

		assertEq(shareValue, marketPrice + marketSpread);
	}

	function testLongShareValueWithLeverage() public {
		uint256 positionTimestampInMs = SECOND_RATE_TS * 1000;
		uint256 marketPrice = 3000 * PRECISION;
		uint256 marketSpread = 3 * PRECISION;
		uint256 orderLeverage = 5 * PRECISION;
		bool sell = false;

		vm.warp(SECOND_RATE_TS);

		uint256 shareValue = morpherTradeEngine.longShareValue(
			marketPrice,
			orderLeverage,
			positionTimestampInMs,
			marketPrice,
			marketSpread,
			orderLeverage,
			sell
		);

		assertEq(shareValue, marketPrice + marketSpread * 5);
	}

	function testLongShareValueSelling() public {
		uint256 positionTimestampInMs = SECOND_RATE_TS * 1000;
		uint256 averagePrice = 3000 * PRECISION;
		uint256 averageLeverage = 5 * PRECISION;
		uint256 marketPrice = 2600 * PRECISION;
		uint256 marketSpread = 3 * PRECISION;
		bool sell = true;

		vm.warp(SECOND_RATE_TS + 5 * 24 * 60 * 60);

		uint256 shareValue = morpherTradeEngine.longShareValue(
			averagePrice,
			averageLeverage,
			positionTimestampInMs,
			marketPrice,
			marketSpread,
			averageLeverage,
			sell
		);

		assertEq(shareValue, 96340000000);
	}

	function testLongShareValueAlmostLiquidated() public {
		uint256 positionTimestampInMs = SECOND_RATE_TS * 1000;
		uint256 averagePrice = 3000 * PRECISION;
		uint256 averageLeverage = 5 * PRECISION;
		uint256 marketPrice = 2405 * PRECISION;
		uint256 marketSpread = 3 * PRECISION;
		bool sell = true;

		vm.warp(SECOND_RATE_TS + 5 * 24 * 60 * 60);

		uint256 shareValue = morpherTradeEngine.longShareValue(
			averagePrice,
			averageLeverage,
			positionTimestampInMs,
			marketPrice,
			marketSpread,
			averageLeverage,
			sell
		);

		// not liquidated but margin interest is > than remaining share value
		assertEq(shareValue, 0);
	}

	function testLongShareValueLiquidated() public {
		uint256 positionTimestampInMs = SECOND_RATE_TS * 1000;
		uint256 averagePrice = 3000 * PRECISION;
		uint256 averageLeverage = 5 * PRECISION;
		uint256 marketPrice = 2404 * PRECISION;
		uint256 marketSpread = 3 * PRECISION;
		bool sell = true;

		vm.warp(SECOND_RATE_TS + 5 * 24 * 60 * 60);

		uint256 shareValue = morpherTradeEngine.longShareValue(
			averagePrice,
			averageLeverage,
			positionTimestampInMs,
			marketPrice,
			marketSpread,
			averageLeverage,
			sell
		);

		assertEq(shareValue, 0);
	}

	function testShortShareValueNoLeverage() public {
		uint256 positionTimestampInMs = SECOND_RATE_TS * 1000;
		uint256 marketPrice = 3000 * PRECISION;
		uint256 marketSpread = 3 * PRECISION;
		uint256 orderLeverage = PRECISION;
		bool sell = false;

		vm.warp(SECOND_RATE_TS);

		uint256 shareValue = morpherTradeEngine.shortShareValue(
			marketPrice,
			orderLeverage,
			positionTimestampInMs,
			marketPrice,
			marketSpread,
			orderLeverage,
			sell
		);

		assertEq(shareValue, marketPrice + marketSpread);
	}

	function testShortShareValueWithLeverage() public {
		uint256 positionTimestampInMs = SECOND_RATE_TS * 1000;
		uint256 marketPrice = 3000 * PRECISION;
		uint256 marketSpread = 3 * PRECISION;
		uint256 orderLeverage = 5 * PRECISION;
		bool sell = false;

		vm.warp(SECOND_RATE_TS);

		uint256 shareValue = morpherTradeEngine.shortShareValue(
			marketPrice,
			orderLeverage,
			positionTimestampInMs,
			marketPrice,
			marketSpread,
			orderLeverage,
			sell
		);

		assertEq(shareValue, marketPrice + marketSpread * 5);
	}

	function testShortShareValueSelling() public {
		uint256 positionTimestampInMs = SECOND_RATE_TS * 1000;
		uint256 averagePrice = 3000 * PRECISION;
		uint256 averageLeverage = 5 * PRECISION;
		uint256 marketPrice = 3400 * PRECISION;
		uint256 marketSpread = 3 * PRECISION;
		bool sell = true;

		vm.warp(SECOND_RATE_TS + 5 * 24 * 60 * 60);

		uint256 shareValue = morpherTradeEngine.shortShareValue(
			averagePrice,
			averageLeverage,
			positionTimestampInMs,
			marketPrice,
			marketSpread,
			averageLeverage,
			sell
		);

		assertEq(shareValue, 96340000000);
	}

	function testShortShareValueAlmostLiquidated() public {
		uint256 positionTimestampInMs = SECOND_RATE_TS * 1000;
		uint256 averagePrice = 3000 * PRECISION;
		uint256 averageLeverage = 5 * PRECISION;
		uint256 marketPrice = 3595 * PRECISION;
		uint256 marketSpread = 3 * PRECISION;
		bool sell = true;

		vm.warp(SECOND_RATE_TS + 5 * 24 * 60 * 60);

		uint256 shareValue = morpherTradeEngine.shortShareValue(
			averagePrice,
			averageLeverage,
			positionTimestampInMs,
			marketPrice,
			marketSpread,
			averageLeverage,
			sell
		);

		// not liquidated but margin interest is > than remaining share value
		assertEq(shareValue, 0);
	}

	function testShortShareValueLiquidated() public {
		uint256 positionTimestampInMs = SECOND_RATE_TS * 1000;
		uint256 averagePrice = 3000 * PRECISION;
		uint256 averageLeverage = 5 * PRECISION;
		uint256 marketPrice = 3596 * PRECISION;
		uint256 marketSpread = 3 * PRECISION;
		bool sell = true;

		vm.warp(SECOND_RATE_TS + 5 * 24 * 60 * 60);

		uint256 shareValue = morpherTradeEngine.shortShareValue(
			averagePrice,
			averageLeverage,
			positionTimestampInMs,
			marketPrice,
			marketSpread,
			averageLeverage,
			sell
		);

		assertEq(shareValue, 0);
	}

	// ORDERS --------------------------------------------------------------------------------------

	function testRequestOrderId() public {
		address user = address(0xff01);

        bytes32 expectedOrderId = keccak256(
			abi.encodePacked(
				user,
				block.number,
				keccak256("CRYPTO_BTC"),
				uint(0),
				uint(100 * 10 ** 18),
				true,
				2 * PRECISION,
				uint(1)
			)
		);

		vm.prank(address(morpherOracle));
        vm.expectEmit(true, true, true, true);
        emit OrderIdRequested(expectedOrderId, user, keccak256("CRYPTO_BTC"), 0, 100 * 10 ** 18, true, 2 * PRECISION);
		bytes32 orderId = morpherTradeEngine.requestOrderId(
			user,
			keccak256("CRYPTO_BTC"),
			0,
			100 * 10 ** 18,
			true,
            2 * PRECISION
		);
        assertEq(orderId, expectedOrderId);

		(
			address userId,
			bytes32 storedMarketId,
			uint256 storedCloseSharesAmount,
			uint256 storedOpenMPHTokenAmount,
			bool storedTradeDirection,
            uint256 storedLiquidationTimestamp,
            uint256 storedMarketPrice,
            uint256 storedMarketSpread,
			uint256 storedOrderLeverage,
            uint256 storedTimestamp,
            uint256 storedEscrowAmount,
		) = morpherTradeEngine.orders(orderId);

		assertEq(userId, user);
		assertEq(storedMarketId, keccak256("CRYPTO_BTC"));
		assertEq(storedCloseSharesAmount, 0);
		assertEq(storedOpenMPHTokenAmount, 100 * 10 ** 18);
		assertEq(storedTradeDirection, true);
        assertEq(storedLiquidationTimestamp, 0);
        assertEq(storedMarketPrice, 0);
        assertEq(storedMarketSpread, 0);
		assertEq(storedOrderLeverage, 2 * PRECISION);
        assertEq(storedTimestamp, 0);
        assertEq(storedEscrowAmount, 0);
	}
}
