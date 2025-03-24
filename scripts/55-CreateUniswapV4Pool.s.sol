//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {DeployOrUpgrade} from "./deployOrUpgrade.sol";
import {MorpherToken} from "../contracts/MorpherToken.sol";

// Uniswap v4 imports
import {PositionManager} from "../lib/v4-periphery/src/PositionManager.sol";
import {PoolKey} from "../lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import {IHooks} from "../lib/v4-periphery/lib/v4-core/src/interfaces/IHooks.sol";
import {CurrencyLibrary, Currency} from "../lib/v4-periphery/lib/v4-core/src/types/Currency.sol";
import {Actions} from "../lib/v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "../lib/v4-periphery/lib/v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "../lib/v4-core/src/libraries/TickMath.sol";
import {IPermit2} from "../lib/permit2/src/interfaces/IPermit2.sol";

contract CreateUniswapV4Pool is DeployOrUpgrade {
    using stdJson for string;
    using CurrencyLibrary for Currency;

    // Uniswap V4 addresses - will be set based on chainId
    address public POOL_MANAGER;
    address public POSITION_MANAGER;
    address public PERMIT2;
    address public WETH;
    IHooks public HOOKS; // No hooks for this example
    
    // Pool configuration
    uint24 constant FEE = 3000; // 0.3%
    int24 constant TICK_SPACING = 60; // For 0.3% fee
    
    // Liquidity position configuration
    uint256 public ethAmount = 1 ether;
    uint256 public mphAmount = 100000 ether; // 100,000 MPH tokens
    int24 public tickLower = -840000; // Must be a multiple of tickSpacing
    int24 public tickUpper = 840000;

    // Set up addresses based on the chain we're deploying to
    function setupAddresses() internal {
        uint256 chainId = block.chainid;
    
        // WETH is the same on both Base and Base Sepolia
        WETH = 0x4200000000000000000000000000000000000006;
        HOOKS = IHooks(address(0)); // No hooks for this example
    
        if (chainId == 8453) {
            // Base Mainnet
            POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
            POSITION_MANAGER = 0x7C5f5A4bBd8fD63184577525326123B519429bDc;
            PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // Standard permit2 address
        } else if (chainId == 84532) {
            // Base Sepolia
            POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
            POSITION_MANAGER = 0x4B2C77d209D3405F41a037Ec6c77F7F5b8e2ca80;
            PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // Standard permit2 address
        } else {
            revert("Unsupported chain ID");
        }
    }

    function run() public {
        // Set up the correct addresses based on the chain
        setupAddresses();
        
        vm.startBroadcast();

        console.log("Deploying Uniswap v4 pool on chain ID:", uint256(block.chainid));
        console.log("Using Pool Manager:", POOL_MANAGER);
        console.log("Using Position Manager:", POSITION_MANAGER);
        
        // Load MorpherToken address
        address morpherTokenAddress = loadAddress("MorpherToken");
        require(morpherTokenAddress != address(0), "MorpherToken must be deployed first");
        
        console.log("MorpherToken address:", morpherTokenAddress);
        console.log("WETH address:", WETH);

        // Create pool and add liquidity
        createPoolAndAddLiquidity(morpherTokenAddress);
        
        vm.stopBroadcast();
    }
    
    // Create pool and add liquidity in one transaction using multicall
    function createPoolAndAddLiquidity(address morpherTokenAddress) internal {
        // Ensure ticks are multiples of tickSpacing
        tickLower = (tickLower / TICK_SPACING) * TICK_SPACING;
        tickUpper = (tickUpper / TICK_SPACING) * TICK_SPACING;
        
        // Ensure ticks are within valid range
        if (tickLower < TickMath.MIN_TICK) tickLower = TickMath.MIN_TICK;
        if (tickUpper > TickMath.MAX_TICK) tickUpper = TickMath.MAX_TICK;
        
        // Create currency objects
        Currency currency0;
        Currency currency1;
        
        // Sort tokens
        if (morpherTokenAddress < WETH) {
            currency0 = Currency.wrap(morpherTokenAddress);
            currency1 = Currency.wrap(WETH);
        } else {
            currency0 = Currency.wrap(WETH);
            currency1 = Currency.wrap(morpherTokenAddress);
        }
        
        // Configure the pool
        PoolKey memory pool = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOKS
        });
        
        console.log("Pool configuration:");
        console.log("- Currency0:", Currency.unwrap(currency0));
        console.log("- Currency1:", Currency.unwrap(currency1));
        console.log("- Fee:", pool.fee);
        console.log("- TickSpacing:", pool.tickSpacing);
        console.log("- Tick range: %d", int(tickLower));
        
        // Calculate starting price (100,000 MPH per 1 WETH)
        uint160 startingPrice;
        if (Currency.unwrap(currency0) == morpherTokenAddress) {
            // If MPH is token0, price = WETH/MPH = 1/100000 = 0.00001
            // sqrt(0.00001) * 2^96
            startingPrice = 250541448375048000000000000;
            console.log("MPH is token0, WETH is token1");
        } else {
            // If MPH is token1, price = MPH/WETH = 100000
            // sqrt(100000) * 2^96
            startingPrice = 25054144837504800000000000000000;
            console.log("WETH is token0, MPH is token1");
        }
        console.log("Setting price: 100,000 MPH per 1 WETH");
        
        // Calculate liquidity amount
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            Currency.unwrap(currency0) == morpherTokenAddress ? mphAmount : ethAmount,
            Currency.unwrap(currency0) == morpherTokenAddress ? ethAmount : mphAmount
        );
        
        console.log("Calculated liquidity:", uint256(liquidity));
        
        // Prepare for multicall
        bytes[] memory params = new bytes[](2);
        
        // Initialize pool
        bytes memory hookData = new bytes(0);
        params[0] = abi.encodeWithSelector(
            PositionManager(payable(POSITION_MANAGER)).initializePool.selector,
            pool,
            startingPrice,
            hookData
        );
        
        // Prepare mint liquidity parameters
        (bytes memory actions, bytes[] memory mintParams) = _mintLiquidityParams(
            pool,
            tickLower,
            tickUpper,
            liquidity,
            Currency.unwrap(currency0) == morpherTokenAddress ? mphAmount + 1 : ethAmount + 1,
            Currency.unwrap(currency0) == morpherTokenAddress ? ethAmount + 1 : mphAmount + 1,
            msg.sender,
            hookData
        );
        
        // Encode modifyLiquidities call
        params[1] = abi.encodeWithSelector(
            PositionManager(payable(POSITION_MANAGER)).modifyLiquidities.selector,
            abi.encode(actions, mintParams),
            block.timestamp + 60
        );
        
        // Approve tokens
        tokenApprovals(morpherTokenAddress);
        
        // Determine if we need to send ETH with the call
        uint256 valueToSend = 0;
        if (currency0.isAddressZero()) {
            valueToSend = ethAmount + 1;
        }
        
        // Execute the multicall
        try PositionManager(payable(POSITION_MANAGER)).multicall{value: valueToSend}(params) returns (bytes[] memory results) {
            console.log("Pool created and liquidity added successfully");
            
            // Save the pool information
            saveAddress("UniswapV4PoolManager", POOL_MANAGER);
            
            // Log the pool key information for reference
            console.log("Pool created with the following key:");
            console.log("- Currency0:", Currency.unwrap(pool.currency0));
            console.log("- Currency1:", Currency.unwrap(pool.currency1));
            console.log("- Fee:", pool.fee);
            console.log("- TickSpacing:", pool.tickSpacing);
            
        } catch Error(string memory reason) {
            console.log("Failed to create pool and add liquidity: %s", reason);
            
        } catch {
            console.log("Failed to create pool and add liquidity: unknown error");
            
        }
        
    }
    
    /// @dev Helper function for encoding mint liquidity operation
    function _mintLiquidityParams(
        PoolKey memory poolKey,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 liquidity,
        uint256 amount0Max,
        uint256 amount1Max,
        address recipient,
        bytes memory hookData
    ) internal pure returns (bytes memory, bytes[] memory) {
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));
        
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(poolKey, _tickLower, _tickUpper, liquidity, amount0Max, amount1Max, recipient, hookData);
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
        
        return (actions, params);
    }
    
    /// @dev Approve tokens for the position manager
    function tokenApprovals(address morpherTokenAddress) internal {
        // Ensure we have enough WETH
        uint256 wethBalance = IERC20(WETH).balanceOf(msg.sender);
        if (wethBalance < ethAmount) {
            console.log("Not enough WETH, depositing ETH...");
            (bool success,) = WETH.call{value: ethAmount}("");
            require(success, "ETH deposit failed");
        }
        
        // Approve tokens for Permit2
        IERC20(WETH).approve(PERMIT2, type(uint256).max);
        IERC20(morpherTokenAddress).approve(PERMIT2, type(uint256).max);
        
        // Approve Position Manager via Permit2
        IPermit2(PERMIT2).approve(WETH, POSITION_MANAGER, type(uint160).max, type(uint48).max);
        IPermit2(PERMIT2).approve(morpherTokenAddress, POSITION_MANAGER, type(uint160).max, type(uint48).max);
        
        console.log("Tokens approved for Position Manager");
    }
}
