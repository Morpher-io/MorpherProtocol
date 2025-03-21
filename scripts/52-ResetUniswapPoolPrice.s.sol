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
import "../lib/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
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
            SWAP_ROUTER = 0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4;
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
        
        // Check price after reducing liquidity
        console.log("Price after reducing liquidity:");
        checkCurrentPrice(poolAddress);
        
        // Perform swap to adjust price
        adjustPriceWithSwap(poolAddress, morpherTokenAddress);
        
        // Check new price after swap
        console.log("Price after swap:");
        checkCurrentPrice(poolAddress);
        
        // Add liquidity back at the new price
        addLiquidityToPool(poolAddress, morpherTokenAddress);
        
        // Final price check
        console.log("Final price after adding liquidity:");
        checkCurrentPrice(poolAddress);
        
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
        
        // For Uniswap V3, we can directly use the tick to understand the price
        // price = 1.0001^tick
        // For tick = -11135, price ≈ 0.33 (meaning 1 WETH is worth about 0.33 MPH)
        // But we want to display MPH per WETH, which is 1/price ≈ 3.03
        
        // Calculate price from tick for better accuracy
        // 1.0001^tick = price
        // For large ticks, we use the approximation: price ≈ 1.0001^tick
        
        if (token0 == WETH) {
            // WETH is token0, MPH is token1
            // Price in Uniswap terms is token1/token0 = MPH/WETH
            // This is what we want directly
            
            // Calculate price from tick: 1.0001^tick
            // For negative tick, this gives us a price < 1
            // For positive tick, this gives us a price > 1
            
            // For display purposes, we'll calculate an approximate value
            uint256 mphPerWeth;
            
            if (tick < 0) {
                // For negative tick, price < 1, so MPH per WETH is small
                // We'll use a simple approximation based on the tick
                uint256 absTickDiv2300 = uint256(int256(-tick)) / 2300;
                mphPerWeth = 10 ** absTickDiv2300; // Rough approximation
            } else {
                // For positive tick, price > 1, so MPH per WETH is large
                uint256 tickDiv2300 = uint256(int256(tick)) / 2300;
                mphPerWeth = (10 ** tickDiv2300) * 10000; // Rough approximation
            }
            
            console.log("- Approximate price from tick: ~%d MPH per WETH", mphPerWeth);
            
            // Also calculate from sqrtPriceX96 for comparison
            uint256 price = 0;
            if (sqrtPriceX96 > 0) {
                // Formula: price = (sqrtPriceX96^2) / 2^192
                uint256 sqrtPriceSquared = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
                
                // Avoid overflow by using multiple steps
                uint256 divisor = 1 << 64; // 2^64
                uint256 intermediate = sqrtPriceSquared / divisor; // Divide by 2^64
                intermediate = intermediate / divisor; // Divide by 2^64 again
                price = intermediate / divisor; // Divide by 2^64 a third time (total division by 2^192)
                
                // Convert to a more readable format
                price = price * 1e18;
            }
            console.log("- Calculated price: %d MPH per WETH", price / 1e18);
        } else {
            // MPH is token0, WETH is token1
            // Price in Uniswap terms is token1/token0 = WETH/MPH
            // We need to invert this to get MPH/WETH
            
            // Calculate price from tick: 1.0001^tick
            uint256 mphPerWeth;
            
            if (tick < 0) {
                // For negative tick, WETH/MPH < 1, so MPH/WETH > 1
                uint256 absTickDiv2300 = uint256(int256(-tick)) / 2300;
                mphPerWeth = (10 ** absTickDiv2300) * 10000; // Rough approximation
            } else {
                // For positive tick, WETH/MPH > 1, so MPH/WETH < 1
                uint256 tickDiv2300 = uint256(int256(tick)) / 2300;
                mphPerWeth = 10 ** tickDiv2300; // Rough approximation
            }
            
            console.log("- Approximate price from tick: ~%d MPH per WETH", mphPerWeth);
            
            // Also calculate from sqrtPriceX96 for comparison
            uint256 wethPerMph = 0;
            if (sqrtPriceX96 > 0) {
                // Formula for WETH/MPH: price = (sqrtPriceX96^2) / 2^192
                uint256 sqrtPriceSquared = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
                
                // Avoid overflow by using multiple steps
                uint256 divisor = 1 << 64; // 2^64
                uint256 intermediate = sqrtPriceSquared / divisor; // Divide by 2^64
                intermediate = intermediate / divisor; // Divide by 2^64 again
                wethPerMph = intermediate / divisor; // Divide by 2^64 a third time (total division by 2^192)
                
                // Convert to a more readable format
                wethPerMph = wethPerMph * 1e18;
                
                // Invert to get MPH/WETH
                uint256 mphPerWethCalculated = 0;
                if (wethPerMph > 0) {
                    mphPerWethCalculated = 1e36 / wethPerMph;
                }
                console.log("- Calculated price: %d MPH per WETH", mphPerWethCalculated / 1e18);
            }
        }
        
        // Most importantly, show the tick which is the most reliable indicator
        console.log("- Target tick for 100,000 MPH per WETH: 11513 (or -11513 if MPH is token0)");
        console.log("- Current tick: %d", tick);
        
        // Calculate how far we are from target
        int24 targetTick = (token0 == WETH) ? int24(11513) : -11513;
        console.log("- Tick difference from target: %d", targetTick - tick);
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
        
        // For our target of 100,000 MPH per WETH, the tick would be around 11513
        // (log base 1.0001 of 100,000)
        int24 targetTick = 11513;
        
        // Based on the logs, we know WETH is token0 and MPH is token1
        // The current tick is -11135, which is far from our target of 11513
        // This means we need to increase the tick significantly
        
        // For simplicity, let's just try both swap directions to see which one works
        console.log("Trying both swap directions to see which one works...");
        
        console.log("First attempt: Swapping MPH for WETH");
        swapMphForWeth(morpherTokenAddress, fee);
        
        // Check if the price moved in the right direction
        (uint160 newSqrtPriceX96, int24 newTick, , , , , ) = pool.slot0();
        console.log("Tick after first swap attempt:", newTick);
        
        // If the tick didn't change much or moved in the wrong direction, try the other way
        if (newTick < tick + 100) {
            console.log("First swap didn't move price enough or in right direction");
            console.log("Second attempt: Swapping WETH for MPH");
            swapWethForMph(morpherTokenAddress, fee);
        }
    }
    
    // Swap WETH for MPH to adjust price
    function swapWethForMph(address morpherTokenAddress, uint24 fee) internal {
        console.log("Swapping WETH for MPH to adjust price...");
        
        // Use a smaller amount first to test the swap
        uint256 wethAmount = 0.001 ether;
        
        console.log("Current WETH balance:", IWETH9(WETH).balanceOf(msg.sender) / 1e18);
        
        // Ensure we have enough WETH
        uint256 wethBalance = IWETH9(WETH).balanceOf(msg.sender);
        if (wethBalance < wethAmount) {
            console.log("Not enough WETH, depositing ETH...");
            try IWETH9(WETH).deposit{value: wethAmount}() {
                console.log("Successfully deposited ETH to WETH");
            } catch Error(string memory reason) {
                console.log("Failed to deposit ETH: %s", reason);
                return;
            } catch {
                console.log("Failed to deposit ETH: unknown error");
                return;
            }
        }
        
        // Check WETH balance after deposit
        console.log("WETH balance after deposit:", IWETH9(WETH).balanceOf(msg.sender) / 1e18);
        
        // Approve the router to spend WETH
        try IWETH9(WETH).approve(SWAP_ROUTER, wethAmount) {
            console.log("Successfully approved WETH for swap");
        } catch Error(string memory reason) {
            console.log("Failed to approve WETH: %s", reason);
            return;
        } catch {
            console.log("Failed to approve WETH: unknown error");
            return;
        }
        
        // Check allowance
        uint256 allowance = IERC20(WETH).allowance(msg.sender, SWAP_ROUTER);
        console.log("WETH allowance for router:", allowance / 1e18);
        
        // Perform the swap with try/catch to handle errors
        IV3SwapRouter router = IV3SwapRouter(SWAP_ROUTER);
        IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: morpherTokenAddress,
            fee: fee,
            recipient: msg.sender,
            amountIn: wethAmount,
            amountOutMinimum: 0, // No slippage protection for this purpose
            sqrtPriceLimitX96: 0 // No price limit
        });
        
        try router.exactInputSingle(params) returns (uint256 amountOut) {
            console.log("Swap completed:");
            console.log("- WETH in:", wethAmount / 1e18);
            console.log("- MPH out:", amountOut / 1e18);
        } catch Error(string memory reason) {
            console.log("Swap failed: %s", reason);
            
            // Try with an even smaller amount
            wethAmount = 0.0001 ether;
            console.log("Trying with smaller amount: %d WETH", wethAmount / 1e18);
            
            // Update approval
            IWETH9(WETH).approve(SWAP_ROUTER, wethAmount);
            
            // Update params
            params.amountIn = wethAmount;
            
            try router.exactInputSingle(params) returns (uint256 amountOut) {
                console.log("Swap with smaller amount completed:");
                console.log("- WETH in:", wethAmount / 1e18);
                console.log("- MPH out:", amountOut / 1e18);
            } catch Error(string memory fallbackReason) {
                console.log("Swap with smaller amount failed: %s", fallbackReason);
            } catch {
                console.log("Swap with smaller amount failed: unknown error");
            }
        } catch {
            console.log("Swap failed: unknown error");
        }
    }
    
    // Swap MPH for WETH to adjust price
    function swapMphForWeth(address morpherTokenAddress, uint24 fee) internal {
        console.log("Swapping MPH for WETH to adjust price...");
        
        // Use a smaller amount first to test the swap
        uint256 mphAmount = 100 ether; // 100 MPH
        
        console.log("Current MPH balance:", IERC20(morpherTokenAddress).balanceOf(msg.sender) / 1e18);
        
        // Ensure we have enough MPH
        uint256 mphBalance = IERC20(morpherTokenAddress).balanceOf(msg.sender);
        if (mphBalance < mphAmount) {
            console.log("Not enough MPH, minting more...");
            // This assumes the caller has minting rights
            try MorpherToken(morpherTokenAddress).mint(msg.sender, mphAmount) {
                console.log("Successfully minted MPH");
            } catch Error(string memory reason) {
                console.log("Failed to mint MPH: %s", reason);
                return;
            } catch {
                console.log("Failed to mint MPH: unknown error");
                return;
            }
        }
        
        // Check MPH balance again after minting
        console.log("MPH balance after minting:", IERC20(morpherTokenAddress).balanceOf(msg.sender) / 1e18);
        
        // Approve the router to spend MPH
        try IERC20(morpherTokenAddress).approve(SWAP_ROUTER, mphAmount) {
            console.log("Successfully approved MPH for swap");
        } catch Error(string memory reason) {
            console.log("Failed to approve MPH: %s", reason);
            return;
        } catch {
            console.log("Failed to approve MPH: unknown error");
            return;
        }
        
        // Check allowance
        uint256 allowance = IERC20(morpherTokenAddress).allowance(msg.sender, SWAP_ROUTER);
        console.log("MPH allowance for router:", allowance / 1e18);
        
        // Perform the swap with try/catch to handle errors
        IV3SwapRouter router = IV3SwapRouter(SWAP_ROUTER);
        IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: morpherTokenAddress,
            tokenOut: WETH,
            fee: fee,
            recipient: msg.sender,
            amountIn: mphAmount,
            amountOutMinimum: 0, // No slippage protection for this purpose
            sqrtPriceLimitX96: 0 // No price limit
        });
        
        try router.exactInputSingle(params) returns (uint256 amountOut) {
            console.log("Swap completed:");
            console.log("- MPH in:", mphAmount / 1e18);
            console.log("- WETH out:", amountOut / 1e18);
        } catch Error(string memory reason) {
            console.log("Swap failed: %s", reason);
            
            // Try with an even smaller amount
            mphAmount = 10 ether; // 10 MPH
            console.log("Trying with smaller amount: %d MPH", mphAmount / 1e18);
            
            // Update approval
            IERC20(morpherTokenAddress).approve(SWAP_ROUTER, mphAmount);
            
            // Update params
            params.amountIn = mphAmount;
            
            try router.exactInputSingle(params) returns (uint256 amountOut) {
                console.log("Swap with smaller amount completed:");
                console.log("- MPH in:", mphAmount / 1e18);
                console.log("- WETH out:", amountOut / 1e18);
            } catch Error(string memory fallbackReason) {
                console.log("Swap with smaller amount failed: %s", fallbackReason);
            } catch {
                console.log("Swap with smaller amount failed: unknown error");
            }
        } catch {
            console.log("Swap failed: unknown error");
        }
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
