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

// Simple Math library for absolute value
library Math {
    function abs(int24 x) internal pure returns (int24) {
        return x >= 0 ? x : -x;
    }
}

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

contract GradualPriceAdjustment is DeployOrUpgrade {
    using stdJson for string;

    // Uniswap V3 addresses - will be set based on chainId
    address public UNISWAP_V3_FACTORY;
    address public NONFUNGIBLE_POSITION_MANAGER;
    address public SWAP_ROUTER;
    address public WETH;
    uint24 constant FEE = 3000; // 0.3%
    
    // Target price: 10,000 MPH = 0.1 WETH (ratio 100,000:1)
    uint256 constant TARGET_MPH_PER_WETH = 100000;
    
    // Target tick for 100,000 MPH per WETH is approximately 11513
    int24 constant TARGET_TICK = 11513;
    
    // Maximum number of swap attempts
    uint256 constant MAX_SWAP_ATTEMPTS = 20;
    
    // Tick tolerance - how close we need to get to target
    int24 constant TICK_TOLERANCE = 1000;

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

        console.log("Gradually adjusting Uniswap pool price on chain ID:", uint256(block.chainid));
        
        // Load MorpherToken address
        address morpherTokenAddress = loadAddress("MorpherToken");
        require(morpherTokenAddress != address(0), "MorpherToken must be deployed first");
        
        console.log("MorpherToken address:", morpherTokenAddress);
        console.log("WETH address:", WETH);

        // Get the pool address
        address poolAddress = getPoolAddress(morpherTokenAddress);
        console.log("Pool address:", poolAddress);
        
        // Check current price
        (int24 currentTick, bool wethIsToken0) = checkCurrentPrice(poolAddress);
        
        // Calculate target tick based on token order
        int24 targetTick = wethIsToken0 ? TARGET_TICK : -TARGET_TICK;
        console.log("Target tick:", targetTick);
        
        // Try a small test swap first to verify everything works
        console.log("Performing a small test swap to verify functionality...");
        if (wethIsToken0) {
            swapMphForWeth(morpherTokenAddress, 1 ether); // Swap 1 MPH for WETH
        } else {
            swapWethForMph(morpherTokenAddress, 0.0001 ether); // Swap 0.0001 WETH for MPH
        }
        
        // Check if the test swap worked
        (int24 newTick, ) = checkCurrentPrice(poolAddress);
        if (newTick != currentTick) {
            console.log("Test swap successful, proceeding with price adjustment");
            
            // Perform gradual swaps to adjust price
            bool success = adjustPriceGradually(poolAddress, morpherTokenAddress, targetTick, wethIsToken0);
            
            if (success) {
                console.log("Successfully adjusted price to near target!");
                
                // Final price check
                console.log("Final price:");
                checkCurrentPrice(poolAddress);
            } else {
                console.log("Failed to adjust price to target after maximum attempts");
            }
        } else {
            console.log("Test swap did not change the price, there may be an issue with the pool");
            console.log("Trying with a different approach...");
            
            // Try a different approach with a single larger swap
            uint256 swapAmount = wethIsToken0 ? 5 ether : 0.0005 ether;
            
            if (currentTick < targetTick) {
                // Need to increase price
                if (wethIsToken0) {
                    console.log("Trying a single larger swap: MPH for WETH");
                    swapMphForWeth(morpherTokenAddress, swapAmount);
                } else {
                    console.log("Trying a single larger swap: WETH for MPH");
                    swapWethForMph(morpherTokenAddress, swapAmount);
                }
            } else {
                // Need to decrease price
                if (wethIsToken0) {
                    console.log("Trying a single larger swap: WETH for MPH");
                    swapWethForMph(morpherTokenAddress, swapAmount);
                } else {
                    console.log("Trying a single larger swap: MPH for WETH");
                    swapMphForWeth(morpherTokenAddress, swapAmount);
                }
            }
            
            // Final price check
            console.log("Final price after alternative approach:");
            checkCurrentPrice(poolAddress);
        }
        
        vm.stopBroadcast();
    }
    
    // Get the pool address
    function getPoolAddress(address morpherTokenAddress) internal view returns (address) {
        IUniswapV3Factory factory = IUniswapV3Factory(UNISWAP_V3_FACTORY);
        address poolAddress = factory.getPool(morpherTokenAddress, WETH, FEE);
        require(poolAddress != address(0), "Pool does not exist");
        return poolAddress;
    }
    
    // Check and display the current price, returns the current tick and whether WETH is token0
    function checkCurrentPrice(address poolAddress) internal view returns (int24 tick, bool wethIsToken0) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        
        uint160 sqrtPriceX96;
        uint16 observationIndex;
        uint16 observationCardinality;
        uint16 observationCardinalityNext;
        uint8 feeProtocol;
        bool unlocked;
        
        (sqrtPriceX96, tick, observationIndex, observationCardinality, observationCardinalityNext, feeProtocol, unlocked) = pool.slot0();
        
        address token0 = pool.token0();
        address token1 = pool.token1();
        
        wethIsToken0 = (token0 == WETH);
        
        console.log("Current pool state:");
        console.log("- Token0:", token0);
        console.log("- Token1:", token1);
        console.log("- Tick:", tick);
        console.log("- SqrtPriceX96:", uint256(sqrtPriceX96));
        
        // Calculate how far we are from target
        int24 targetTick = wethIsToken0 ? TARGET_TICK : -TARGET_TICK;
        console.log("- Target tick for 100,000 MPH per WETH:", targetTick);
        console.log("- Current tick: %d", tick);
        console.log("- Tick difference from target: %d", targetTick - tick);
        
        // For display purposes, provide a rough estimate of the price
        if (Math.abs(tick) > 50000) {
            console.log("- Price is extreme (tick out of normal range)");
        } else {
            if (wethIsToken0) {
                // WETH is token0, MPH is token1
                if (tick < 0) {
                    console.log("- Price: Less than 1 MPH per WETH");
                } else {
                    console.log("- Price: More than 1 MPH per WETH");
                    if (tick > 0 && tick < 20000) {
                        uint256 approxPrice = uint256(1) << (uint256(int256(tick)) / 2300);
                        console.log("- Approximate price: ~%d MPH per WETH", approxPrice);
                    }
                }
            } else {
                // MPH is token0, WETH is token1
                if (tick < 0) {
                    console.log("- Price: More than 1 MPH per WETH");
                    if (tick > -20000 && tick < 0) {
                        uint256 approxPrice = uint256(1) << (uint256(int256(-tick)) / 2300);
                        console.log("- Approximate price: ~%d MPH per WETH", approxPrice);
                    }
                } else {
                    console.log("- Price: Less than 1 MPH per WETH");
                }
            }
        }
        
        return (tick, wethIsToken0);
    }
    
    // Reduce liquidity in existing positions to a minimal amount
    function removeAllLiquidity() internal {
        INonfungiblePositionManager posManager = INonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER);
        
        // Get the balance of NFTs for this address
        uint256 balance = posManager.balanceOf(msg.sender);
        console.log("Found existing positions:", balance);
        
        if (balance == 0) {
            console.log("No existing positions found, skipping liquidity removal");
            return;
        }
        
        // Loop through and reduce liquidity from all positions
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = posManager.tokenOfOwnerByIndex(msg.sender, 0); // Always get the first one as they shift when burned
            console.log("Removing liquidity from position with token ID:", tokenId);
            
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
                // Decrease all liquidity
                console.log("Decreasing all liquidity...");
                
                try posManager.decreaseLiquidity(
                    INonfungiblePositionManager.DecreaseLiquidityParams({
                        tokenId: tokenId,
                        liquidity: liquidity,
                        amount0Min: 0,
                        amount1Min: 0,
                        deadline: block.timestamp + 15 minutes
                    })
                ) returns (uint256 amount0, uint256 amount1) {
                    console.log("Liquidity removed:");
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
                    
                    // Burn the position
                    try posManager.burn(tokenId) {
                        console.log("Position with token ID %d successfully burned", tokenId);
                    } catch Error(string memory reason) {
                        console.log("Failed to burn position: %s", reason);
                    } catch {
                        console.log("Failed to burn position: unknown error");
                    }
                } catch Error(string memory reason) {
                    console.log("Failed to decrease liquidity: %s", reason);
                } catch {
                    console.log("Failed to decrease liquidity: unknown error");
                }
            } else {
                console.log("Position has no liquidity, attempting to burn directly");
                try posManager.burn(tokenId) {
                    console.log("Position with token ID %d successfully burned", tokenId);
                } catch Error(string memory reason) {
                    console.log("Failed to burn position: %s", reason);
                } catch {
                    console.log("Failed to burn position: unknown error");
                }
            }
        }
    }
    
    // Adjust price gradually with multiple small swaps
    function adjustPriceGradually(
        address poolAddress, 
        address morpherTokenAddress, 
        int24 targetTick, 
        bool wethIsToken0
    ) internal returns (bool) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        
        // Get initial tick
        uint160 sqrtPriceX96;
        int24 currentTick;
        uint16 observationIndex;
        uint16 observationCardinality;
        uint16 observationCardinalityNext;
        uint8 feeProtocol;
        bool unlocked;
        
        (sqrtPriceX96, currentTick, observationIndex, observationCardinality, observationCardinalityNext, feeProtocol, unlocked) = pool.slot0();
        
        console.log("Starting gradual price adjustment:");
        console.log("- Current tick: %d", currentTick);
        console.log("- Target tick: %d", targetTick);
        console.log("- Pool unlocked: %s", unlocked ? "true" : "false");
        
        // Determine initial swap direction
        bool needToIncreasePrice = currentTick < targetTick;
        
        // Calculate initial tick difference
        int24 tickDiff = targetTick - currentTick;
        console.log("- Initial tick difference: %d", tickDiff);
        
        // If we're already close enough, we're done
        if (Math.abs(tickDiff) <= TICK_TOLERANCE) {
            console.log("Current price is already within tolerance of target!");
            return true;
        }
        
        // Loop for multiple swap attempts
        for (uint256 i = 0; i < MAX_SWAP_ATTEMPTS; i++) {
            console.log("\nSwap attempt %d of %d:", i + 1, MAX_SWAP_ATTEMPTS);
            
            // Get current tick
            (,currentTick,,,,,) = pool.slot0();
            console.log("- Current tick: %d", currentTick);
            
            // Recalculate tick difference and direction
            tickDiff = targetTick - currentTick;
            needToIncreasePrice = currentTick < targetTick;
            console.log("- Tick difference: %d", tickDiff);
            
            // Check if we're close enough
            if (Math.abs(tickDiff) <= TICK_TOLERANCE) {
                console.log("Target price reached within tolerance!");
                return true;
            }
            
            // Calculate swap amount based on how far we are from target
            // Use smaller amounts as we get closer
            uint256 swapAmount;
            if (Math.abs(tickDiff) > 50000) {
                // Very far - use larger amount but still keep it small for safety
                swapAmount = needToIncreasePrice ? 10 ether : 0.001 ether;
            } else if (Math.abs(tickDiff) > 10000) {
                // Far - use medium amount
                swapAmount = needToIncreasePrice ? 5 ether : 0.0005 ether;
            } else if (Math.abs(tickDiff) > 5000) {
                // Getting closer - use smaller amount
                swapAmount = needToIncreasePrice ? 2 ether : 0.0002 ether;
            } else {
                // Close - use tiny amount
                swapAmount = needToIncreasePrice ? 1 ether : 0.0001 ether;
            }
            
            // Perform the swap
            if (needToIncreasePrice) {
                // To increase price (increase tick):
                // - If WETH is token0: Swap MPH for WETH
                // - If MPH is token0: Swap WETH for MPH
                if (wethIsToken0) {
                    console.log("Swapping MPH for WETH to increase price");
                    swapMphForWeth(morpherTokenAddress, swapAmount);
                } else {
                    console.log("Swapping WETH for MPH to increase price");
                    swapWethForMph(morpherTokenAddress, swapAmount);
                }
            } else {
                // To decrease price (decrease tick):
                // - If WETH is token0: Swap WETH for MPH
                // - If MPH is token0: Swap MPH for WETH
                if (wethIsToken0) {
                    console.log("Swapping WETH for MPH to decrease price");
                    swapWethForMph(morpherTokenAddress, swapAmount);
                } else {
                    console.log("Swapping MPH for WETH to decrease price");
                    swapMphForWeth(morpherTokenAddress, swapAmount);
                }
            }
            
            // Check new tick after swap
            (,int24 newTick,,,,,) = pool.slot0();
            console.log("- New tick after swap: %d", newTick);
            console.log("- Tick change from this swap: %d", newTick - currentTick);
            
            // If the price didn't move at all, try a different approach
            if (newTick == currentTick) {
                console.log("Price didn't move, trying a different amount");
                
                // Try with a different amount
                swapAmount = needToIncreasePrice ? 5 ether : 0.0005 ether;
                
                if (needToIncreasePrice) {
                    if (wethIsToken0) {
                        swapMphForWeth(morpherTokenAddress, swapAmount);
                    } else {
                        swapWethForMph(morpherTokenAddress, swapAmount);
                    }
                } else {
                    if (wethIsToken0) {
                        swapWethForMph(morpherTokenAddress, swapAmount);
                    } else {
                        swapMphForWeth(morpherTokenAddress, swapAmount);
                    }
                }
                
                // Check if it moved now
                (,newTick,,,,,) = pool.slot0();
                console.log("- New tick after alternative swap: %d", newTick);
                
                // If still no movement, we might be stuck
                if (newTick == currentTick) {
                    console.log("Price still didn't move, might be stuck at this tick");
                    
                    // Try one more approach with a slightly larger amount, but still keep it reasonable
                    swapAmount = needToIncreasePrice ? 20 ether : 0.002 ether;
                    
                    if (needToIncreasePrice) {
                        if (wethIsToken0) {
                            swapMphForWeth(morpherTokenAddress, swapAmount);
                        } else {
                            swapWethForMph(morpherTokenAddress, swapAmount);
                        }
                    } else {
                        if (wethIsToken0) {
                            swapWethForMph(morpherTokenAddress, swapAmount);
                        } else {
                            swapMphForWeth(morpherTokenAddress, swapAmount);
                        }
                    }
                    
                    // Final check
                    (,newTick,,,,,) = pool.slot0();
                    console.log("- New tick after large swap: %d", newTick);
                    
                    if (newTick == currentTick) {
                        console.log("Price is completely stuck, trying to continue anyway");
                    }
                }
            }
        }
        
        // Check final result
        (,currentTick,,,,,) = pool.slot0();
        tickDiff = targetTick - currentTick;
        
        console.log("\nFinal result after all swap attempts:");
        console.log("- Final tick: %d", currentTick);
        console.log("- Target tick: %d", targetTick);
        console.log("- Final tick difference: %d", tickDiff);
        
        return Math.abs(tickDiff) <= TICK_TOLERANCE;
    }
    
    // Swap WETH for MPH
    function swapWethForMph(address morpherTokenAddress, uint256 wethAmount) internal {
        console.log("Swapping %s WETH for MPH", wethAmount / 1e18);
        
        // Ensure we have enough WETH
        uint256 wethBalance = IWETH9(WETH).balanceOf(msg.sender);
        console.log("Current WETH balance: %s", wethBalance / 1e18);
        
        if (wethBalance < wethAmount) {
            console.log("Not enough WETH, depositing ETH...");
            try IWETH9(WETH).deposit{value: wethAmount}() {
                console.log("Successfully deposited ETH to WETH");
                wethBalance = IWETH9(WETH).balanceOf(msg.sender);
                console.log("New WETH balance: %s", wethBalance / 1e18);
            } catch {
                console.log("Failed to deposit ETH, reducing swap amount");
                wethAmount = wethBalance > 0 ? wethBalance : 0.001 ether;
                console.log("Reduced swap amount to: %s WETH", wethAmount / 1e18);
            }
        }
        
        // Use a smaller amount for the swap to ensure it succeeds
        if (wethAmount > 0.01 ether) {
            wethAmount = 0.01 ether;
            console.log("Limiting swap to 0.01 WETH for safety");
        }
        
        // Approve the router to spend WETH (approve a large amount to avoid repeated approvals)
        try IWETH9(WETH).approve(SWAP_ROUTER, type(uint256).max) {
            console.log("Successfully approved WETH for swap");
            uint256 allowance = IERC20(WETH).allowance(msg.sender, SWAP_ROUTER);
            console.log("WETH allowance for router: %s", allowance / 1e18);
        } catch {
            console.log("Failed to approve WETH");
            return;
        }
        
        // Get the pool to check if it exists
        address poolAddress = IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(WETH, morpherTokenAddress, FEE);
        if (poolAddress == address(0)) {
            console.log("Pool does not exist, cannot swap");
            return;
        }
        console.log("Using pool at address: %s", poolAddress);
        
        // Perform the swap
        IV3SwapRouter router = IV3SwapRouter(SWAP_ROUTER);
        IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: morpherTokenAddress,
            fee: FEE,
            recipient: msg.sender,
            amountIn: wethAmount,
            amountOutMinimum: 0, // No slippage protection for this purpose
            sqrtPriceLimitX96: 0 // No price limit
        });
        
        try router.exactInputSingle(params) returns (uint256 amountOut) {
            console.log("Swap completed:");
            console.log("- WETH in: %s", wethAmount / 1e18);
            console.log("- MPH out: %s", amountOut / 1e18);
        } catch Error(string memory reason) {
            console.log("Swap failed: %s", reason);
        } catch {
            console.log("Swap failed: unknown error");
        }
    }
    
    // Swap MPH for WETH
    function swapMphForWeth(address morpherTokenAddress, uint256 mphAmount) internal {
        console.log("Swapping %s MPH for WETH", mphAmount / 1e18);
        
        // Ensure we have enough MPH
        uint256 mphBalance = IERC20(morpherTokenAddress).balanceOf(msg.sender);
        console.log("Current MPH balance: %s", mphBalance / 1e18);
        
        if (mphBalance < mphAmount) {
            console.log("Not enough MPH, minting more...");
            try MorpherToken(morpherTokenAddress).mint(msg.sender, mphAmount) {
                console.log("Successfully minted MPH");
                mphBalance = IERC20(morpherTokenAddress).balanceOf(msg.sender);
                console.log("New MPH balance: %s", mphBalance / 1e18);
            } catch {
                console.log("Failed to mint MPH, reducing swap amount");
                mphAmount = mphBalance > 0 ? mphBalance : 1 ether;
                console.log("Reduced swap amount to: %s MPH", mphAmount / 1e18);
            }
        }
        
        // Use a smaller amount for the swap to ensure it succeeds
        if (mphAmount > 10 ether) {
            mphAmount = 10 ether;
            console.log("Limiting swap to 10 MPH for safety");
        }
        
        // Approve the router to spend MPH (approve a large amount to avoid repeated approvals)
        try IERC20(morpherTokenAddress).approve(SWAP_ROUTER, type(uint256).max) {
            console.log("Successfully approved MPH for swap");
            uint256 allowance = IERC20(morpherTokenAddress).allowance(msg.sender, SWAP_ROUTER);
            console.log("MPH allowance for router: %s", allowance / 1e18);
        } catch {
            console.log("Failed to approve MPH");
            return;
        }
        
        // Get the pool to check if it exists
        address poolAddress = IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(morpherTokenAddress, WETH, FEE);
        if (poolAddress == address(0)) {
            console.log("Pool does not exist, cannot swap");
            return;
        }
        console.log("Using pool at address: %s", poolAddress);
        
        // Perform the swap
        IV3SwapRouter router = IV3SwapRouter(SWAP_ROUTER);
        IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: morpherTokenAddress,
            tokenOut: WETH,
            fee: FEE,
            recipient: msg.sender,
            amountIn: mphAmount,
            amountOutMinimum: 0, // No slippage protection for this purpose
            sqrtPriceLimitX96: 0 // No price limit
        });
        
        try router.exactInputSingle(params) returns (uint256 amountOut) {
            console.log("Swap completed:");
            console.log("- MPH in: %s", mphAmount / 1e18);
            console.log("- WETH out: %s", amountOut / 1e18);
        } catch Error(string memory reason) {
            console.log("Swap failed: %s", reason);
        } catch {
            console.log("Swap failed: unknown error");
        }
    }
    
    // Add liquidity back to the pool at the new price
    function addLiquidityToPool(address poolAddress, address morpherTokenAddress) internal {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        
        // Get token order and current tick
        address token0 = pool.token0();
        address token1 = pool.token1();
        (,int24 currentTick,,,,,) = pool.slot0();
        console.log("Adding liquidity at current tick:", currentTick);
        
        // Use moderate amounts for liquidity
        uint256 ethAmount = 0.05 ether; // 0.05 WETH
        uint256 mphAmount = 5000 ether; // 5,000 MPH
        
        // Adjust the ratio based on the current price
        bool wethIsToken0 = (token0 == WETH);
        
        // If we're close to the target price, use the target ratio
        int24 targetTick = wethIsToken0 ? TARGET_TICK : -TARGET_TICK;
        if (Math.abs(currentTick - targetTick) <= TICK_TOLERANCE) {
            console.log("Using target price ratio for liquidity");
            mphAmount = ethAmount * TARGET_MPH_PER_WETH;
        } else {
            // Otherwise, adjust based on current tick
            if (Math.abs(currentTick) > 50000) {
                console.log("Current tick is extreme, using a balanced ratio");
                if (wethIsToken0) {
                    if (currentTick < 0) {
                        // More WETH needed
                        ethAmount = 0.1 ether;
                        mphAmount = 1000 ether;
                    } else {
                        // More MPH needed
                        ethAmount = 0.01 ether;
                        mphAmount = 10000 ether;
                    }
                } else {
                    if (currentTick < 0) {
                        // More MPH needed
                        ethAmount = 0.01 ether;
                        mphAmount = 10000 ether;
                    } else {
                        // More WETH needed
                        ethAmount = 0.1 ether;
                        mphAmount = 1000 ether;
                    }
                }
            }
        }
        
        console.log("Adding liquidity with:");
        console.log("- WETH amount: %s", ethAmount / 1e18);
        console.log("- MPH amount: %s", mphAmount / 1e18);
        
        // Ensure we have enough tokens
        ensureTokenBalances(morpherTokenAddress, ethAmount, mphAmount);
        
        // Calculate tick range and create position
        createPosition(token0, token1, morpherTokenAddress, ethAmount, mphAmount, currentTick);
    }
    
    // Helper function to ensure we have enough tokens
    function ensureTokenBalances(address morpherTokenAddress, uint256 ethAmount, uint256 mphAmount) internal {
        // Ensure we have enough WETH
        uint256 wethBalance = IWETH9(WETH).balanceOf(msg.sender);
        if (wethBalance < ethAmount) {
            console.log("Not enough WETH, depositing ETH...");
            try IWETH9(WETH).deposit{value: ethAmount}() {
                console.log("Successfully deposited ETH to WETH");
            } catch {
                console.log("Failed to deposit ETH");
                return;
            }
        }
        
        // Ensure we have enough MPH
        uint256 mphBalance = IERC20(morpherTokenAddress).balanceOf(msg.sender);
        if (mphBalance < mphAmount) {
            console.log("Not enough MPH, minting more...");
            try MorpherToken(morpherTokenAddress).mint(msg.sender, mphAmount) {
                console.log("Successfully minted MPH");
            } catch {
                console.log("Failed to mint MPH");
                return;
            }
        }
        
        // Approve tokens for the position manager
        try IWETH9(WETH).approve(NONFUNGIBLE_POSITION_MANAGER, ethAmount) {
            console.log("Successfully approved WETH");
        } catch {
            console.log("Failed to approve WETH");
        }
        
        try IERC20(morpherTokenAddress).approve(NONFUNGIBLE_POSITION_MANAGER, mphAmount) {
            console.log("Successfully approved MPH");
        } catch {
            console.log("Failed to approve MPH");
        }
    }
    
    // Helper function to create position
    function createPosition(
        address token0, 
        address token1, 
        address morpherTokenAddress,
        uint256 ethAmount,
        uint256 mphAmount,
        int24 currentTick
    ) internal {
        // Calculate a reasonable tick range around the current price
        int24 tickSpacing = 60; // 0.3% fee tier has 60 tick spacing
        
        // Ensure the tick range is valid
        int24 maxValidTick = 887270;
        int24 minValidTick = -887270;
        
        // Ensure current tick is within valid range
        currentTick = currentTick > maxValidTick ? maxValidTick : currentTick;
        currentTick = currentTick < minValidTick ? minValidTick : currentTick;
        
        // Calculate tick range, ensuring we stay within valid bounds
        int24 minTick = (currentTick / tickSpacing) * tickSpacing - tickSpacing * 5;
        int24 maxTick = (currentTick / tickSpacing) * tickSpacing + tickSpacing * 5;
        
        // Ensure ticks are within valid range
        minTick = minTick < minValidTick ? minValidTick : minTick;
        maxTick = maxTick > maxValidTick ? maxValidTick : maxTick;
        
        // Ensure min tick is less than max tick
        if (minTick >= maxTick) {
            minTick = maxTick - tickSpacing;
        }
        
        console.log("Using tick range:");
        console.log("- Min tick: %d", minTick);
        console.log("- Max tick: %d", maxTick);
        
        // Determine token amounts based on token order
        uint256 amount0 = token0 == morpherTokenAddress ? mphAmount : ethAmount;
        uint256 amount1 = token0 == morpherTokenAddress ? ethAmount : mphAmount;
        
        // Ensure both amounts are non-zero
        if (amount0 == 0) amount0 = 1;
        if (amount1 == 0) amount1 = 1;
        
        console.log("Final amounts for position:");
        console.log("- Amount0: %s", amount0);
        console.log("- Amount1: %s", amount1);
        
        // Create the mint parameters
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: FEE,
            tickLower: minTick,
            tickUpper: maxTick,
            amount0Desired: amount0,
            amount1Desired: amount1,
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
            console.log("- Token ID: %d", tokenId);
            console.log("- Liquidity: %d", uint256(liquidity));
            console.log("- Amount token0 used: %s", amount0Mint);
            console.log("- Amount token1 used: %s", amount1Mint);
        } catch Error(string memory reason) {
            console.log("Failed to mint position: %s", reason);
            
            // Try with even smaller amounts and narrower range as a fallback
            tryFallbackPosition(token0, token1, morpherTokenAddress, currentTick);
        } catch {
            console.log("Failed to mint position: unknown error");
            
            // Try with even smaller amounts and narrower range as a fallback
            tryFallbackPosition(token0, token1, morpherTokenAddress, currentTick);
        }
    }
    
    // Try a fallback position with minimal values
    function tryFallbackPosition(
        address token0,
        address token1,
        address morpherTokenAddress,
        int24 currentTick
    ) internal {
        console.log("Trying fallback position with minimal values");
        
        int24 tickSpacing = 60;
        
        // Use a very narrow range
        int24 minTick = (currentTick / tickSpacing) * tickSpacing - tickSpacing;
        int24 maxTick = (currentTick / tickSpacing) * tickSpacing + tickSpacing;
        
        // Ensure ticks are within valid range
        minTick = minTick < -887270 ? int24(-887270) : minTick;
        maxTick = maxTick > 887270 ? int24(887270) : maxTick;
        
        // Use minimal amounts
        uint256 minEthAmount = 0.001 ether;
        uint256 minMphAmount = 1 ether;
        
        // Ensure we have the tokens
        ensureTokenBalances(morpherTokenAddress, minEthAmount, minMphAmount);
        
        // Determine token amounts based on token order
        uint256 amount0 = token0 == morpherTokenAddress ? minMphAmount : minEthAmount;
        uint256 amount1 = token0 == morpherTokenAddress ? minEthAmount : minMphAmount;
        
        console.log("Fallback position parameters:");
        console.log("- Min tick: %d", minTick);
        console.log("- Max tick: %d", maxTick);
        console.log("- Amount0: %s", amount0);
        console.log("- Amount1: %s", amount1);
        
        // Create the mint parameters
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: FEE,
            tickLower: minTick,
            tickUpper: maxTick,
            amount0Desired: amount0,
            amount1Desired: amount1,
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
            console.log("Fallback liquidity position created:");
            console.log("- Token ID: %d", tokenId);
            console.log("- Liquidity: %d", uint256(liquidity));
            console.log("- Amount token0 used: %s", amount0Mint);
            console.log("- Amount token1 used: %s", amount1Mint);
        } catch Error(string memory reason) {
            console.log("Fallback position creation failed: %s", reason);
        } catch {
            console.log("Fallback position creation failed: unknown error");
        }
    }
}
