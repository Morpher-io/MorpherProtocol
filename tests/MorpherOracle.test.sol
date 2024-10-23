// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

import "./BaseSetup.sol";
import "../contracts/MorpherOracle.sol";

// using staking as one of the inheriting contracts
contract MorpherOracleTest is BaseSetup, MorpherOracle {
	uint public constant PRECISION = 1e8;

	event Transfer(address indexed from, address indexed to, uint256 value);

	event PositionUpdated(
		address _userId,
		bytes32 _marketId,
		uint256 _timeStamp,
		uint256 _newLongShares,
		uint256 _newShortShares,
		uint256 _newMeanEntryPrice,
		uint256 _newMeanEntrySpread,
		uint256 _newMeanEntryLeverage,
		uint256 _newLiquidationPrice,
		uint256 _mint,
		uint256 _burn
	);

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

	event OrderIdRequested(
		bytes32 _orderId,
		address indexed _address,
		bytes32 indexed _marketId,
		uint256 _closeSharesAmount,
		uint256 _openMPHTokenAmount,
		bool _tradeDirection,
		uint256 _orderLeverage
	);

	event OrderProcessed(
		bytes32 _orderId,
		uint256 _marketPrice,
		uint256 _marketSpread,
		uint256 _liquidationTimestamp,
		uint256 _timeStamp,
		uint256 _newLongShares,
		uint256 _newShortShares,
		uint256 _newAverageEntry,
		uint256 _newAverageSpread,
		uint256 _newAverageLeverage,
		uint256 _liquidationPrice
	);

	function setUp() public override {
		super.setUp();
		morpherAccessControl.grantRole(morpherOracle.ADMINISTRATOR_ROLE(), address(this));
	}

	function generatePosition(bytes32 market, address user) public {
		morpherAccessControl.grantRole(keccak256("MINTER_ROLE"), address(this));
		morpherToken.mint(user, 100 * 10 ** 18);
		morpherAccessControl.revokeRole(keccak256("MINTER_ROLE"), address(this));

		vm.prank(address(morpherOracle));
		bytes32 orderId = morpherTradeEngine.requestOrderId(user, market, 0, 100 * 10 ** 18, true, 10 ** 8);

		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(orderId, 1000 * 10 ** 8, 10 ** 8, 0, 0);
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
		uint256 openMPHTokenAmount = 50 * 1e18;
		bool tradeDirection = true;
		uint256 orderLeverage = 1e8;
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

	function testCreateOrder() public {
		address user = address(0xff01);

		bytes32 expectedOrderId = keccak256(
			abi.encodePacked(
				user,
				block.number,
				keccak256("CRYPTO_BTC"),
				uint(0),
				uint(100 * 1e18),
				true,
				2 * PRECISION,
				uint(1)
			)
		);

		vm.prank(user);
		vm.expectEmit(true, true, true, true);
		emit OrderIdRequested(expectedOrderId, user, keccak256("CRYPTO_BTC"), 0, 100 * 1e18, true, 2 * PRECISION);
		vm.expectEmit(true, true, true, true);
		emit OrderCreated(
			expectedOrderId,
			user,
			keccak256("CRYPTO_BTC"),
			0,
			100 * 1e18,
			true,
			2 * PRECISION,
			110 * 1e18,
			90 * 1e18,
			1,
			999999999999999
		);
		bytes32 orderId = morpherOracle.createOrder(
			keccak256("CRYPTO_BTC"),
			0,
			100 * 1e18,
			true,
			2 * PRECISION,
			90 * 1e18,
			110 * 1e18,
			999999999999999,
			1
		);
		assertEq(orderId, expectedOrderId);
		assertEq(morpherOracle.priceAbove(orderId), 90 * 1e18);
		assertEq(morpherOracle.priceBelow(orderId), 110 * 1e18);
		assertEq(morpherOracle.goodFrom(orderId), 1);
		assertEq(morpherOracle.goodUntil(orderId), 999999999999999);
	}

	function testCreateOrderForDeactivatedMarket() public {
		vm.warp(1700000000);
		address user = address(0xff01);

		generatePosition(keccak256("CRYPTO_BTC"), user);

		morpherState.deActivateMarket(keccak256("CRYPTO_BTC"));
		morpherTradeEngine.setDeactivatedMarketPrice(keccak256("CRYPTO_BTC"), 25000 * PRECISION);

		bytes32 orderId = keccak256(
			abi.encodePacked(
				user,
				block.number,
				keccak256("CRYPTO_BTC"),
				uint(999000999),
				uint(0),
				false,
				PRECISION,
				uint(2)
			)
		);
		bytes32 positionHash = morpherTradeEngine.getPositionHash(
			user,
			keccak256("CRYPTO_BTC"),
			block.timestamp * 1000,
			0,
			0,
			0,
			0,
			PRECISION,
			0
		);

		vm.prank(user);
		vm.expectEmit(true, true, true, true);
		emit OrderIdRequested(orderId, user, keccak256("CRYPTO_BTC"), 999000999, 0, false, PRECISION);
		vm.expectEmit(true, true, true, true);
		emit Transfer(address(0), user, 2497502497500000000000);
		vm.expectEmit(true, true, true, true);
		emit SetPosition(positionHash, user, keccak256("CRYPTO_BTC"), block.timestamp * 1000, 0, 0, 0, 0, PRECISION, 0);
		vm.expectEmit(true, true, true, true);
		emit PositionUpdated(
			user,
			keccak256("CRYPTO_BTC"),
			block.timestamp * 1000,
			0,
			0,
			0,
			0,
			PRECISION,
			0,
			2497502497500000000000,
			0
		);
		vm.expectEmit(true, true, true, true);
		emit OrderProcessed(orderId, 25000 * PRECISION, 0, 0, block.timestamp * 1000, 0, 0, 0, 0, PRECISION, 0);
		vm.expectEmit(true, true, true, true);
		emit MorpherOracle.OrderProcessed(
			orderId,
			25000 * PRECISION,
			0,
			0,
			0,
			block.timestamp * 1000,
			0,
			0,
			0,
			0,
			0,
			0
		);
		morpherOracle.createOrder(keccak256("CRYPTO_BTC"), 999000999, 0, false, PRECISION, 0, 0, 0, 0);
	}

	function testCreateOrderWithSignature() public {
		Account memory owner = makeAccount("owner");

		CreateOrderStruct memory str = CreateOrderStruct(
			keccak256("CRYPTO_BTC"),
			uint(0),
			uint(100 * 1e18),
			true,
			2 * PRECISION,
			uint(90 * 1e18),
			uint(110 * 1e18),
			uint(999999999999999),
			uint(1)
		);

		uint nonce = morpherOracle.nonces(owner.addr);

		bytes32 structHash = keccak256(
			abi.encode(
				_PERMIT_TYPEHASH,
				str._marketId,
				str._closeSharesAmount,
				str._openMPHTokenAmount,
				owner.addr,
				nonce,
				str._goodUntil
			)
		);
		bytes32 domainSeparator = keccak256(
			abi.encode(_TYPE_HASH, _HASHED_NAME, _HASHED_VERSION, block.chainid, address(morpherOracle))
		);
		bytes32 finalHash = ECDSAUpgradeable.toTypedDataHash(domainSeparator, structHash);
		(uint8 v, bytes32 r, bytes32 s) = vm.sign(owner.key, finalHash);

		bytes32 expectedOrderId = keccak256(
			abi.encodePacked(
				owner.addr,
				block.number,
				keccak256("CRYPTO_BTC"),
				uint(0),
				uint(100 * 1e18),
				true,
				2 * PRECISION,
				uint(1)
			)
		);

		bytes32 orderId = morpherOracle.createOrderPermittedBySignature(str, owner.addr, str._goodUntil, v, r, s);
		assertEq(orderId, expectedOrderId);
	}
}
