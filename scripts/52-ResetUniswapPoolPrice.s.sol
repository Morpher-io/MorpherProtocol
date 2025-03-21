//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {DeployOrUpgrade} from "./deployOrUpgrade.sol";
import {MorpherToken} from "../contracts/MorpherToken.sol";
import {INonfungiblePositionManager} from "../lib/uniswap-v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {ISwapRouter} from "../lib/uniswap-v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {TickMath} from "../lib/uniswap-v3-core/contracts/libraries/TickMath.sol";

// Uniswap interfaces
interface IUniswapV3Factory {
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IUniswapV3Pool {
    function initialize(uint160 sqrtPriceX96) external;
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
    function deposit() external payable;
    function withdraw(uint wad) external;
    function approve(address guy, uint wad) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address dst, uint wad) external returns (bool);
}

contract ResetUniswapPoolPrice is DeployOrUpgrade {
    using stdJson for string;

    // Uniswap V3 addresses - will be set based on chainId
    address public UNISWAP_V3_FACTORY;
    address public NONFUNGIBLE_POSITION_MANAGER;
    address public SWAP_ROUTER;
    address public WETH;
    uint24 constant FEE = 3000; // 0.3%
    
    // Target price: 10,000 MPH = 0.1 WETH (ratio 100,000:1)
    uint256 constant TARGET_MPH_PER_WETH = 100000;

    // Set up addresses based on the chain we're deploying to
    function setupAddresses() internal {
        uint256 chainId = block.chainid;
    
        // WETH is the same on both Base and Base Sepolia
        WETH = 0x4200000000000000000000000000000000000006;
    
        if (chainId == 8453) {
            // Base Mainnet
            UNISWAP_V3_FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
            NONFUNGIBLE_POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
            SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
        } else if (chainId == 84532) {
            // Base Sepolia
            UNISWAP_V3_FACTORY = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
            NONFUNGIBLE_POSITION_MANAGER = 0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2;
            SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
        } else {
            revert("Unsupported chain ID");
        }
    }

    function run() public {
        // Set up the correct addresses based on the chain
        setupAddresses();
        
        vm.startBroadcast();

        console.log("Resetting Uniswap pool price on chain ID:", uint256(block.chainid));
        
        // Load MorpherToken address
        address morpherTokenAddress = loadAddress("MorpherToken");
        require(morpherTokenAddress != address(0), "MorpherToken must be deployed first");
        
        console.log("MorpherToken address:", morpherTokenAddress);
        console.log("WETH address:", WETH);

        // Get the pool address
        address poolAddress = getPoolAddress(morpherTokenAddress);
        console.log("Pool address:", poolAddress);
        
        // Check current price
        checkCurrentPrice(poolAddress);
        
        // Reduce liquidity in existing positions to make price adjustment easier
        removeAllLiquidity();
        
        // Perform swap to adjust price
        adjustPriceWithSwap(poolAddress, morpherTokenAddress);
        
        // Check new price after swap
        checkCurrentPrice(poolAddress);
        
        // Add liquidity back at the new price
        addLiquidityToPool(poolAddress, morpherTokenAddress);
        
        vm.stopBroadcast();
    }
    
    // Get the pool address
    function getPoolAddress(address morpherTokenAddress) internal view returns (address) {
        IUniswapV3Factory factory = IUniswapV3Factory(UNISWAP_V3_FACTORY);
        address poolAddress = factory.getPool(morpherTokenAddress, WETH, FEE);
        require(poolAddress != address(0), "Pool does not exist");
        return poolAddress;
    }
    
    // Check and display the current price
    function checkCurrentPrice(address poolAddress) internal view {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = pool.slot0();
        
        address token0 = pool.token0();
        address token1 = pool.token1();
        
        console.log("Current pool state:");
        console.log("- Token0:", token0);
        console.log("- Token1:", token1);
        console.log("- Tick:", tick);
        console.log("- SqrtPriceX96:", uint256(sqrtPriceX96));
        
        // Calculate and display the price with more detailed logging
        if (token0 == WETH) {
            // WETH is token0, MPH is token1
            // Price is MPH per WETH
            uint256 price = 0;
            if (sqrtPriceX96 > 0) {
                // Formula: price = (sqrtPriceX96^2) / 2^192 * 10^18
                uint256 sqrtPriceSquared = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
                console.log("- SqrtPrice squared:", sqrtPriceSquared);
                
                // Avoid overflow by using two steps
                uint256 shiftedPrice = sqrtPriceSquared / (1 << 96); // Divide by 2^96
                price = (shiftedPrice * 1e18) / (1 << 96); // Multiply by 10^18 and divide by 2^96 again
            }
            console.log("- Current price: %d MPH per WETH", price / 1e18);
            console.log("- Raw price value:", price);
        } else {
            // MPH is token0, WETH is token1
            // Price is WETH per MPH
            uint256 wethPerMph = 0;
            uint256 mphPerWeth = 0;
            
            if (sqrtPriceX96 > 0) {
                // Formula: price = 2^192 / (sqrtPriceX96^2) * 10^18
                uint256 sqrtPriceSquared = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
                console.log("- SqrtPrice squared:", sqrtPriceSquared);
                
                if (sqrtPriceSquared > 0) {
                    // Calculate WETH per MPH (direct price)
                    uint256 factor = 1;
                    uint256 divisor = 1;
                    
                    // Handle calculation in parts to avoid overflow
                    factor = (1 << 96); // 2^96
                    wethPerMph = (factor * 1e18) / sqrtPriceSquared;
                    factor = (1 << 96); // 2^96
                    wethPerMph = (wethPerMph * factor) / (1 << 32); // Adjust by multiplying by 2^(96-32)
                    
                    // Calculate MPH per WETH (inverted price)
                    if (wethPerMph > 0) {
                        mphPerWeth = (1e36 / wethPerMph);
                    }
                }
            }
            
            console.log("- Current price: %d WETH per MPH", wethPerMph / 1e18);
            console.log("- Raw WETH per MPH:", wethPerMph);
            console.log("- Inverted: %d MPH per WETH", mphPerWeth / 1e18);
            console.log("- Raw MPH per WETH:", mphPerWeth);
        }
    }
    
    // Reduce liquidity in existing positions to a minimal amount
    function removeAllLiquidity() internal {
        INonfungiblePositionManager posManager = INonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER);
        
        // Get the balance of NFTs for this address
        uint256 balance = posManager.balanceOf(msg.sender);
        console.log("Found existing positions:", balance);
        
        // Loop through and reduce liquidity from all positions
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = posManager.tokenOfOwnerByIndex(msg.sender, i);
            console.log("Reducing liquidity from position with token ID:", tokenId);
            
            // Get position details
            (
                ,
                ,
                address token0,
                address token1,
                ,
                ,
                ,
                uint128 liquidity,
                ,
                ,
                ,
            ) = posManager.positions(tokenId);
            
            console.log("Position details:");
            console.log("- Token0:", token0);
            console.log("- Token1:", token1);
            console.log("- Liquidity:", uint256(liquidity));
            
            if (liquidity > 0) {
                // Calculate how much liquidity to remove (99.9%)
                uint128 liquidityToRemove = uint128((uint256(liquidity) * 9) / 10);
                
                // Decrease liquidity but leave a tiny amount
                console.log("Decreasing liquidity to 10% of original...");
                console.log("- Original liquidity:", uint256(liquidity));
                console.log("- Liquidity to remove:", uint256(liquidityToRemove));
                console.log("- Liquidity to keep:", uint256(liquidity) - uint256(liquidityToRemove));
                
                (uint256 amount0, uint256 amount1) = posManager.decreaseLiquidity(
                    INonfungiblePositionManager.DecreaseLiquidityParams({
                        tokenId: tokenId,
                        liquidity: liquidityToRemove,
                        amount0Min: 0,
                        amount1Min: 0,
                        deadline: block.timestamp + 15 minutes
                    })
                );
                
                console.log("Liquidity reduced:");
                console.log("- Amount token0 removed:", amount0);
                console.log("- Amount token1 removed:", amount1);
                
                // Collect the tokens
                console.log("Collecting tokens...");
                (uint256 collected0, uint256 collected1) = posManager.collect(
                    INonfungiblePositionManager.CollectParams({
                        tokenId: tokenId,
                        recipient: msg.sender,
                        amount0Max: type(uint128).max,
                        amount1Max: type(uint128).max
                    })
                );
                
                console.log("Tokens collected:");
                console.log("- Amount token0:", collected0);
                console.log("- Amount token1:", collected1);
            }
        }
    }
    
    // Adjust price with a swap
    function adjustPriceWithSwap(address poolAddress, address morpherTokenAddress) internal {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        address token0 = pool.token0();
        address token1 = pool.token1();
        uint24 fee = pool.fee();
        
        // Determine which token to swap based on current price vs target price
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = pool.slot0();
        
        console.log("Determining swap direction:");
        console.log("- Current tick:", tick);
        console.log("- Target MPH per WETH:", TARGET_MPH_PER_WETH);
        
        // For simplicity, let's use the tick directly to determine swap direction
        // The tick is related to the price by: price = 1.0001^tick
        // For our target of 100,000 MPH per WETH, the tick would be around 11513
        // (log base 1.0001 of 100,000)
        int24 targetTick = 11513;
        
        if (token0 == morpherTokenAddress) {
            // MPH is token0, WETH is token1
            // In this case, a higher tick means a higher WETH/MPH price (lower MPH/WETH)
            // So we need to invert our comparison
            targetTick = -targetTick;
            
            console.log("- MPH is token0, target tick (inverted):", targetTick);
            
            if (tick < targetTick) {
                // Current price has fewer MPH per WETH than target
                // Need to swap WETH for MPH to increase MPH per WETH
                console.log("- Current tick < target tick, swapping WETH for MPH");
                swapWethForMph(morpherTokenAddress, fee);
            } else {
                // Current price has more MPH per WETH than target
                // Need to swap MPH for WETH to decrease MPH per WETH
                console.log("- Current tick > target tick, swapping MPH for WETH");
                swapMphForWeth(morpherTokenAddress, fee);
            }
        } else {
            // WETH is token0, MPH is token1
            // In this case, a higher tick means a higher MPH/WETH price
            console.log("- WETH is token0, target tick:", targetTick);
            
            if (tick < targetTick) {
                // Current price has fewer MPH per WETH than target
                // Need to swap MPH for WETH to increase MPH per WETH
                console.log("- Current tick < target tick, swapping MPH for WETH");
                swapMphForWeth(morpherTokenAddress, fee);
            } else {
                // Current price has more MPH per WETH than target
                // Need to swap WETH for MPH to decrease MPH per WETH
                console.log("- Current tick > target tick, swapping WETH for MPH");
                swapWethForMph(morpherTokenAddress, fee);
            }
        }
    }
    
    // Swap WETH for MPH to adjust price
    function swapWethForMph(address morpherTokenAddress, uint24 fee) internal {
        console.log("Swapping WETH for MPH to adjust price...");
        
        // Use a larger amount to ensure a significant price impact
        uint256 wethAmount = 0.01 ether;
        
        // Ensure we have enough WETH
        uint256 wethBalance = IWETH9(WETH).balanceOf(msg.sender);
        if (wethBalance < wethAmount) {
            console.log("Not enough WETH, depositing ETH...");
            IWETH9(WETH).deposit{value: wethAmount}();
        }
        
        // Approve the router to spend WETH
        IWETH9(WETH).approve(SWAP_ROUTER, wethAmount);
        
        // Perform the swap
        ISwapRouter router = ISwapRouter(SWAP_ROUTER);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: morpherTokenAddress,
            fee: fee,
            recipient: msg.sender,
            deadline: block.timestamp + 15 minutes,
            amountIn: wethAmount,
            amountOutMinimum: 0, // No slippage protection for this purpose
            sqrtPriceLimitX96: 0 // No price limit
        });
        
        uint256 amountOut = router.exactInputSingle(params);
        console.log("Swap completed:");
        console.log("- WETH in:", wethAmount / 1e18);
        console.log("- MPH out:", amountOut / 1e18);
    }
    
    // Swap MPH for WETH to adjust price
    function swapMphForWeth(address morpherTokenAddress, uint24 fee) internal {
        console.log("Swapping MPH for WETH to adjust price...");
        
        // Use a larger amount to ensure a significant price impact
        uint256 mphAmount = 1000 ether; // 1000 MPH
        
        // Ensure we have enough MPH
        uint256 mphBalance = IERC20(morpherTokenAddress).balanceOf(msg.sender);
        if (mphBalance < mphAmount) {
            console.log("Not enough MPH, minting more...");
            // This assumes the caller has minting rights
            MorpherToken(morpherTokenAddress).mint(msg.sender, mphAmount);
        }
        
        // Approve the router to spend MPH
        IERC20(morpherTokenAddress).approve(SWAP_ROUTER, mphAmount);
        
        // Perform the swap
        ISwapRouter router = ISwapRouter(SWAP_ROUTER);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: morpherTokenAddress,
            tokenOut: WETH,
            fee: fee,
            recipient: msg.sender,
            deadline: block.timestamp + 15 minutes,
            amountIn: mphAmount,
            amountOutMinimum: 0, // No slippage protection for this purpose
            sqrtPriceLimitX96: 0 // No price limit
        });
        
        uint256 amountOut = router.exactInputSingle(params);
        console.log("Swap completed:");
        console.log("- MPH in:", mphAmount / 1e18);
        console.log("- WETH out:", amountOut / 1e18);
    }
    
    // Add liquidity back to the pool at the new price
    function addLiquidityToPool(address poolAddress, address morpherTokenAddress) internal {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        
        // Get token order
        address token0 = pool.token0();
        address token1 = pool.token1();
        
        // Get current price to determine the correct ratio
        (uint160 sqrtPriceX96, int24 currentTick, , , , , ) = pool.slot0();
        console.log("Current tick after swap:", currentTick);
        
        // Add substantial liquidity at the target price
        uint256 ethAmount = 1 ether; // 1 WETH
        uint256 mphAmount = TARGET_MPH_PER_WETH * ethAmount / 1 ether; // 100,000 MPH
        
        console.log("Adding liquidity with:");
        console.log("- WETH amount:", ethAmount / 1e18);
        console.log("- MPH amount:", mphAmount / 1e18);
        
        // Ensure we have enough WETH
        uint256 wethBalance = IWETH9(WETH).balanceOf(msg.sender);
        if (wethBalance < ethAmount) {
            console.log("Not enough WETH, depositing ETH...");
            IWETH9(WETH).deposit{value: ethAmount}();
        }
        
        // Ensure we have enough MPH
        uint256 mphBalance = IERC20(morpherTokenAddress).balanceOf(msg.sender);
        if (mphBalance < mphAmount) {
            console.log("Not enough MPH, minting more...");
            // This assumes the caller has minting rights
            MorpherToken(morpherTokenAddress).mint(msg.sender, mphAmount);
        }
        
        // Approve tokens for the position manager
        IWETH9(WETH).approve(NONFUNGIBLE_POSITION_MANAGER, ethAmount);
        IERC20(morpherTokenAddress).approve(NONFUNGIBLE_POSITION_MANAGER, mphAmount);
        
        // Calculate a wider tick range around the current price for better liquidity distribution
        int24 tickSpacing = 60; // 0.3% fee tier has 60 tick spacing
        int24 minTick = (currentTick / tickSpacing) * tickSpacing - tickSpacing * 20;
        int24 maxTick = (currentTick / tickSpacing) * tickSpacing + tickSpacing * 20;
        
        console.log("Using tick range:");
        console.log("- Min tick:", minTick);
        console.log("- Max tick:", maxTick);
        
        // Create the mint parameters
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: FEE,
            tickLower: minTick,
            tickUpper: maxTick,
            amount0Desired: token0 == morpherTokenAddress ? mphAmount : ethAmount,
            amount1Desired: token0 == morpherTokenAddress ? ethAmount : mphAmount,
            amount0Min: 0,
            amount1Min: 0,
            recipient: msg.sender,
            deadline: block.timestamp + 15 minutes
        });
        
        // Mint the position
        try INonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER).mint(params) returns (
            uint256 tokenId, 
            uint128 liquidity, 
            uint256 amount0Mint, 
            uint256 amount1Mint
        ) {
            console.log("Liquidity position created:");
            console.log("- Token ID:", tokenId);
            console.log("- Liquidity:", uint256(liquidity));
            console.log("- Amount token0 used:", amount0Mint);
            console.log("- Amount token1 used:", amount1Mint);
        } catch Error(string memory reason) {
            console.log("Failed to mint position: %s", reason);
        } catch {
            console.log("Failed to mint position: unknown error");
        }
    }
}
