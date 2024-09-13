// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "./BaseSetup.sol";
import "../contracts/MorpherAdmin.sol";

contract MorpherAdminTest is BaseSetup, MorpherAdmin {
	function setUp() public override {
		super.setUp();
		morpherAccessControl.grantRole(ADMINISTRATOR_ROLE, address(this));
		morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(this));
	}

	function generatePosition(bytes32 market, address user) public {
		morpherToken.mint(user, 100 * 10 ** 18);

		vm.prank(address(morpherOracle));
		bytes32 orderId = morpherTradeEngine.requestOrderId(user, market, 0, 100 * 10 ** 18, true, 10 ** 8);

		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(orderId, 1000 * 10 ** 8, 10 ** 8, 0, block.timestamp * 1000);
	}

	function testPositionMigrationToNewMarketsFull() public {
		vm.warp(1630000000);
		address user = address(0x123);
		bytes32 oldMarket = keccak256("CRYPTO_BTC_OLD");
		bytes32 newMarket = keccak256("CRYPTO_BTC_NEW");
		morpherState.activateMarket(oldMarket);

		this.generatePosition(oldMarket, user);

		uint longShares;
		(, longShares, , , , , , ) = morpherTradeEngine.portfolio(user, oldMarket);

		assertEq(longShares, 999000999);
		bool active = morpherState.getMarketActive(oldMarket);
		assertEq(active, true);

		vm.expectRevert();
		morpherAdmin.migratePositionsToNewMarket(oldMarket, newMarket);

		morpherState.deActivateMarket(oldMarket);
		morpherState.activateMarket(newMarket);

		vm.expectRevert();
		morpherAdmin.migratePositionsToNewMarket(oldMarket, newMarket);

		morpherState.deActivateMarket(newMarket);

		vm.expectEmit(true, true, true, true);
		emit AddressPositionMigrationComplete(user, oldMarket, newMarket);
		vm.expectEmit(true, true, true, true);
		emit AllPositionMigrationsComplete(oldMarket, newMarket);
		morpherAdmin.migratePositionsToNewMarket(oldMarket, newMarket);

		(, longShares, , , , , , ) = morpherTradeEngine.portfolio(user, oldMarket);
		assertEq(longShares, 0);
		(, longShares, , , , , , ) = morpherTradeEngine.portfolio(user, newMarket);
		assertEq(longShares, 999000999);
	}

	// no idea how to test this
	function testPositionMigrationToNewMarketsPartial() public {
		vm.warp(1630000000);
		address user = address(0x123);
		address user2 = address(0x456);
		bytes32 oldMarket = keccak256("CRYPTO_BTC_OLD");
		bytes32 newMarket = keccak256("CRYPTO_BTC_NEW");
		morpherState.activateMarket(oldMarket);

		this.generatePosition(oldMarket, user);
		this.generatePosition(oldMarket, user2);

		morpherState.deActivateMarket(oldMarket);

		vm.expectEmit(true, true, true, true);
		emit AddressPositionMigrationComplete(user, oldMarket, newMarket);
		// vm.expectEmit(true, true, true, true);
		// emit AllPositionMigrationIncomplete(oldMarket, newMarket, 0);
		morpherAdmin.migratePositionsToNewMarket(oldMarket, newMarket);

		uint longShares;
		(, longShares, , , , , , ) = morpherTradeEngine.portfolio(user, oldMarket);
		assertEq(longShares, 0);
		(, longShares, , , , , , ) = morpherTradeEngine.portfolio(user, newMarket);
		assertEq(longShares, 999000999);

		// (, longShares, , , , , , ) = morpherTradeEngine.portfolio(user2, oldMarket);
		// assertEq(longShares, 999000999);
		// (, longShares, , , , , , ) = morpherTradeEngine.portfolio(user2, newMarket);
		// assertEq(longShares, 0);
	}

	function testBulkActivate() public {
		bytes32[] memory markets = new bytes32[](2);
		markets[0] = keccak256("CRYPTO_ETH");
		markets[1] = keccak256("CRYPTO_SOL");
		bool active = morpherState.getMarketActive(markets[0]);
		assertEq(active, false);
		active = morpherState.getMarketActive(markets[1]);
		assertEq(active, false);

		morpherAdmin.bulkActivateMarkets(markets);

		active = morpherState.getMarketActive(markets[0]);
		assertEq(active, true);
		active = morpherState.getMarketActive(markets[1]);
		assertEq(active, true);
	}

	function testAdminLiquidationOrder() public {
		vm.warp(1630000000);
		address user = address(0x123);
		address user2 = address(0x456);
		bytes32 market = keccak256("CRYPTO_BTC");

		this.generatePosition(market, user);

		// generate also short position
		morpherToken.mint(user2, 100 * 10 ** 18);
		vm.prank(address(morpherOracle));
		bytes32 orderId = morpherTradeEngine.requestOrderId(user2, market, 0, 100 * 10 ** 18, false, 10 ** 8);
		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(orderId, 1000 * 10 ** 8, 10 ** 8, 0, block.timestamp * 1000);

		uint longShares;
		(, longShares, , , , , , ) = morpherTradeEngine.portfolio(user, market);
		assertEq(longShares, 999000999);
		uint shortShares;
		(, , shortShares, , , , , ) = morpherTradeEngine.portfolio(user2, market);
		assertEq(shortShares, 999000999);

		vm.expectEmit(false, true, true, true);
		emit AdminLiquidationOrderCreated(bytes32(0x0), user, market, 999000999, 0, false, 10 ** 8);
		bytes32 order1Id = morpherAdmin.adminLiquidationOrder(user, market);
		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(order1Id, 1000 * 10 ** 8, 10 ** 8, 0, block.timestamp * 1000);

		vm.expectEmit(false, true, true, true);
		emit AdminLiquidationOrderCreated(bytes32(0x0), user2, market, 999000999, 0, true, 10 ** 8);
		bytes32 order2Id = morpherAdmin.adminLiquidationOrder(user2, market);
		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(order2Id, 1000 * 10 ** 8, 10 ** 8, 0, block.timestamp * 1000);

		longShares;
		(, longShares, , , , , , ) = morpherTradeEngine.portfolio(user, market);
		assertEq(longShares, 0);
		shortShares;
		(, , shortShares, , , , , ) = morpherTradeEngine.portfolio(user2, market);
		assertEq(shortShares, 0);
	}

	function testDelistMarket() public {
		vm.warp(1630000000);
		address user = address(0x123);
		address user2 = address(0x456);
		bytes32 market = keccak256("CRYPTO_BTC");

		this.generatePosition(market, user);

		// generate also short position
		morpherToken.mint(user2, 100 * 10 ** 18);
		vm.prank(address(morpherOracle));
		bytes32 orderId = morpherTradeEngine.requestOrderId(user2, market, 0, 100 * 10 ** 18, false, 10 ** 8);
		vm.prank(address(morpherOracle));
		morpherTradeEngine.processOrder(orderId, 1000 * 10 ** 8, 10 ** 8, 0, block.timestamp * 1000);
		
		vm.expectEmit(false, true, true, true);
		emit AdminLiquidationOrderCreated(bytes32(0x0), user, market, 999000999, 0, false, 10 ** 8);
		vm.expectEmit(false, true, true, true);
		emit AdminLiquidationOrderCreated(bytes32(0x0), user2, market, 999000999, 0, true, 10 ** 8);
		morpherAdmin.delistMarket(market, 0, 0);	
	}
}
