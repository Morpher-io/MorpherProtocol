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
        (uint160 sqrtPriceX96, tick, , , , , bool unlocked) = pool.slot0();
        
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
    
    
    // Adjust price gradually with multiple small swaps
    function adjustPriceGradually(
        address poolAddress, 
        address morpherTokenAddress, 
        int24 targetTick, 
        bool wethIsToken0
    ) internal returns (bool) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        
        // Get initial tick
        (,int24 currentTick,,,,,) = pool.slot0();
        console.log("Starting gradual price adjustment:");
        console.log("- Current tick: %d", currentTick);
        console.log("- Target tick: %d", targetTick);
        
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
                // Very far - use larger amount
                swapAmount = needToIncreasePrice ? 5000 ether : 0.05 ether;
            } else if (Math.abs(tickDiff) > 10000) {
                // Far - use medium amount
                swapAmount = needToIncreasePrice ? 1000 ether : 0.01 ether;
            } else if (Math.abs(tickDiff) > 5000) {
                // Getting closer - use smaller amount
                swapAmount = needToIncreasePrice ? 500 ether : 0.005 ether;
            } else {
                // Close - use tiny amount
                swapAmount = needToIncreasePrice ? 100 ether : 0.001 ether;
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
                    
                    // Try one more approach with a much larger amount
                    swapAmount = needToIncreasePrice ? 50000 ether : 0.5 ether;
                    
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
        if (wethBalance < wethAmount) {
            console.log("Not enough WETH, depositing ETH...");
            try IWETH9(WETH).deposit{value: wethAmount}() {
                console.log("Successfully deposited ETH to WETH");
            } catch {
                console.log("Failed to deposit ETH, reducing swap amount");
                wethAmount = wethBalance > 0 ? wethBalance : 0.001 ether;
            }
        }
        
        // Approve the router to spend WETH
        try IWETH9(WETH).approve(SWAP_ROUTER, wethAmount) {
            console.log("Successfully approved WETH for swap");
        } catch {
            console.log("Failed to approve WETH");
            return;
        }
        
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
        if (mphBalance < mphAmount) {
            console.log("Not enough MPH, minting more...");
            try MorpherToken(morpherTokenAddress).mint(msg.sender, mphAmount) {
                console.log("Successfully minted MPH");
            } catch {
                console.log("Failed to mint MPH, reducing swap amount");
                mphAmount = mphBalance > 0 ? mphBalance : 1 ether;
            }
        }
        
        // Approve the router to spend MPH
        try IERC20(morpherTokenAddress).approve(SWAP_ROUTER, mphAmount) {
            console.log("Successfully approved MPH for swap");
        } catch {
            console.log("Failed to approve MPH");
            return;
        }
        
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
    
}
