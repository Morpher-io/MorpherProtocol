// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

import "./BaseSetup.sol";
import "../contracts/MorpherTradeEngine.sol";

contract MorkpherTradingEngineTest is BaseSetup {
	uint public constant PRECISION = 10 ** 8;
	uint public constant SECOND_RATE_TS = 1644491427;

	bytes32 public constant DOMAIN_TYPE_HASH =
		keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
	bytes32 public constant POSITION_TYPE_HASH =
		keccak256(
			"Position(uint256 lastUpdated,uint256 longShares,uint256 shortShares,uint256 meanEntryPrice,uint256 meanEntrySpread,uint256 meanEntryLeverage,uint256 liquidationPrice,bytes32 positionHash)"
		);

	event Transfer(address indexed from, address indexed to, uint256 value);
	event LinkState(address stateAddress);
	event LockedPriceForClosingPositions(bytes32 _marketId, uint256 _price);
	event EscrowPaid(bytes32 orderId, address user, uint escrowAmount);
	event EscrowReturned(bytes32 orderId, address user, uint escrowAmount);
	event OrderIdRequested(
		bytes32 _orderId,
		address indexed _address,
		bytes32 indexed _marketId,
		uint256 _closeSharesAmount,
		uint256 _openMPHTokenAmount,
		bool _tradeDirection,
		uint256 _orderLeverage
	);
	event OrderCancelled(bytes32 indexed _orderId, address indexed _address);
	event SetPosition(
		bytes32 indexed positionHash,
		address indexed sender,
		bytes32 indexed marketId,
		uint256 timeStamp,
		uint256 longShares,
		uint256 shortShares,
		uint256 meanEntryPrice,
		uint256 meanEntrySpread,
		uint256 meanEntryLeverage,
		uint256 liquidationPrice
	);

	function setUp() public override {
		super.setUp();
		morpherAccessControl.grantRole(morpherToken.ADMINISTRATOR_ROLE(), address(this));
		morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(this));
	}

	function testAdminFunctions() public {
		bytes32 marketId = keccak256("CRYPTO_DOGE");
		vm.expectEmit(true, true, true, true);
		emit LockedPriceForClosingPositions(marketId, 5 * 10 ** 8);
		morpherTradeEngine.setDeactivatedMarketPrice(marketId, 5 * 10 ** 8);
		assertEq(morpherTradeEngine.getDeactivatedMarketPrice(marketId), 5 * 10 ** 8);

		vm.expectEmit(true, true, true, true);
		emit LinkState(address(0x01));
		morpherTradeEngine.setMorpherStateAddress(address(0x01));
		assertEq(address(morpherTradeEngine.morpherState()), address(0x01));
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

	function testOrderFieldsCleared() public {
		address user = address(0xff01);
		morpherToken.mint(user, 100 * 10 ** 18);

		vm.warp(SECOND_RATE_TS);

		vm.prank(address(morpherOracle));
		bytes32 orderId = morpherTradeEngine.requestOrderId(
			user,
			keccak256("CRYPTO_BTC"),
			0,
			100 * 10 ** 18,
			true,
			2 * PRECISION
		);

		vm.warp(SECOND_RATE_TS + 2);

		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(orderId, 50000 * 10 ** 8, 5 * 10 ** 8, 0, SECOND_RATE_TS * 1000 + 1000);

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

		assertEq(userId, address(0x00));
		assertEq(storedMarketId, bytes32(0x00));
		assertEq(storedCloseSharesAmount, 0);
		assertEq(storedOpenMPHTokenAmount, 0);
		assertEq(storedTradeDirection, false);
		assertEq(storedLiquidationTimestamp, 0);
		assertEq(storedMarketPrice, 0);
		assertEq(storedMarketSpread, 0);
		assertEq(storedOrderLeverage, 0);
		assertEq(storedTimestamp, 0);
		assertEq(storedEscrowAmount, 0);
	}

	function testProcessSimpleBuyOrder() public {
		uint256 marketPrice = 50000 * PRECISION;
		uint256 marketSpread = 10 * PRECISION;
		uint256 orderLeverage = 5 * PRECISION;
		address user = address(0xff01);
		morpherToken.mint(user, 1001 * 10 ** 18);

		vm.warp(SECOND_RATE_TS);

		vm.prank(address(morpherOracle));
		bytes32 orderId = morpherTradeEngine.requestOrderId(
			user,
			keccak256("CRYPTO_BTC"),
			0,
			1001 * 10 ** 18,
			true,
			orderLeverage
		);

		vm.warp(SECOND_RATE_TS + 2);

		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(orderId, marketPrice, marketSpread, 0, SECOND_RATE_TS * 1000 + 1000);

		(
			uint256 lastUpdated,
			uint256 longShares,
			uint256 shortShares,
			uint256 meanEntryPrice,
			uint256 meanEntrySpread,
			uint256 meanEntryLeverage,
			uint256 liquidationPrice,
			bytes32 positionHash
		) = morpherTradeEngine.portfolio(user, keccak256("CRYPTO_BTC"));

		bytes32 expectedPositionHash = keccak256(
			abi.encodePacked(
				user,
				keccak256("CRYPTO_BTC"),
				uint(SECOND_RATE_TS * 1000 + 1000),
				uint(2 * 10 ** 8),
				uint(0),
				uint(50000 * PRECISION),
				uint(10 * PRECISION),
				uint(5 * PRECISION),
				uint(4001200000000)
			)
		);
		assertEq(lastUpdated, SECOND_RATE_TS * 1000 + 1000);
		assertEq(longShares, 2 * 10 ** 8);
		assertEq(shortShares, 0);
		assertEq(meanEntryPrice, uint(50000 * PRECISION));
		assertEq(meanEntrySpread, uint(10 * PRECISION));
		assertEq(meanEntryLeverage, uint(5 * PRECISION));
		assertEq(liquidationPrice, 4001200000000);
		assertEq(positionHash, expectedPositionHash);
	}

	function testProcessSimpleSellOrder() public {
		uint256 marketPrice = 50000 * PRECISION;
		uint256 marketSpread = 10 * PRECISION;
		uint256 orderLeverage = 5 * PRECISION;
		address user = address(0xff01);
		morpherToken.mint(user, 1001 * 10 ** 18);

		vm.warp(SECOND_RATE_TS);

		vm.prank(address(morpherOracle));
		bytes32 orderId = morpherTradeEngine.requestOrderId(
			user,
			keccak256("CRYPTO_BTC"),
			0,
			1001 * 10 ** 18,
			false,
			orderLeverage
		);

		vm.warp(SECOND_RATE_TS + 2);

		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(orderId, marketPrice, marketSpread, 0, SECOND_RATE_TS * 1000 + 1000);

		(
			uint256 lastUpdated,
			uint256 longShares,
			uint256 shortShares,
			uint256 meanEntryPrice,
			uint256 meanEntrySpread,
			uint256 meanEntryLeverage,
			uint256 liquidationPrice,
			bytes32 positionHash
		) = morpherTradeEngine.portfolio(user, keccak256("CRYPTO_BTC"));

		bytes32 expectedPositionHash = keccak256(
			abi.encodePacked(
				user,
				keccak256("CRYPTO_BTC"),
				uint(SECOND_RATE_TS * 1000 + 1000),
				uint(0),
				uint(2 * 10 ** 8),
				uint(50000 * PRECISION),
				uint(10 * PRECISION),
				uint(5 * PRECISION),
				uint(5998800000000)
			)
		);
		assertEq(lastUpdated, SECOND_RATE_TS * 1000 + 1000);
		assertEq(longShares, 0);
		assertEq(shortShares, 2 * 10 ** 8);
		assertEq(meanEntryPrice, uint(50000 * PRECISION));
		assertEq(meanEntrySpread, uint(10 * PRECISION));
		assertEq(meanEntryLeverage, uint(5 * PRECISION));
		assertEq(liquidationPrice, 5998800000000);
		assertEq(positionHash, expectedPositionHash);
	}

	function testOpenAndCloseBuyOrder() public {
		uint256 marketPrice = 50000 * PRECISION;
		uint256 marketSpread = 10 * PRECISION;
		uint256 orderLeverage = 5 * PRECISION;
		address user = address(0xff01);
		morpherToken.mint(user, 1001 * 10 ** 18);

		vm.warp(SECOND_RATE_TS);

		vm.prank(address(morpherOracle));
		bytes32 orderId = morpherTradeEngine.requestOrderId(
			user,
			keccak256("CRYPTO_BTC"),
			0,
			1001 * 10 ** 18,
			true,
			orderLeverage
		);

		vm.warp(SECOND_RATE_TS + 2);

		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(orderId, marketPrice, marketSpread, 0, SECOND_RATE_TS * 1000 + 1000);

		vm.warp(block.timestamp + 10 * 24 * 60 * 60);

		vm.prank(address(morpherOracle));
		orderId = morpherTradeEngine.requestOrderId(user, keccak256("CRYPTO_BTC"), 2 * 10 ** 8, 0, false, PRECISION);

		vm.warp(block.timestamp + 2);

		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(
			orderId,
			marketPrice + 50 * PRECISION,
			marketSpread,
			0,
			block.timestamp * 1000 - 1000
		);

		(
			uint256 lastUpdated,
			uint256 longShares,
			uint256 shortShares,
			uint256 meanEntryPrice,
			uint256 meanEntrySpread,
			uint256 meanEntryLeverage,
			uint256 liquidationPrice,

		) = morpherTradeEngine.portfolio(user, keccak256("CRYPTO_BTC"));

		assertEq(lastUpdated, block.timestamp * 1000 - 1000);
		assertEq(longShares, 0);
		assertEq(shortShares, 0);
		assertEq(meanEntryPrice, 0);
		assertEq(meanEntrySpread, 0);
		assertEq(meanEntryLeverage, PRECISION);
		assertEq(liquidationPrice, 0);

		uint userBalance = morpherToken.balanceOf(user);
		uint256 marginInterest = morpherTradeEngine.calculateMarginInterest(
			marketPrice,
			orderLeverage,
			SECOND_RATE_TS * 1000 + 1000
		);
		uint expectedShareValue = (50050 * PRECISION) *
			5 -
			50000 *
			PRECISION *
			(5 - 1) -
			10 *
			5 *
			PRECISION -
			marginInterest;
		assertEq(userBalance, expectedShareValue * 2 * 10 ** 8);
	}

	function testOpenAndCloseSellOrder() public {
		uint256 marketPrice = 50000 * PRECISION;
		uint256 marketSpread = 10 * PRECISION;
		uint256 orderLeverage = 5 * PRECISION;
		address user = address(0xff01);
		morpherToken.mint(user, 1001 * 10 ** 18);

		vm.warp(SECOND_RATE_TS);

		vm.prank(address(morpherOracle));
		bytes32 orderId = morpherTradeEngine.requestOrderId(
			user,
			keccak256("CRYPTO_BTC"),
			0,
			1001 * 10 ** 18,
			false,
			orderLeverage
		);

		vm.warp(SECOND_RATE_TS + 2);

		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(orderId, marketPrice, marketSpread, 0, SECOND_RATE_TS * 1000 + 1000);

		vm.warp(block.timestamp + 10 * 24 * 60 * 60);

		vm.prank(address(morpherOracle));
		orderId = morpherTradeEngine.requestOrderId(user, keccak256("CRYPTO_BTC"), 2 * 10 ** 8, 0, true, PRECISION);

		vm.warp(block.timestamp + 2);

		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(
			orderId,
			marketPrice + 50 * PRECISION,
			marketSpread,
			0,
			block.timestamp * 1000 - 1000
		);

		(
			uint256 lastUpdated,
			uint256 longShares,
			uint256 shortShares,
			uint256 meanEntryPrice,
			uint256 meanEntrySpread,
			uint256 meanEntryLeverage,
			uint256 liquidationPrice,

		) = morpherTradeEngine.portfolio(user, keccak256("CRYPTO_BTC"));

		assertEq(lastUpdated, block.timestamp * 1000 - 1000);
		assertEq(longShares, 0);
		assertEq(shortShares, 0);
		assertEq(meanEntryPrice, 0);
		assertEq(meanEntrySpread, 0);
		assertEq(meanEntryLeverage, PRECISION);
		assertEq(liquidationPrice, 0);

		uint userBalance = morpherToken.balanceOf(user);
		uint256 marginInterest = morpherTradeEngine.calculateMarginInterest(
			marketPrice,
			orderLeverage,
			SECOND_RATE_TS * 1000 + 1000
		);
		uint expectedShareValue = 50000 *
			PRECISION *
			(5 + 1) -
			50050 *
			PRECISION *
			5 -
			10 *
			5 *
			PRECISION -
			marginInterest;
		assertEq(userBalance, expectedShareValue * 2 * 10 ** 8);
	}

	function testOpenAndHalfCloseBuyOrder() public {
		uint256 marketPrice = 50000 * PRECISION;
		uint256 marketSpread = 10 * PRECISION;
		uint256 orderLeverage = 5 * PRECISION;
		address user = address(0xff01);
		morpherToken.mint(user, 1001 * 10 ** 18);

		vm.warp(SECOND_RATE_TS);

		vm.prank(address(morpherOracle));
		bytes32 orderId = morpherTradeEngine.requestOrderId(
			user,
			keccak256("CRYPTO_BTC"),
			0,
			1001 * 10 ** 18,
			true,
			orderLeverage
		);

		vm.warp(SECOND_RATE_TS + 2);

		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(orderId, marketPrice, marketSpread, 0, SECOND_RATE_TS * 1000 + 1000);

		vm.warp(block.timestamp + 10 * 24 * 60 * 60);

		vm.prank(address(morpherOracle));
		orderId = morpherTradeEngine.requestOrderId(user, keccak256("CRYPTO_BTC"), 10 ** 8, 0, false, PRECISION);

		vm.warp(block.timestamp + 2);

		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(
			orderId,
			marketPrice + 50 * PRECISION,
			marketSpread,
			0,
			block.timestamp * 1000 - 1000
		);

		(
			uint256 lastUpdated,
			uint256 longShares,
			uint256 shortShares,
			uint256 meanEntryPrice,
			uint256 meanEntrySpread,
			uint256 meanEntryLeverage,
			uint256 liquidationPrice,

		) = morpherTradeEngine.portfolio(user, keccak256("CRYPTO_BTC"));

		// timestamp doesn't change on partial close
		assertEq(lastUpdated, SECOND_RATE_TS * 1000 + 1000);
		assertEq(longShares, 10 ** 8);
		assertEq(shortShares, 0);
		assertEq(meanEntryPrice, marketPrice);
		assertEq(meanEntrySpread, marketSpread);
		assertEq(meanEntryLeverage, orderLeverage);
		// liquidation price is updated because block.timestamp is higher
		assertEq(liquidationPrice, 4001200000000 + 10 * 1200000000);

		uint userBalance = morpherToken.balanceOf(user);
		uint256 marginInterest = morpherTradeEngine.calculateMarginInterest(
			marketPrice,
			orderLeverage,
			SECOND_RATE_TS * 1000 + 1000
		);
		uint expectedShareValue = (50050 * PRECISION) *
			5 -
			50000 *
			PRECISION *
			(5 - 1) -
			10 *
			5 *
			PRECISION -
			marginInterest;
		assertEq(userBalance, expectedShareValue * 10 ** 8);
	}

	function testOpenAndHalfCloseSellOrder() public {
		uint256 marketPrice = 50000 * PRECISION;
		uint256 marketSpread = 10 * PRECISION;
		uint256 orderLeverage = 5 * PRECISION;
		address user = address(0xff01);
		morpherToken.mint(user, 1001 * 10 ** 18);

		vm.warp(SECOND_RATE_TS);

		vm.prank(address(morpherOracle));
		bytes32 orderId = morpherTradeEngine.requestOrderId(
			user,
			keccak256("CRYPTO_BTC"),
			0,
			1001 * 10 ** 18,
			false,
			orderLeverage
		);

		vm.warp(SECOND_RATE_TS + 2);

		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(orderId, marketPrice, marketSpread, 0, SECOND_RATE_TS * 1000 + 1000);

		vm.warp(block.timestamp + 10 * 24 * 60 * 60);

		vm.prank(address(morpherOracle));
		orderId = morpherTradeEngine.requestOrderId(user, keccak256("CRYPTO_BTC"), 10 ** 8, 0, true, PRECISION);

		vm.warp(block.timestamp + 2);

		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(
			orderId,
			marketPrice + 50 * PRECISION,
			marketSpread,
			0,
			block.timestamp * 1000 - 1000
		);

		(
			uint256 lastUpdated,
			uint256 longShares,
			uint256 shortShares,
			uint256 meanEntryPrice,
			uint256 meanEntrySpread,
			uint256 meanEntryLeverage,
			uint256 liquidationPrice,

		) = morpherTradeEngine.portfolio(user, keccak256("CRYPTO_BTC"));

		assertEq(lastUpdated, SECOND_RATE_TS * 1000 + 1000);
		assertEq(longShares, 0);
		assertEq(shortShares, 10 ** 8);
		assertEq(meanEntryPrice, marketPrice);
		assertEq(meanEntrySpread, marketSpread);
		assertEq(meanEntryLeverage, orderLeverage);
		assertEq(liquidationPrice, 5998800000000 - 10 * 1200000000);

		uint userBalance = morpherToken.balanceOf(user);
		uint256 marginInterest = morpherTradeEngine.calculateMarginInterest(
			marketPrice,
			orderLeverage,
			SECOND_RATE_TS * 1000 + 1000
		);
		uint expectedShareValue = 50000 *
			PRECISION *
			(5 + 1) -
			50050 *
			PRECISION *
			5 -
			10 *
			5 *
			PRECISION -
			marginInterest;
		assertEq(userBalance, expectedShareValue * 10 ** 8);
	}

	function testOpenAndDoubleDownBuyOrder() public {
		uint256 marketPrice = 50000 * PRECISION;
		uint256 marketSpread = 10 * PRECISION;
		uint256 orderLeverage = 5 * PRECISION;
		uint256 marketPrice2 = 51000 * PRECISION;
		uint256 marketSpread2 = 12 * PRECISION;
		uint256 orderLeverage2 = 9 * PRECISION;
		address user = address(0xff01);
		morpherToken.mint(user, 1001 * 10 ** 18 + 153324 * 10 ** 16);

		vm.warp(SECOND_RATE_TS);

		vm.prank(address(morpherOracle));
		bytes32 orderId = morpherTradeEngine.requestOrderId(
			user,
			keccak256("CRYPTO_BTC"),
			0,
			1001 * 10 ** 18,
			true,
			orderLeverage
		);

		vm.warp(SECOND_RATE_TS + 2);

		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(orderId, marketPrice, marketSpread, 0, SECOND_RATE_TS * 1000 + 1000);

		vm.warp(block.timestamp + 10 * 24 * 60 * 60);

		vm.prank(address(morpherOracle));
		orderId = morpherTradeEngine.requestOrderId(
			user,
			keccak256("CRYPTO_BTC"),
			0,
			153324 * 10 ** 16,
			true,
			orderLeverage2
		);

		vm.warp(block.timestamp + 2);

		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(orderId, marketPrice2, marketSpread2, 0, block.timestamp * 1000 - 1000);

		(
			uint256 lastUpdated,
			uint256 longShares,
			uint256 shortShares,
			uint256 meanEntryPrice,
			uint256 meanEntrySpread,
			uint256 meanEntryLeverage,
			uint256 liquidationPrice,

		) = morpherTradeEngine.portfolio(user, keccak256("CRYPTO_BTC"));

		assertEq(lastUpdated, block.timestamp * 1000 - 1000);
		assertEq(longShares, 3 * 10 ** 8 + 215686276);
		assertEq(shortShares, 0);
		assertEq(meanEntryPrice, 51000 * PRECISION);
		assertEq(meanEntrySpread, (PRECISION * (10 * 215686276 + 12 * 3 * PRECISION)) / longShares);
		assertEq(meanEntryLeverage, (PRECISION * 5 * 215686276 + PRECISION * 9 * 3 * 10 ** 8) / longShares);
		// function is already tested
		uint expectedLiquidationPrice = morpherTradeEngine.getLiquidationPrice(
			meanEntryPrice,
			meanEntryLeverage,
			true,
			lastUpdated
		);
		assertEq(liquidationPrice, expectedLiquidationPrice);
		uint userBalance = morpherToken.balanceOf(user);
		assertEq(userBalance, 0);
	}

	function testOpenAndDoubleDownSellOrder() public {
		uint256 marketPrice = 50000 * PRECISION;
		uint256 marketSpread = 10 * PRECISION;
		uint256 orderLeverage = 5 * PRECISION;
		uint256 marketPrice2 = 51000 * PRECISION;
		uint256 marketSpread2 = 12 * PRECISION;
		uint256 orderLeverage2 = 9 * PRECISION;
		address user = address(0xff01);
		morpherToken.mint(user, 1001 * 10 ** 18 + 153324 * 10 ** 16);

		vm.warp(SECOND_RATE_TS);

		vm.prank(address(morpherOracle));
		bytes32 orderId = morpherTradeEngine.requestOrderId(
			user,
			keccak256("CRYPTO_BTC"),
			0,
			1001 * 10 ** 18,
			false,
			orderLeverage
		);

		vm.warp(SECOND_RATE_TS + 2);

		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(orderId, marketPrice, marketSpread, 0, SECOND_RATE_TS * 1000 + 1000);

		vm.warp(block.timestamp + 10 * 24 * 60 * 60);

		vm.prank(address(morpherOracle));
		orderId = morpherTradeEngine.requestOrderId(
			user,
			keccak256("CRYPTO_BTC"),
			0,
			153324 * 10 ** 16,
			false,
			orderLeverage2
		);

		vm.warp(block.timestamp + 2);

		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(orderId, marketPrice2, marketSpread2, 0, block.timestamp * 1000 - 1000);

		(
			uint256 lastUpdated,
			uint256 longShares,
			uint256 shortShares,
			uint256 meanEntryPrice,
			uint256 meanEntrySpread,
			uint256 meanEntryLeverage,
			uint256 liquidationPrice,

		) = morpherTradeEngine.portfolio(user, keccak256("CRYPTO_BTC"));

		assertEq(lastUpdated, block.timestamp * 1000 - 1000);
		assertEq(longShares, 0);
		assertEq(shortShares, 3 * 10 ** 8 + 176470588);
		assertEq(meanEntryPrice, 51000 * PRECISION);
		assertEq(meanEntrySpread, (PRECISION * (10 * 176470588 + 12 * 3 * PRECISION)) / shortShares);
		assertEq(meanEntryLeverage, (PRECISION * 5 * 176470588 + PRECISION * 9 * 3 * 10 ** 8) / shortShares);
		// function is already tested
		uint expectedLiquidationPrice = morpherTradeEngine.getLiquidationPrice(
			meanEntryPrice,
			meanEntryLeverage,
			false,
			lastUpdated
		);
		assertEq(liquidationPrice, expectedLiquidationPrice);
		uint userBalance = morpherToken.balanceOf(user);
		assertEq(userBalance, 0);
	}

	function testOpenAndHalfCloseAndDoubleDownBuyOrder() public {
		address user = address(0xff01);
		morpherToken.mint(user, 1001 * 10 ** 18 + 153324 * 10 ** 16);

		vm.warp(SECOND_RATE_TS);

		vm.prank(address(morpherOracle));
		bytes32 orderId = morpherTradeEngine.requestOrderId(
			user,
			keccak256("CRYPTO_BTC"),
			0,
			1001 * 10 ** 18,
			true,
			5 * 10 ** 8
		);

		vm.warp(SECOND_RATE_TS + 2);

		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(orderId, 50000 * 10 ** 8, 10 * 10 ** 8, 0, SECOND_RATE_TS * 1000 + 1000);

		vm.warp(block.timestamp + 10 * 24 * 60 * 60);

		vm.prank(address(morpherOracle));
		orderId = morpherTradeEngine.requestOrderId(user, keccak256("CRYPTO_BTC"), 10 ** 8, 0, false, PRECISION);

		vm.warp(block.timestamp + 2);

		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(orderId, 50050 * 10 ** 8, 10 * 10 ** 8, 0, block.timestamp * 1000 - 1000);

		uint256 marginInterest = morpherTradeEngine.calculateMarginInterest(
			50000 * 10 ** 8,
			5 * 10 ** 8,
			SECOND_RATE_TS * 1000 + 1000
		);
		uint expectedShareValue = (50050 * PRECISION) *
			5 -
			50000 *
			PRECISION *
			(5 - 1) -
			10 *
			5 *
			PRECISION -
			marginInterest;

		vm.warp(block.timestamp + 10 * 24 * 60 * 60);

		vm.prank(address(morpherOracle));
		orderId = morpherTradeEngine.requestOrderId(
			user,
			keccak256("CRYPTO_BTC"),
			0,
			153324 * 10 ** 16,
			true,
			9 * 10 ** 8
		);

		vm.warp(block.timestamp + 2);

		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(orderId, 51000 * 10 ** 8, 12 * 10 ** 8, 0, block.timestamp * 1000 - 1000);

		(
			uint256 lastUpdated,
			uint256 longShares,
			uint256 shortShares,
			uint256 meanEntryPrice,
			uint256 meanEntrySpread,
			uint256 meanEntryLeverage,
			uint256 liquidationPrice,

		) = morpherTradeEngine.portfolio(user, keccak256("CRYPTO_BTC"));

		assertEq(lastUpdated, block.timestamp * 1000 - 1000);
		assertEq(longShares, 3 * 10 ** 8 + 107843138);
		assertEq(shortShares, 0);
		assertEq(meanEntryPrice, 51000 * PRECISION);
		assertEq(meanEntrySpread, (PRECISION * (10 * 107843138 + 12 * 3 * PRECISION)) / longShares);
		assertEq(meanEntryLeverage, (PRECISION * 5 * 107843138 + PRECISION * 9 * 3 * 10 ** 8) / longShares);
		// function is already tested
		uint expectedLiquidationPrice = morpherTradeEngine.getLiquidationPrice(
			meanEntryPrice,
			meanEntryLeverage,
			true,
			lastUpdated
		);
		assertEq(liquidationPrice, expectedLiquidationPrice);
		uint userBalance = morpherToken.balanceOf(user);
		assertEq(userBalance, expectedShareValue * 10 ** 8);
	}

	function testOpenAndHalfCloseAndDoubleDownSellOrder() public {
		address user = address(0xff01);
		morpherToken.mint(user, 1001 * 10 ** 18 + 153324 * 10 ** 16);

		vm.warp(SECOND_RATE_TS);

		vm.prank(address(morpherOracle));
		bytes32 orderId = morpherTradeEngine.requestOrderId(
			user,
			keccak256("CRYPTO_BTC"),
			0,
			1001 * 10 ** 18,
			false,
			5 * 10 ** 8
		);

		vm.warp(SECOND_RATE_TS + 2);

		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(orderId, 50000 * 10 ** 8, 10 * 10 ** 8, 0, SECOND_RATE_TS * 1000 + 1000);

		vm.warp(block.timestamp + 10 * 24 * 60 * 60);

		vm.prank(address(morpherOracle));
		orderId = morpherTradeEngine.requestOrderId(user, keccak256("CRYPTO_BTC"), 10 ** 8, 0, true, PRECISION);

		vm.warp(block.timestamp + 2);

		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(orderId, 50050 * 10 ** 8, 10 * 10 ** 8, 0, block.timestamp * 1000 - 1000);

		uint256 marginInterest = morpherTradeEngine.calculateMarginInterest(
			50000 * 10 ** 8,
			5 * 10 ** 8,
			SECOND_RATE_TS * 1000 + 1000
		);
		uint expectedShareValue = 50000 *
			PRECISION *
			(5 + 1) -
			50050 *
			PRECISION *
			5 -
			10 *
			5 *
			PRECISION -
			marginInterest;

		vm.warp(block.timestamp + 10 * 24 * 60 * 60);

		vm.prank(address(morpherOracle));
		orderId = morpherTradeEngine.requestOrderId(
			user,
			keccak256("CRYPTO_BTC"),
			0,
			153324 * 10 ** 16,
			false,
			9 * 10 ** 8
		);

		vm.warp(block.timestamp + 2);

		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(orderId, 51000 * 10 ** 8, 12 * 10 ** 8, 0, block.timestamp * 1000 - 1000);

		(
			uint256 lastUpdated,
			uint256 longShares,
			uint256 shortShares,
			uint256 meanEntryPrice,
			uint256 meanEntrySpread,
			uint256 meanEntryLeverage,
			uint256 liquidationPrice,

		) = morpherTradeEngine.portfolio(user, keccak256("CRYPTO_BTC"));

		assertEq(lastUpdated, block.timestamp * 1000 - 1000);
		assertEq(longShares, 0);
		assertEq(shortShares, 3 * 10 ** 8 + 88235294);
		assertEq(meanEntryPrice, 51000 * PRECISION);
		assertEq(meanEntrySpread, (PRECISION * (10 * 88235294 + 12 * 3 * PRECISION)) / shortShares);
		assertEq(meanEntryLeverage, (PRECISION * 5 * 88235294 + PRECISION * 9 * 3 * 10 ** 8) / shortShares);
		// function is already tested
		uint expectedLiquidationPrice = morpherTradeEngine.getLiquidationPrice(
			meanEntryPrice,
			meanEntryLeverage,
			false,
			lastUpdated
		);
		assertEq(liquidationPrice, expectedLiquidationPrice);
		uint userBalance = morpherToken.balanceOf(user);
		assertEq(userBalance, expectedShareValue * 10 ** 8);
	}

	function testBuildUpAndPaybackEscrow() public {
		morpherTradeEngine.setEscrowOpenOrderEnabled(true);
		address user = address(0xff01);
		morpherToken.mint(user, 100 ether);

		vm.warp(SECOND_RATE_TS);

		vm.prank(address(morpherOracle));
		vm.expectEmit(true, true, true, false);
		emit OrderIdRequested(bytes32(0x0), user, keccak256("CRYPTO_BTC"), 0, 100 ether, true, 500000000);
		vm.expectEmit(true, true, true, true);
		emit Transfer(user, address(0x0), 100 ether);
		vm.expectEmit(true, true, true, false);
		emit EscrowPaid(bytes32(0x0), user, 100 ether);
		bytes32 orderId = morpherTradeEngine.requestOrderId(
			user,
			keccak256("CRYPTO_BTC"),
			0,
			100 ether,
			true,
			5 * PRECISION
		);

		(, , , , , , , , , , uint256 orderEscrowAmount, ) = morpherTradeEngine.orders(orderId);
		assertEq(orderEscrowAmount, 100 ether);
		assertEq(morpherToken.balanceOf(user), 0);

		vm.warp(SECOND_RATE_TS + 2);

		vm.prank(address(morpherOracle));
		// vm.expectEmit(true, true, true, true);
		// emit Transfer(address(0x0), user, 100 ether);
		// vm.expectEmit(true, true, true, true);
		// emit EscrowReturned(orderId, user, 100 ether);
		morpherTradeEngine.processOrder(orderId, 50000 * PRECISION, 10 * PRECISION, 0, SECOND_RATE_TS * 1000 + 1000);
		(, , , , , , , , , , uint256 orderEscrowAmount2, ) = morpherTradeEngine.orders(orderId);
		assertEq(orderEscrowAmount2, 0);
		// reminder of the position opening
		assertEq(morpherToken.balanceOf(user), 4905000000000);
	}

	function testValidateClosedMarketOrderConditions() public {
		address user = address(0xff01);
		morpherToken.mint(user, 100 ether);

		vm.warp(SECOND_RATE_TS);
		vm.startPrank(address(morpherOracle));

		vm.expectRevert();
		// can't open if market disabled
		morpherTradeEngine.requestOrderId(user, keccak256("CRYPTO_DOGE"), 0, 100 ether, true, PRECISION);

		bytes32 orderId = morpherTradeEngine.requestOrderId(
			user,
			keccak256("CRYPTO_BTC"),
			0,
			100 ether,
			true,
			PRECISION
		);
		morpherTradeEngine.processOrder(orderId, 50000 * PRECISION, 10 * PRECISION, 0, SECOND_RATE_TS * 1000);

		// disable market now
		vm.stopPrank();
		morpherState.deActivateMarket(keccak256("CRYPTO_BTC"));

		vm.prank(address(morpherOracle));
		// fails because of no deactivated market price
		vm.expectRevert();
		morpherTradeEngine.requestOrderId(user, keccak256("CRYPTO_BTC"), 19996000, 0, false, PRECISION);

		morpherTradeEngine.setDeactivatedMarketPrice(keccak256("CRYPTO_BTC"), 25000 * PRECISION);

		vm.startPrank(address(morpherOracle));

		// fails because of no full position close
		vm.expectRevert();
		morpherTradeEngine.requestOrderId(user, keccak256("CRYPTO_BTC"), 19995999, 0, false, PRECISION);

		// now it goes through
		orderId = morpherTradeEngine.requestOrderId(user, keccak256("CRYPTO_BTC"), 19996000, 0, false, PRECISION);
		morpherTradeEngine.processOrder(orderId, 50000 * PRECISION, 10 * PRECISION, 0, SECOND_RATE_TS * 1000);
		// uses the deactivated market price instead of the oracle one
		uint256 userBalance = morpherToken.balanceOf(user);
		assertEq(userBalance, 49.970008 ether);

		// activate to create a short
		vm.stopPrank();
		morpherState.activateMarket(keccak256("CRYPTO_BTC"));
		vm.startPrank(address(morpherOracle));

		orderId = morpherTradeEngine.requestOrderId(user, keccak256("CRYPTO_BTC"), 0, 10 ether, false, PRECISION);
		morpherTradeEngine.processOrder(orderId, 50000 * PRECISION, 10 * PRECISION, 0, SECOND_RATE_TS * 1000);

		// disable market now
		vm.stopPrank();
		morpherState.deActivateMarket(keccak256("CRYPTO_BTC"));
		vm.startPrank(address(morpherOracle));

		// fails because of no full position close
		vm.expectRevert();
		morpherTradeEngine.requestOrderId(user, keccak256("CRYPTO_BTC"), 1999599, 0, true, PRECISION);

		// now it goes through
		orderId = morpherTradeEngine.requestOrderId(user, keccak256("CRYPTO_BTC"), 1999600, 0, true, PRECISION);
		morpherTradeEngine.processOrder(orderId, 50000 * PRECISION, 10 * PRECISION, 0, SECOND_RATE_TS * 1000);
		// uses the deactivated market price instead of the oracle one
		userBalance = morpherToken.balanceOf(user);
		assertEq(userBalance, 54.9650088 ether);
	}

	function testCancelOrder() public {
		address user = address(0xff01);
		morpherToken.mint(user, 100 ether);

		vm.warp(SECOND_RATE_TS);

		vm.prank(address(morpherOracle));
		bytes32 orderId = morpherTradeEngine.requestOrderId(
			user,
			keccak256("CRYPTO_BTC"),
			0,
			100 ether,
			true,
			5 * PRECISION
		);

		assertEq(morpherToken.balanceOf(user), 100 ether);

		vm.warp(SECOND_RATE_TS + 2);

		vm.prank(address(morpherOracle));
		vm.expectEmit(true, true, true, true);
		emit OrderCancelled(orderId, user);
		morpherTradeEngine.cancelOrder(orderId, user);

		assertEq(morpherToken.balanceOf(user), 100 ether);
	}

	function testCancelOrderWithEscrow() public {
		morpherTradeEngine.setEscrowOpenOrderEnabled(true);
		address user = address(0xff01);
		morpherToken.mint(user, 100 ether);

		vm.warp(SECOND_RATE_TS);

		vm.prank(address(morpherOracle));
		bytes32 orderId = morpherTradeEngine.requestOrderId(
			user,
			keccak256("CRYPTO_BTC"),
			0,
			100 ether,
			true,
			5 * PRECISION
		);

		assertEq(morpherToken.balanceOf(user), 0);

		vm.warp(SECOND_RATE_TS + 2);

		vm.prank(address(morpherOracle));
		vm.expectEmit(true, true, true, true);
		emit EscrowReturned(orderId, user, 100 ether);
		vm.expectEmit(true, true, true, true);
		emit OrderCancelled(orderId, user);
		morpherTradeEngine.cancelOrder(orderId, user);

		assertEq(morpherToken.balanceOf(user), 100 ether);
	}

	function testAdminSetPosition() public {
		address addr = address(0x123abc);
		bytes32 marketId = keccak256("CRYPTO_BTC");
		uint256 timeStamp = SECOND_RATE_TS;
		uint256 longShares = 100;
		uint256 shortShares = 50;
		uint256 meanEntryPrice = 1000 * 10 ** 8;
		uint256 meanEntrySpread = 1 * 10 ** 8;
		uint256 meanEntryLeverage = PRECISION;
		uint256 liquidationPrice = 500 * 10 ** 8;
		bytes32 positionHash = morpherTradeEngine.getPositionHash(
			addr,
			marketId,
			timeStamp,
			longShares,
			shortShares,
			meanEntryPrice,
			meanEntrySpread,
			meanEntryLeverage,
			liquidationPrice
		);

		morpherAccessControl.grantRole(keccak256("POSITIONADMIN_ROLE"), address(this));
		vm.expectEmit(true, true, true, true);
		emit SetPosition(
			positionHash,
			addr,
			marketId,
			timeStamp,
			longShares,
			shortShares,
			meanEntryPrice,
			meanEntrySpread,
			meanEntryLeverage,
			liquidationPrice
		);
		morpherTradeEngine.setPosition(
			addr,
			marketId,
			timeStamp,
			longShares,
			shortShares,
			meanEntryPrice,
			meanEntrySpread,
			meanEntryLeverage,
			liquidationPrice
		);

		MorpherTradeEngine.position memory pos = morpherTradeEngine.getPosition(addr, keccak256("CRYPTO_BTC"));
		assertEq(pos.positionHash, positionHash);
		assertEq(pos.lastUpdated, timeStamp);
		assertEq(pos.longShares, longShares);
		assertEq(pos.shortShares, shortShares);
		assertEq(pos.meanEntryPrice, meanEntryPrice);
		assertEq(pos.meanEntrySpread, meanEntrySpread);
		assertEq(pos.meanEntryLeverage, meanEntryLeverage);
		assertEq(pos.liquidationPrice, liquidationPrice);
	}

	function testPositionMigrationPermissionless() public {
		Account memory owner = makeAccount("owner");
		Account memory posAdmin = makeAccount("positionadmin");
		morpherAccessControl.grantRole(keccak256("POSITIONADMIN_ROLE"), posAdmin.addr);

		bytes32 marketId = keccak256("CRYPTO_BTC");	

		bytes32 structHash = keccak256(
			abi.encode(
				POSITION_TYPE_HASH,
				SECOND_RATE_TS,
				100,
				50,
				1000 * 10 ** 8,
				1 * 10 ** 8,
				PRECISION,
				500 * 10 ** 8,
				owner.addr,
				0,
				SECOND_RATE_TS + 1	
			)
		);
		bytes32 domainSeparator = keccak256(
			abi.encode(
				DOMAIN_TYPE_HASH,
				keccak256("MorpherTradeEngine"),
				keccak256("1"),
				block.chainid,
				address(morpherToken)
			)
		);
		bytes32 finalHash = ECDSAUpgradeable.toTypedDataHash(domainSeparator, structHash);
		(uint8 v, bytes32 r, bytes32 s) = vm.sign(posAdmin.key, finalHash);

		structHash = keccak256(
			abi.encode(
				POSITION_TYPE_HASH,
				SECOND_RATE_TS,
				100,
				50,
				1000 * 10 ** 8,
				1 * 10 ** 8,
				PRECISION,
				500 * 10 ** 8,
				posAdmin.addr,
				0,
				SECOND_RATE_TS + 1	
			)
		);
		domainSeparator = keccak256(
			abi.encode(
				DOMAIN_TYPE_HASH,
				keccak256("MorpherTradeEngine"),
				keccak256("1"),
				block.chainid,
				address(morpherToken)
			)
		);
		finalHash = ECDSAUpgradeable.toTypedDataHash(domainSeparator, structHash);
		(v, r, s) = vm.sign(posAdmin.key, finalHash);
	}
}
