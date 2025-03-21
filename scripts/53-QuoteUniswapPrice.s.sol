//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {DeployOrUpgrade} from "./deployOrUpgrade.sol";
import {MorpherToken} from "../contracts/MorpherToken.sol";
import {TickMath} from "../lib/uniswap-v3-core/contracts/libraries/TickMath.sol";

// Uniswap interfaces
interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IUniswapV3Pool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    );
    function fee() external view returns (uint24);
}

interface IWETH9 {
    function balanceOf(address account) external view returns (uint256);
}

contract QuoteUniswapPrice is DeployOrUpgrade {
    using stdJson for string;

    // Uniswap V3 addresses - will be set based on chainId
    address public UNISWAP_V3_FACTORY;
    address public WETH;
    uint24 constant FEE = 3000; // 0.3%
    
    // Set up addresses based on the chain we're querying
    function setupAddresses() internal {
        uint256 chainId = block.chainid;
    
        // WETH is the same on both Base and Base Sepolia
        WETH = 0x4200000000000000000000000000000000000006;
    
        if (chainId == 8453) {
            // Base Mainnet
            UNISWAP_V3_FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
        } else if (chainId == 84532) {
            // Base Sepolia
            UNISWAP_V3_FACTORY = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
        } else {
            revert("Unsupported chain ID");
        }
    }

    function run() public view {
        // Set up the correct addresses based on the chain
        setupAddresses();

        console.log("Quoting Uniswap price on chain ID:", uint256(block.chainid));
        
        // Load MorpherToken address
        address morpherTokenAddress = loadAddress("MorpherToken");
        require(morpherTokenAddress != address(0), "MorpherToken must be deployed first");
        
        console.log("MorpherToken address:", morpherTokenAddress);
        console.log("WETH address:", WETH);

        // Get the pool address
        address poolAddress = getPoolAddress(morpherTokenAddress);
        console.log("Pool address:", poolAddress);
        
        // Get current price
        quotePrice(poolAddress, morpherTokenAddress);
    }
    
    // Get the pool address
    function getPoolAddress(address morpherTokenAddress) internal view returns (address) {
        IUniswapV3Factory factory = IUniswapV3Factory(UNISWAP_V3_FACTORY);
        address poolAddress = factory.getPool(morpherTokenAddress, WETH, FEE);
        require(poolAddress != address(0), "Pool does not exist");
        return poolAddress;
    }
    
    // Quote the current price
    function quotePrice(address poolAddress, address morpherTokenAddress) internal view {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = pool.slot0();
        
        address token0 = pool.token0();
        address token1 = pool.token1();
        
        console.log("Current pool state:");
        console.log("- Token0:", token0);
        console.log("- Token1:", token1);
        console.log("- Tick:", tick);
        console.log("- SqrtPriceX96:", uint256(sqrtPriceX96));
        
        // Calculate the price of 0.1 WETH in MPH
        uint256 wethAmount = 0.1 ether;
        uint256 mphAmount;
        
        if (token0 == WETH) {
            // WETH is token0, MPH is token1
            // Price = MPH/WETH
            
            // Calculate price from sqrtPriceX96
            // price = (sqrtPriceX96/2^96)^2
            uint256 price = calculatePrice(sqrtPriceX96);
            
            // Calculate MPH amount for 0.1 WETH
            mphAmount = (price * wethAmount) / 1e18;
            
            console.log("Price calculation:");
            console.log("- Raw price (MPH per WETH):", price / 1e18);
            console.log("- 0.1 WETH = %d MPH", mphAmount / 1e18);
        } else {
            // MPH is token0, WETH is token1
            // Price = WETH/MPH
            
            // Calculate price from sqrtPriceX96
            // price = (2^96/sqrtPriceX96)^2
            uint256 price = calculateInversePrice(sqrtPriceX96);
            
            // Calculate MPH amount for 0.1 WETH
            mphAmount = (wethAmount * 1e18) / price;
            
            console.log("Price calculation:");
            console.log("- Raw price (WETH per MPH):", price / 1e18);
            console.log("- Inverted (MPH per WETH):", (1e36 / price) / 1e18);
            console.log("- 0.1 WETH = %d MPH", mphAmount / 1e18);
        }
        
        // Also calculate from tick for verification
        int24 targetTick = (token0 == WETH) ? 11513 : -11513; // Target tick for 100,000 MPH per WETH
        console.log("Target price reference:");
        console.log("- Target tick for 100,000 MPH per WETH: 11513 (or -11513 if MPH is token0)");
        console.log("- Current tick: %d", tick);
        console.log("- Tick difference from target: %d", targetTick - tick);
        
        // Calculate approximate price from tick
        uint256 tickPrice = approximatePriceFromTick(tick, token0 == WETH);
        console.log("- Approximate price from tick: ~%d MPH per WETH", tickPrice);
        console.log("- 0.1 WETH ≈ %d MPH (from tick)", (tickPrice * wethAmount / 1e18) / 1e18);
    }
    
    // Calculate price from sqrtPriceX96 (when WETH is token0)
    function calculatePrice(uint160 sqrtPriceX96) internal pure returns (uint256) {
        // Formula: price = (sqrtPriceX96^2) / 2^192
        uint256 sqrtPriceSquared = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        
        // Avoid overflow by using multiple steps
        uint256 divisor = 1 << 64; // 2^64
        uint256 intermediate = sqrtPriceSquared / divisor; // Divide by 2^64
        intermediate = intermediate / divisor; // Divide by 2^64 again
        uint256 price = intermediate / divisor; // Divide by 2^64 a third time (total division by 2^192)
        
        // Convert to a more readable format (18 decimals)
        return price * 1e18;
    }
    
    // Calculate inverse price from sqrtPriceX96 (when MPH is token0)
    function calculateInversePrice(uint160 sqrtPriceX96) internal pure returns (uint256) {
        // Formula: price = 2^192 / (sqrtPriceX96^2)
        
        // First calculate 2^96 / sqrtPriceX96
        uint256 divisor = uint256(sqrtPriceX96);
        uint256 dividend = 1;
        for (uint8 i = 0; i < 96; i++) {
            dividend *= 2;
        }
        
        uint256 intermediate = (dividend * 1e18) / divisor;
        
        // Then square it and multiply by 1e18 for 18 decimals
        return intermediate * intermediate / 1e18;
    }
    
    // Approximate price from tick
    function approximatePriceFromTick(int24 tick, bool wethIsToken0) internal pure returns (uint256) {
        // For Uniswap V3, price = 1.0001^tick
        // We'll use a rough approximation based on the tick value
        
        if (wethIsToken0) {
            // WETH is token0, price is MPH per WETH
            if (tick < 0) {
                // For negative tick, price < 1
                return 1; // Very small price
            } else {
                // For positive tick, price > 1
                // Rough approximation: 1.0001^tick ≈ 2^(tick/6932)
                uint256 approxPower = uint256(int256(tick)) / 6932;
                if (approxPower > 30) return 1e9; // Cap at a billion to avoid overflow
                return uint256(1) << approxPower;
            }
        } else {
            // MPH is token0, price is WETH per MPH, we need to invert
            if (tick < 0) {
                // For negative tick, WETH/MPH < 1, so MPH/WETH > 1
                // Rough approximation: 1.0001^(-tick) ≈ 2^(-tick/6932)
                uint256 approxPower = uint256(int256(-tick)) / 6932;
                if (approxPower > 30) return 1e9; // Cap at a billion to avoid overflow
                return uint256(1) << approxPower;
            } else {
                // For positive tick, WETH/MPH > 1, so MPH/WETH < 1
                return 1; // Very small price
            }
        }
    }
}
