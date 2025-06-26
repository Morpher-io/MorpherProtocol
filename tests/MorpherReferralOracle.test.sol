// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ECDSA} from "../lib/openzeppelin-contracts-5/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "../lib/openzeppelin-contracts-5/contracts/utils/cryptography/MessageHashUtils.sol";

import "./BaseSetup.sol";
import "./mocks/ERC20.sol";
import "./mocks/UniswapRouter.sol"; // Assuming this mock is suitable
import "../contracts/MorpherReferralOracle.sol";
import "../contracts/interfaces/IMorpherTradeEngine.sol"; // For position struct

contract MorpherReferralOracleTest is BaseSetup {
    MorpherReferralOracle public morpherReferralOracle;
    MockERC20 public WETH_MOCK; // Using a generic mock ERC20 for WETH

    uint256 public constant INITIAL_REFERRAL_PERCENTAGE = 1000; // 10%
    uint256 public constant REFERRAL_PERCENTAGE_PRECISION = 10000;
    uint256 public constant PRECISION = 1e8;


    // Events from MorpherReferralOracle
    event ReferralOrderCreated(
        bytes32 indexed orderId,
        address indexed trader,
        address indexed beneficiary,
        bytes32 marketId,
        uint256 openMPHTokenAmount,
        bool tradeDirection,
        uint256 orderLeverage
    );

    event ReferralOpenDetailsStored(
        address indexed trader,
        bytes32 indexed marketId,
        address indexed beneficiary,
        uint256 initialInvestmentValue
    );

    event ReferralBonusPaid(
        address indexed trader,
        bytes32 indexed marketId,
        address indexed beneficiary,
        uint256 lossAmount,
        uint256 bonusAmount
    );

    event ReferralOrderProcessed(
        bytes32 indexed _orderId,
        uint256 _price,
        uint256 _unadjustedMarketPrice,
        uint256 _spread,
        uint256 _positionLiquidationTimestamp,
        uint256 _timeStamp,
        uint256 _newLongShares,
        uint256 _newShortShares,
        uint256 _newMeanEntry,
        uint256 _newMeanSprad,
        uint256 _newMeanLeverage,
        uint256 _liquidationPrice
    );


    function setUp() public override {
        super.setUp(); // Sets up MorpherState, MorpherToken, MorpherTradeEngine, MorpherAccessControl

        // Deploy Mock WETH
        WETH_MOCK = new MockERC20("Mock WETH", "MWETH");

        // Deploy Mock Uniswap Router
        address mockUniswapRouterAddress = address(new MockUniswapRouter());
        MockUniswapRouter mockUniswapRouter = MockUniswapRouter(mockUniswapRouterAddress);
        mockUniswapRouter.setWethAddress(address(WETH_MOCK)); // Configure mock router with mock WETH

        // Mint some WETH and MPH to the mock router for swaps
        WETH_MOCK.mint(mockUniswapRouterAddress, 1000 ether);
        morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(this));
        morpherToken.mint(mockUniswapRouterAddress, 100000 ether); // Router has MPH
        morpherAccessControl.revokeRole(morpherToken.MINTER_ROLE(), address(this));


        // Deploy MorpherReferralOracle
        vm.startBroadcast();
        morpherReferralOracle = new MorpherReferralOracle();
        morpherReferralOracle.initialize(
            address(morpherState),
            address(morpherTradeEngine),
            address(morpherToken),
            address(WETH_MOCK),
            mockUniswapRouterAddress,
            INITIAL_REFERRAL_PERCENTAGE,
            "MorpherReferralOracle",
            "1"
        );
        vm.stopBroadcast();

        // Configure MorpherTradeEngine with MorpherReferralOracle address
        morpherAccessControl.grantRole(morpherTradeEngine.ADMINISTRATOR_ROLE(), address(this));
        morpherTradeEngine.setMorpherReferralOracleAddress(address(morpherReferralOracle));


        // Grant necessary roles to this test contract for admin operations on MRO
        morpherAccessControl.grantRole(morpherReferralOracle.ADMINISTRATOR_ROLE(), address(this));
        morpherAccessControl.grantRole(morpherReferralOracle.PAUSER_ROLE(), address(this));
        // Grant ORACLEOPERATOR_ROLE to this test contract to simulate callbacks
        bytes32 oracleOperatorRole = keccak256("ORACLEOPERATOR_ROLE");
        morpherAccessControl.grantRole(oracleOperatorRole, address(this));


        // Allow MorpherReferralOracle to mint MorpherToken (for referral bonuses)
        morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(morpherReferralOracle));
        // Allow MorpherTradeEngine to burn/mint MorpherToken (for trades)
        morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(morpherTradeEngine));
        morpherAccessControl.grantRole(morpherToken.BURNER_ROLE(), address(morpherTradeEngine));


        // Unrestrict token transfers for easier testing if needed
        morpherToken.setRestrictTransfers(false);
    }

    function testCreateOrder_MPH_Referral() public {
        Account memory trader = makeAccount("trader");
        Account memory beneficiary = makeAccount("beneficiary");

        uint256 openAmount = 100 * 1e18; // 100 MPH
        bytes32 marketId = keccak256("CRYPTO_BTC");
        uint256 leverage = 2 * PRECISION;

        // Trader needs MPH
        morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(this));
        morpherToken.mint(trader.addr, openAmount);
        morpherAccessControl.revokeRole(morpherToken.MINTER_ROLE(), address(this));

        // Trader approves MRO to spend MPH for the TradeEngine's escrow/burn
        vm.prank(trader.addr);
        morpherToken.approve(address(morpherReferralOracle), openAmount);
        // MRO will need to approve MTE, or MTE pulls directly if MRO is msg.sender for MTE's escrow.
        // For simplicity, assume MTE's requestOrderId handles the escrow from trader via MRO.
        // The current MRO.createOrder does not take MPH itself, it expects MTE to handle it.
        // This needs MTE to be able to pull from trader.addr when MRO calls requestOrderId.
        // Let's adjust: MRO's createOrder should facilitate the token transfer or MTE needs to be aware.

        // The MRO's createOrder doesn't handle token transfers itself. It relies on MTE.
        // MTE's requestOrderId will try to use trader.addr as the source for escrow.
        // So, trader must approve MTE.
        vm.prank(trader.addr);
        morpherToken.approve(address(morpherTradeEngine), openAmount);


        MorpherReferralOracle.CreateOrderStruct memory params = MorpherReferralOracle.CreateOrderStruct({
            _marketId: marketId,
            _closeSharesAmount: 0,
            _openMPHTokenAmount: openAmount,
            _tradeDirection: true, // Long
            _orderLeverage: leverage,
            _onlyIfPriceAbove: 0,
            _onlyIfPriceBelow: 0,
            _goodUntil: 0,
            _goodFrom: 0
        });

        vm.prank(trader.addr);
        vm.expectEmit(true, true, true, true, address(morpherReferralOracle));
        emit ReferralOrderCreated(bytes32(0), trader.addr, beneficiary.addr, marketId, openAmount, true, leverage); // orderId is dynamic

        bytes32 orderId = morpherReferralOracle.createOrder(params, beneficiary.addr);
        assertTrue(orderId != 0, "Order ID should not be zero");

        assertEq(morpherReferralOracle.pendingOrderToBeneficiary(orderId), beneficiary.addr, "Beneficiary not set");
        assertTrue(morpherTradeEngine.isReferredOrder(orderId), "Order not marked as referred in MTE");
    }

    function testCreateOrder_GasToken_Referral() public {
        Account memory trader = makeAccount("trader");
        Account memory beneficiary = makeAccount("beneficiary");

        uint256 minMPHAmount = 95 * 1e18; // Expect at least 95 MPH
        uint256 ethToSend = 0.1 ether;
        bytes32 marketId = keccak256("STK_AAPL");
        uint256 leverage = 5 * PRECISION;

        vm.deal(trader.addr, ethToSend); // Give trader ETH

        MorpherReferralOracle.CreateOrderStruct memory params = MorpherReferralOracle.CreateOrderStruct({
            _marketId: marketId,
            _closeSharesAmount: 0,
            _openMPHTokenAmount: minMPHAmount, // This is min MPH out for the swap
            _tradeDirection: false, // Short
            _orderLeverage: leverage,
            _onlyIfPriceAbove: 0,
            _onlyIfPriceBelow: 0,
            _goodUntil: 0,
            _goodFrom: 0
        });

        // Mock Uniswap Router to return slightly more than minMPHAmount
        MockUniswapRouter(morpherReferralOracle.uniswapRouter()).mockAmountOut = 100 * 1e18;

        vm.prank(trader.addr);
        // OrderId is dynamic, openMPHTokenAmount in event will be actual swapped amount
        vm.expectEmit(true, true, true, true, address(morpherReferralOracle));
        emit ReferralOrderCreated(bytes32(0), trader.addr, beneficiary.addr, marketId, 100 * 1e18, false, leverage);

        bytes32 orderId = morpherReferralOracle.createOrderFromGasToken{value: ethToSend}(params, beneficiary.addr);
        assertTrue(orderId != 0, "Order ID should not be zero");

        assertEq(morpherReferralOracle.pendingOrderToBeneficiary(orderId), beneficiary.addr, "Beneficiary not set for gas token order");
        assertTrue(morpherTradeEngine.isReferredOrder(orderId), "Gas token order not marked as referred in MTE");

        // Check MRO has no WETH left and MTE has allowance for the MPH
        assertEq(WETH_MOCK.balanceOf(address(morpherReferralOracle)), 0);
        assertEq(morpherToken.allowance(address(morpherReferralOracle), address(morpherTradeEngine)), 100 * 1e18);
    }


    function testReferral_Open_Process_Close_WithLoss() public {
        Account memory trader = makeAccount("trader");
        Account memory beneficiary = makeAccount("beneficiary");
        bytes32 marketId = keccak256("FX_EURUSD");
        uint256 initialInvestmentMPH = 1000 * 1e18; // Cost to open the position

        // 1. Simulate order creation (not testing MRO.createOrder here, direct setup)
        bytes32 orderId = keccak256(abi.encodePacked("test_order_loss"));
        morpherReferralOracle.setPendingOrderToBeneficiary(orderId, beneficiary.addr); // Helper for test

        // 2. MTE calls recordReferralOpen
        vm.prank(address(morpherTradeEngine)); // Simulate call from MTE
        vm.expectEmit(true, true, true, true, address(morpherReferralOracle));
        emit ReferralOpenDetailsStored(trader.addr, marketId, beneficiary.addr, initialInvestmentMPH);
        morpherReferralOracle.recordReferralOpen(orderId, trader.addr, marketId, initialInvestmentMPH);

        assertEq(morpherReferralOracle.activeReferrals(trader.addr, marketId).beneficiary, beneficiary.addr);
        assertEq(morpherReferralOracle.activeReferrals(trader.addr, marketId).initialInvestmentValue, initialInvestmentMPH);
        assertEq(morpherReferralOracle.pendingOrderToBeneficiary(orderId), address(0)); // Should be cleared

        // 3. MTE calls processReferralClose after position closes with a loss
        uint256 finalPayoutValue = 600 * 1e18; // Trader got back 600 MPH from 1000 MPH investment
        uint256 expectedLoss = initialInvestmentMPH - finalPayoutValue; // 400 MPH
        uint256 expectedBonus = (expectedLoss * INITIAL_REFERRAL_PERCENTAGE) / REFERRAL_PERCENTAGE_PRECISION; // 10% of 400 = 40 MPH

        uint256 beneficiaryBalanceBefore = morpherToken.balanceOf(beneficiary.addr);

        vm.prank(address(morpherTradeEngine)); // Simulate call from MTE
        vm.expectEmit(true, true, true, true, address(morpherReferralOracle));
        emit ReferralBonusPaid(trader.addr, marketId, beneficiary.addr, expectedLoss, expectedBonus);
        // Also expect MPH mint event
        vm.expectEmit(true, true, false, true, address(morpherToken)); // from, to, value (ignore from as it's complex with roles)
        emit Transfer(address(0), beneficiary.addr, expectedBonus); // Mint event

        morpherReferralOracle.processReferralClose(trader.addr, marketId, finalPayoutValue);

        assertEq(morpherReferralOracle.activeReferrals(trader.addr, marketId).beneficiary, address(0)); // Should be cleared
        uint256 beneficiaryBalanceAfter = morpherToken.balanceOf(beneficiary.addr);
        assertEq(beneficiaryBalanceAfter, beneficiaryBalanceBefore + expectedBonus, "Beneficiary bonus incorrect");
    }

    function testReferral_Process_Close_WithProfit() public {
        Account memory trader = makeAccount("trader");
        Account memory beneficiary = makeAccount("beneficiary");
        bytes32 marketId = keccak256("COMM_GOLD");
        uint256 initialInvestmentMPH = 500 * 1e18;

        bytes32 orderId = keccak256(abi.encodePacked("test_order_profit"));
        morpherReferralOracle.setPendingOrderToBeneficiary(orderId, beneficiary.addr);

        vm.prank(address(morpherTradeEngine));
        morpherReferralOracle.recordReferralOpen(orderId, trader.addr, marketId, initialInvestmentMPH);

        // Position closes with profit
        uint256 finalPayoutValue = 700 * 1e18; // Trader got back 700 MPH (profit)
        uint256 beneficiaryBalanceBefore = morpherToken.balanceOf(beneficiary.addr);

        // No ReferralBonusPaid event expected
        vm.prank(address(morpherTradeEngine));
        morpherReferralOracle.processReferralClose(trader.addr, marketId, finalPayoutValue);

        assertEq(morpherReferralOracle.activeReferrals(trader.addr, marketId).beneficiary, address(0));
        uint256 beneficiaryBalanceAfter = morpherToken.balanceOf(beneficiary.addr);
        assertEq(beneficiaryBalanceAfter, beneficiaryBalanceBefore, "Beneficiary should not receive bonus on profit");
    }

    function testMRO_Callback() public {
        Account memory trader = makeAccount("trader");
        Account memory beneficiary = makeAccount("beneficiary");
        bytes32 marketId = keccak256("CRYPTO_ETH");
        uint256 openAmount = 200 * 1e18;
        uint256 leverage = 3 * PRECISION;

        // Trader approves MTE
        vm.prank(trader.addr);
        morpherToken.approve(address(morpherTradeEngine), openAmount);
        morpherAccessControl.grantRole(morpherToken.MINTER_ROLE(), address(this));
        morpherToken.mint(trader.addr, openAmount);
        morpherAccessControl.revokeRole(morpherToken.MINTER_ROLE(), address(this));


        // 1. Create order via MRO (simplified: directly get orderId from MTE for test)
        vm.prank(address(morpherReferralOracle)); // MRO calls MTE
        bytes32 orderId = morpherTradeEngine.requestOrderId(trader.addr, marketId, 0, openAmount, true, leverage);
        morpherReferralOracle.setPendingOrderToBeneficiary(orderId, beneficiary.addr); // Manually set for test
        vm.prank(address(morpherReferralOracle)); // MRO calls MTE
        morpherTradeEngine.markOrderAsReferred(orderId);


        // 2. Simulate Oracle Operator calling MRO's __callback
        uint256 price = 3000 * PRECISION;
        uint256 spread = 5 * PRECISION;
        uint256 liquidationTimestamp = 0; // No prior liquidation
        uint256 priceTimestamp = block.timestamp * 1000;

        // Expect MRO to emit ReferralOrderProcessed
        // Expect MTE to emit OrderProcessed (called internally by MRO's callback via MTE.processOrder)
        // Expect MTE to emit PositionUpdated (also internal to MTE.processOrder)
        // Expect MRO to call MTE.processOrder
        // Expect MRO to call MTE.recordReferralOpen (from MTE.setPositionInState)

        vm.expectEmit(true, true, true, true, address(morpherReferralOracle));
        emit ReferralOrderProcessed(orderId, price, price, spread, liquidationTimestamp, priceTimestamp, 0,0,0,0,0,0); // Shares/etc are dynamic

        vm.expectEmit(true, true, true, true, address(morpherTradeEngine)); // MTE.OrderProcessed
        emit OrderProcessed(orderId, price, spread, liquidationTimestamp, priceTimestamp,0,0,0,0,0,0); // Shares/etc are dynamic

        vm.expectEmit(true, true, true, true, address(morpherReferralOracle)); // MRO.ReferralOpenDetailsStored
        emit ReferralOpenDetailsStored(trader.addr, marketId, beneficiary.addr, 0); // initialInvestmentValue is dynamic

        // Callback is from this test contract (granted ORACLEOPERATOR_ROLE)
        morpherReferralOracle.__callback(orderId, price, price, spread, liquidationTimestamp, priceTimestamp);

        // Verify referral details were stored
        assertTrue(morpherReferralOracle.activeReferrals(trader.addr, marketId).initialInvestmentValue > 0, "Initial investment not stored");
        assertEq(morpherReferralOracle.activeReferrals(trader.addr, marketId).beneficiary, beneficiary.addr);
    }

    // Admin functions tests
    function testSetReferralPercentage() public {
        uint256 newPercentage = 1500; // 15%
        vm.expectEmit(true, true, true, true, address(morpherReferralOracle));
        emit ReferralAdminSet(address(this), address(morpherReferralOracle), "ReferralPercentage", newPercentage);
        morpherReferralOracle.setReferralPercentage(newPercentage);
        assertEq(morpherReferralOracle.referralPercentage(), newPercentage);

        // Test revert if too high
        vm.expectRevert("MRO: Percentage too high");
        morpherReferralOracle.setReferralPercentage(REFERRAL_PERCENTAGE_PRECISION + 1);
    }

    // Pausable tests
    function testPauseUnpause() public {
        assertTrue(!morpherReferralOracle.paused(), "Should not be paused initially");
        vm.expectEmit(true, false, false, true, address(morpherReferralOracle)); // Paused event
        emit Paused(address(this));
        morpherReferralOracle.pause();
        assertTrue(morpherReferralOracle.paused(), "Should be paused");

        // Attempt to call a whenNotPaused function
        MorpherReferralOracle.CreateOrderStruct memory params; // Dummy params
        vm.expectRevert("Pausable: paused");
        morpherReferralOracle.createOrder(params, makeAccount("beneficiary_pause").addr);

        vm.expectEmit(true, false, false, true, address(morpherReferralOracle)); // Unpaused event
        emit Unpaused(address(this));
        morpherReferralOracle.unpause();
        assertTrue(!morpherReferralOracle.paused(), "Should be unpaused");
    }


    // Helper to set pendingOrderToBeneficiary for tests that don't go through createOrder
    function setPendingOrderToBeneficiary(bytes32 orderId, address beneficiary) internal {
        // This function needs to be callable by the test contract.
        // For a real contract, this would be internal or access controlled.
        // Here, we make it public for test setup ease.
        // In a real scenario, you might need a more complex setup or friend contract pattern.
        // Or, test the full flow starting from createOrder.
        // For now, let's assume we can call this from the test.
        // This requires adding it to MorpherReferralOracle.sol or using vm.store/vm.etch.
        // Let's add a public setter in MRO for testing purposes only, or use vm.store.
        // Using vm.store is cleaner for tests.
        // The mapping `pendingOrderToBeneficiary` itself is at slot index 6.
        bytes32 mappingSlot = bytes32(uint256(6)); 
        bytes32 storageSlotForKey = keccak256(abi.encode(orderId, mappingSlot)); // Compute storage slot for the key within the mapping
        vm.store(address(morpherReferralOracle), storageSlotForKey, bytes32(uint256(uint160(beneficiary))));
    }
}