// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

import "./BaseSetup.sol";
import "./mocks/ERC20.sol";
import "./mocks/UniswapRouter.sol";
import "../contracts/MorpherOracle.sol";

// using staking as one of the inheriting contracts
contract MorpherOracleTest is BaseSetup, MorpherOracle {
	uint public constant PRECISION = 1e8;

	MockERC20 public WMATIC;
	MockERC20 public OTHER_ERC20;

	event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

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
		bytes memory contractCode = type(MockUniswapRouter).runtimeCode;
		vm.etch(UNISWAP_ROUTER, contractCode);
		WMATIC = new MockERC20("wmatic", "WMATIC");
		WMATIC.mint(UNISWAP_ROUTER, 100000 ether);
		OTHER_ERC20 = new MockERC20("test", "TEST");
		OTHER_ERC20.mint(UNISWAP_ROUTER, 100000 ether);
		morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(this));
		morpherToken.mint(UNISWAP_ROUTER, 100000 ether);
		morpherAccessControl.revokeRole(morpherToken.MINTER_ROLE(), address(this));
		morpherOracle.setWmaticAddress(address(WMATIC));
		morpherToken.setRestrictTransfers(false);
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

	function testCreateOpenOrderWithToken() public {
		Account memory owner = makeAccount("owner");

		WMATIC.mint(owner.addr, 50 ether);

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

		bytes32 erc20PermitTypehash = keccak256(
			"Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
		);
		bytes32 structHash = keccak256(
			abi.encode(erc20PermitTypehash, owner.addr, address(morpherOracle), 50 ether, 0, 1)
		);
		bytes32 domainHash = keccak256(
			abi.encode(_TYPE_HASH, keccak256("wmatic"), keccak256("1"), block.chainid, address(WMATIC))
		);

		bytes32 finalHash = ECDSAUpgradeable.toTypedDataHash(domainHash, structHash);
		(uint8 v, bytes32 r, bytes32 s) = vm.sign(owner.key, finalHash);

		TokenPermitEIP712Struct memory inputToken = TokenPermitEIP712Struct(
			address(WMATIC),
			owner.addr,
			50 ether,
			50 ether,
			1,
			v,
			r,
			s
		);

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

		vm.prank(owner.addr);
		// wmatic from user to morpher oracle
		vm.expectEmit(true, true, true, true);
		emit Approval(owner.addr, address(morpherOracle), 50 ether);
		vm.expectEmit(true, true, true, true);
		emit Approval(owner.addr, address(morpherOracle), 0);
		vm.expectEmit(true, true, true, true);
		emit Transfer(owner.addr, address(morpherOracle), 50 ether);
		// wmatic and mph from oracle to uniswap	
		vm.expectEmit(true, true, true, true);
		emit Approval(address(morpherOracle), UNISWAP_ROUTER, 50 ether);
		vm.expectEmit(true, true, true, true);
		emit Approval(address(morpherOracle), UNISWAP_ROUTER, 100 ether);
		// swap get executed (mocking contract)
		vm.expectEmit(true, true, true, true);
		emit Approval(address(morpherOracle), UNISWAP_ROUTER, 0);
		vm.expectEmit(true, true, true, true);
		emit Transfer(address(morpherOracle), UNISWAP_ROUTER, 50 ether); // -> wmatic
		vm.expectEmit(true, true, true, true);
		emit Transfer(UNISWAP_ROUTER, owner.addr, 100 ether); // -> mph
		// wmatic and mph from oracle to uniswap reset
		vm.expectEmit(true, true, true, true);
		emit Approval(address(morpherOracle), UNISWAP_ROUTER, 0);
		vm.expectEmit(true, true, true, true);
		emit Approval(address(morpherOracle), UNISWAP_ROUTER, 0);
		vm.expectEmit(true, true, true, true);
		emit OrderIdRequested(expectedOrderId, owner.addr, keccak256("CRYPTO_BTC"), 0, 100 * 1e18, true, 2 * PRECISION);
		vm.expectEmit(true, true, true, true);
		emit OrderCreated(
			expectedOrderId,
			owner.addr,
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
		morpherOracle.createOrderFromToken(str, inputToken);

		assertEq(morpherOracle.priceAbove(expectedOrderId), 90 * 1e18);
		assertEq(morpherOracle.priceBelow(expectedOrderId), 110 * 1e18);
		assertEq(morpherOracle.goodFrom(expectedOrderId), 1);
		assertEq(morpherOracle.goodUntil(expectedOrderId), 999999999999999);

		// check balances
		assertEq(WMATIC.balanceOf(address(morpherOracle)), 0);
		assertEq(morpherToken.balanceOf(address(morpherOracle)), 0);
		assertEq(WMATIC.balanceOf(owner.addr), 0);
		assertEq(morpherToken.balanceOf(owner.addr), 100 ether);
		assertEq(WMATIC.balanceOf(UNISWAP_ROUTER), 100050 ether);
		assertEq(morpherToken.balanceOf(UNISWAP_ROUTER), 99900 ether);
	}

	function testCreateOpenOrderWithTokenWithOtherERC20() public {
		Account memory owner = makeAccount("owner");

		OTHER_ERC20.mint(owner.addr, 50 ether);

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

		bytes32 erc20PermitTypehash = keccak256(
			"Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
		);
		bytes32 structHash = keccak256(
			abi.encode(erc20PermitTypehash, owner.addr, address(morpherOracle), 50 ether, 0, 1)
		);
		bytes32 domainHash = keccak256(
			abi.encode(_TYPE_HASH, keccak256("test"), keccak256("1"), block.chainid, address(OTHER_ERC20))
		);

		bytes32 finalHash = ECDSAUpgradeable.toTypedDataHash(domainHash, structHash);
		(uint8 v, bytes32 r, bytes32 s) = vm.sign(owner.key, finalHash);

		TokenPermitEIP712Struct memory inputToken = TokenPermitEIP712Struct(
			address(OTHER_ERC20),
			owner.addr,
			50 ether,
			50 ether,
			1,
			v,
			r,
			s
		);

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

		vm.prank(owner.addr);
		morpherOracle.createOrderFromToken(str, inputToken);

		// check balances
		assertEq(WMATIC.balanceOf(address(morpherOracle)), 0);
		assertEq(OTHER_ERC20.balanceOf(address(morpherOracle)), 0);
		assertEq(morpherToken.balanceOf(address(morpherOracle)), 0);
		assertEq(WMATIC.balanceOf(owner.addr), 0);
		assertEq(OTHER_ERC20.balanceOf(owner.addr), 0);
		assertEq(morpherToken.balanceOf(owner.addr), 100 ether);
		assertEq(WMATIC.balanceOf(UNISWAP_ROUTER), 100000 ether);
		assertEq(OTHER_ERC20.balanceOf(UNISWAP_ROUTER), 100050 ether);
		assertEq(morpherToken.balanceOf(UNISWAP_ROUTER), 99900 ether);
	}

	function testCreateOpenOrderWithTokenAndSignature() public {
		Account memory owner = makeAccount("owner");

		WMATIC.mint(owner.addr, 50 ether);

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

		bytes32 erc20PermitTypehash = keccak256(
			"Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
		);
		bytes32 structHash = keccak256(
			abi.encode(erc20PermitTypehash, owner.addr, address(morpherOracle), 50 ether, 0, 1)
		);
		bytes32 domainHash = keccak256(
			abi.encode(_TYPE_HASH, keccak256("wmatic"), keccak256("1"), block.chainid, address(WMATIC))
		);

		bytes32 finalHash = ECDSAUpgradeable.toTypedDataHash(domainHash, structHash);
		(uint8 v, bytes32 r, bytes32 s) = vm.sign(owner.key, finalHash);

		TokenPermitEIP712Struct memory inputToken = TokenPermitEIP712Struct(
			address(WMATIC),
			owner.addr,
			50 ether,
			50 ether,
			1,
			v,
			r,
			s
		);

		uint nonce = morpherOracle.nonces(owner.addr);

		structHash = keccak256(
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
		domainHash = keccak256(
			abi.encode(_TYPE_HASH, _HASHED_NAME, _HASHED_VERSION, block.chainid, address(morpherOracle))
		);
		finalHash = ECDSAUpgradeable.toTypedDataHash(domainHash, structHash);
		(v, r, s) = vm.sign(owner.key, finalHash);

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
	
		morpherOracle.createOrderFromToken(str, inputToken, owner.addr, str._goodUntil, v, r, s);

		assertEq(morpherOracle.priceAbove(expectedOrderId), 90 * 1e18);
		assertEq(morpherOracle.priceBelow(expectedOrderId), 110 * 1e18);
		assertEq(morpherOracle.goodFrom(expectedOrderId), 1);
		assertEq(morpherOracle.goodUntil(expectedOrderId), 999999999999999);

		// check balances
		assertEq(WMATIC.balanceOf(address(morpherOracle)), 0);
		assertEq(morpherToken.balanceOf(address(morpherOracle)), 0);
		assertEq(WMATIC.balanceOf(owner.addr), 0);
		assertEq(morpherToken.balanceOf(owner.addr), 100 ether);
		assertEq(WMATIC.balanceOf(UNISWAP_ROUTER), 100050 ether);
		assertEq(morpherToken.balanceOf(UNISWAP_ROUTER), 99900 ether);
	}

	function testCallbackForOpenPosition() public {}
	function testCallbackForClosePositionInMph() public {}
	function testCallbackForClosePositionInWMmatic() public {}
	function testLiquidationOrder() public {}
	function testLiquidationOrderFromAdmin() public {}
	function testCancelOrder() public {}
	function testCancelOrderFromAdmin() public {}
	function testDelistMarket() public {}
	function testCheckOrderConditionsLogic() public {}
}
