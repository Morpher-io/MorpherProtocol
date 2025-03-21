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

    // Flag to track if we've done a direct price reset
    bool private didDirectPriceReset = false;
    
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
        
        // Add liquidity back at the new price only if we didn't do a direct reset
        if (!didDirectPriceReset) {
            console.log("Adding liquidity back at the current price...");
            addLiquidityToPool(poolAddress, morpherTokenAddress);
            
            // Final price check
            console.log("Final price after adding liquidity:");
            checkCurrentPrice(poolAddress);
        } else {
            console.log("Skipping additional liquidity addition since we did a direct price reset");
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
        
        // For Uniswap V3, the tick is the most reliable indicator of price
        // We'll just use the tick to determine if we're close to our target
        
        // Most importantly, show the tick which is the most reliable indicator
        console.log("- Target tick for 100,000 MPH per WETH: 11513 (or -11513 if MPH is token0)");
        console.log("- Current tick: %d", tick);
        
        // Calculate how far we are from target
        int24 targetTick = (token0 == WETH) ? int24(11513) : -11513;
        console.log("- Tick difference from target: %d", targetTick - tick);
        
        // For display purposes, provide a rough estimate of the price
        if (token0 == WETH) {
            // WETH is token0, MPH is token1
            if (tick < -50000 || tick > 50000) {
                console.log("- Price is extreme (tick out of normal range)");
            } else if (tick < 0) {
                // For negative tick, price < 1
                console.log("- Price: Less than 1 MPH per WETH");
            } else {
                // For positive tick, price > 1
                console.log("- Price: More than 1 MPH per WETH");
                
                // Very rough approximation for display only
                if (tick > 0 && tick < 20000) {
                    uint256 approxPrice = uint256(1) << (uint256(int256(tick)) / 2300);
                    console.log("- Approximate price: ~%d MPH per WETH", approxPrice);
                }
            }
        } else {
            // MPH is token0, WETH is token1
            if (tick < -50000 || tick > 50000) {
                console.log("- Price is extreme (tick out of normal range)");
            } else if (tick < 0) {
                // For negative tick, WETH/MPH < 1, so MPH/WETH > 1
                console.log("- Price: More than 1 MPH per WETH");
                
                // Very rough approximation for display only
                if (tick > -20000 && tick < 0) {
                    uint256 approxPrice = uint256(1) << (uint256(int256(-tick)) / 2300);
                    console.log("- Approximate price: ~%d MPH per WETH", approxPrice);
                }
            } else {
                // For positive tick, WETH/MPH > 1, so MPH/WETH < 1
                console.log("- Price: Less than 1 MPH per WETH");
            }
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
        
        // For our target of 100,000 MPH per WETH
        // log base 1.0001 of 100,000 is approximately 11513
        // But we need to be precise with this calculation
        int24 targetTick;
        
        // Calculate the target tick more precisely
        if (token0 == WETH) {
            // If WETH is token0, we want a price of 100,000 MPH per WETH
            // This is a positive tick
            targetTick = 11513;
        } else {
            // If MPH is token0, we want a price of 1/100,000 WETH per MPH
            // This is a negative tick
            targetTick = -11513;
        }
        
        console.log("Calculated target tick:", targetTick);
        
        // Calculate the direction we need to move
        bool needToIncreasePrice;
        
        if (token0 == WETH) {
            // WETH is token0, MPH is token1
            // We need to increase the price (tick) to reach our target
            needToIncreasePrice = tick < targetTick;
        } else {
            // MPH is token0, WETH is token1
            // We need to decrease the price (tick) to reach our target
            needToIncreasePrice = tick > -targetTick;
        }
        
        if (needToIncreasePrice) {
            console.log("Need to increase MPH/WETH price");
            console.log("Swapping MPH for WETH to increase price");
            swapMphForWeth(morpherTokenAddress, fee);
        } else {
            console.log("Need to decrease MPH/WETH price");
            console.log("Swapping WETH for MPH to decrease price");
            swapWethForMph(morpherTokenAddress, fee);
        }
        
        // Check if the price moved in the right direction
        (uint160 newSqrtPriceX96, int24 newTick, , , , , ) = pool.slot0();
        console.log("Tick after swap:", newTick);
        
        // If we're still far from target, try a direct price reset
        int24 targetTickWithBuffer = token0 == WETH ? targetTick : -targetTick;
        if (Math.abs(newTick - targetTickWithBuffer) > 5000) {
            console.log("Still far from target price, trying direct price reset");
            resetPoolPrice(poolAddress, morpherTokenAddress);
        }
    }
    
    // Reset pool price directly by removing all liquidity and adding it back at target price
    function resetPoolPrice(address poolAddress, address morpherTokenAddress) internal {
        // First remove all liquidity
        removeAllLiquidityAndBurn();
        
        // Calculate the initial sqrt price for the target price
        uint160 sqrtPriceX96 = calculateSqrtPriceX96ForTarget(poolAddress);
        
        // Initialize the pool with the target price
        try IUniswapV3Pool(poolAddress).initialize(sqrtPriceX96) {
            console.log("Pool initialized with target price");
            console.log("Target sqrtPriceX96:", uint256(sqrtPriceX96));
        } catch Error(string memory reason) {
            console.log("Failed to initialize pool: %s", reason);
            console.log("Pool may already be initialized, continuing with liquidity addition");
        } catch {
            console.log("Failed to initialize pool: unknown error");
            console.log("Pool may already be initialized, continuing with liquidity addition");
        }
        
        // Then add new liquidity at target price
        addLiquidityAtTargetPrice(poolAddress, morpherTokenAddress);
    }
    
    // Calculate the sqrtPriceX96 value for the target price
    function calculateSqrtPriceX96ForTarget(address poolAddress) internal view returns (uint160) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        address token0 = pool.token0();
        
        // Target price: 100,000 MPH per WETH
        uint256 targetPrice;
        
        if (token0 == WETH) {
            // If WETH is token0, price = MPH/WETH = 100,000
            targetPrice = TARGET_MPH_PER_WETH;
        } else {
            // If MPH is token0, price = WETH/MPH = 1/100,000
            targetPrice = (1e36 / TARGET_MPH_PER_WETH) / 1e18;
        }
        
        console.log("Target price calculation:");
        console.log("- WETH is token0:", token0 == WETH);
        console.log("- Target price value:", targetPrice);
        
        // Calculate sqrtPriceX96 from the target price
        // sqrtPriceX96 = sqrt(price) * 2^96
        uint256 sqrtPrice = sqrt(targetPrice * 1e18); // Scale by 1e18 for precision
        uint256 sqrtPriceX96 = (sqrtPrice * (1 << 96)) / 1e9; // Divide by 1e9 to account for the sqrt of 1e18
        
        console.log("- Sqrt of price:", sqrtPrice);
        console.log("- SqrtPriceX96:", sqrtPriceX96);
        
        return uint160(sqrtPriceX96);
    }
    
    // Square root function using Newton's method
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        
        return y;
    }
    
    // Helper function to remove all liquidity and burn positions
    function removeAllLiquidityAndBurn() internal {
        INonfungiblePositionManager posManager = INonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER);
        
        // Get the balance of NFTs for this address
        uint256 balance = posManager.balanceOf(msg.sender);
        console.log("Found positions for complete removal:", balance);
        
        // Loop through and remove all liquidity from positions
        for (uint256 i = 0; i < balance; i++) {
            // Always get the first token since the array shifts when we burn
            uint256 tokenId = posManager.tokenOfOwnerByIndex(msg.sender, 0);
            console.log("Removing all liquidity from position with token ID:", tokenId);
            
            // Get position details
            (
                ,
                ,
                ,
                ,
                ,
                ,
                ,
                uint128 liquidity,
                ,
                ,
                ,
            ) = posManager.positions(tokenId);
            
            if (liquidity > 0) {
                // Decrease all liquidity
                console.log("Decreasing all liquidity...");
                (uint256 amount0, uint256 amount1) = posManager.decreaseLiquidity(
                    INonfungiblePositionManager.DecreaseLiquidityParams({
                        tokenId: tokenId,
                        liquidity: liquidity,
                        amount0Min: 0,
                        amount1Min: 0,
                        deadline: block.timestamp + 15 minutes
                    })
                );
                
                console.log("Liquidity removed:");
                console.log("- Amount token0:", amount0);
                console.log("- Amount token1:", amount1);
                
                // Collect all tokens
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
            
            // Burn the position
            posManager.burn(tokenId);
            console.log("Position with token ID %d successfully burned", tokenId);
        }
    }
    
    // Helper function to add liquidity at target price
    function addLiquidityAtTargetPrice(address poolAddress, address morpherTokenAddress) internal {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        address token0 = pool.token0();
        address token1 = pool.token1();
        
        // Get the current price to determine the correct ratio
        (uint160 sqrtPriceX96, int24 currentTick, , , , , ) = pool.slot0();
        console.log("Current tick before adding liquidity:", currentTick);
        
        // Check if the tick is in a valid range
        if (currentTick > 800000 || currentTick < -800000) {
            console.log("Current tick is too extreme for adding liquidity");
            // Try to reset the price to something more reasonable
            tryResetPoolToReasonableTick(poolAddress, morpherTokenAddress);
            
            // Get the new tick after reset attempt
            (,currentTick,,,,,) = pool.slot0();
            console.log("Tick after reset attempt:", currentTick);
            
            // If still extreme, we can't add liquidity
            if (currentTick > 800000 || currentTick < -800000) {
                console.log("Tick is still too extreme, cannot add liquidity safely");
                return;
            }
        }
        
        // Use smaller amounts for extreme ticks
        uint256 ethAmount = 0.1 ether; // 0.1 WETH
        uint256 mphAmount = 10000 ether; // 10,000 MPH
        
        // Adjust the amounts based on the current price to ensure balanced liquidity
        if (Math.abs(currentTick) > 50000) {
            console.log("Current price is extreme, using a more balanced ratio");
            // If the price is extreme, use a more balanced ratio
            if (token0 == WETH) {
                if (currentTick < 0) {
                    // More WETH needed
                    ethAmount = 0.2 ether;
                    mphAmount = 5000 ether;
                } else {
                    // More MPH needed
                    ethAmount = 0.05 ether;
                    mphAmount = 20000 ether;
                }
            } else {
                if (currentTick < 0) {
                    // More MPH needed
                    ethAmount = 0.05 ether;
                    mphAmount = 20000 ether;
                } else {
                    // More WETH needed
                    ethAmount = 0.2 ether;
                    mphAmount = 5000 ether;
                }
            }
        }
        
        console.log("Adding liquidity with target ratio:");
        console.log("- WETH amount:", ethAmount / 1e18);
        console.log("- MPH amount:", mphAmount / 1e18);
        
        // Ensure we have enough WETH
        uint256 wethBalance = IWETH9(WETH).balanceOf(msg.sender);
        if (wethBalance < ethAmount) {
            console.log("Not enough WETH, depositing ETH...");
            try IWETH9(WETH).deposit{value: ethAmount}() {
                console.log("Successfully deposited ETH to WETH");
            } catch Error(string memory reason) {
                console.log("Failed to deposit ETH: %s", reason);
                return;
            } catch {
                console.log("Failed to deposit ETH: unknown error");
                return;
            }
        }
        
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
        
        // Approve tokens for the position manager
        try IWETH9(WETH).approve(NONFUNGIBLE_POSITION_MANAGER, ethAmount) {
            console.log("Successfully approved WETH");
        } catch {
            console.log("Failed to approve WETH");
            return;
        }
        
        try IERC20(morpherTokenAddress).approve(NONFUNGIBLE_POSITION_MANAGER, mphAmount) {
            console.log("Successfully approved MPH");
        } catch {
            console.log("Failed to approve MPH");
            return;
        }
        
        // Create and mint the position
        createPositionAtTargetPrice(token0, token1, morpherTokenAddress, ethAmount, mphAmount);
    }
    
    // Helper function to create position at target price
    function createPositionAtTargetPrice(
        address token0, 
        address token1, 
        address morpherTokenAddress,
        uint256 ethAmount,
        uint256 mphAmount
    ) internal {
        // Get the current tick after our price initialization
        IUniswapV3Pool pool = IUniswapV3Pool(getPoolAddress(morpherTokenAddress));
        (,int24 currentTick,,,,,) = pool.slot0();
        
        console.log("Current tick after price initialization:", currentTick);
        
        // Ensure the tick is within valid range
        if (currentTick > 887270) currentTick = 887270;
        if (currentTick < -887270) currentTick = -887270;
        
        // Use a narrower tick range around the current price
        int24 tickSpacing = 60; // 0.3% fee tier has 60 tick spacing
        int24 minTick = (currentTick / tickSpacing) * tickSpacing - tickSpacing * 5;
        int24 maxTick = (currentTick / tickSpacing) * tickSpacing + tickSpacing * 5;
        
        // Ensure ticks are within valid range
        if (minTick < -887270) minTick = -887270;
        if (maxTick > 887270) maxTick = 887270;
        
        // Ensure min tick is less than max tick
        if (minTick >= maxTick) {
            minTick = maxTick - tickSpacing;
        }
        
        console.log("Using tick range around target:");
        console.log("- Min tick:", minTick);
        console.log("- Max tick:", maxTick);
        
        // Use smaller amounts for extreme ticks
        if (Math.abs(currentTick) > 500000) {
            ethAmount = 0.01 ether;
            mphAmount = 1000 ether;
            console.log("Using smaller amounts due to extreme tick:");
            console.log("- WETH amount:", ethAmount / 1e18);
            console.log("- MPH amount:", mphAmount / 1e18);
        }
        
        // Determine token amounts based on token order
        uint256 amount0 = token0 == morpherTokenAddress ? mphAmount : ethAmount;
        uint256 amount1 = token0 == morpherTokenAddress ? ethAmount : mphAmount;
        
        // Ensure both amounts are non-zero
        if (amount0 == 0) amount0 = 1;
        if (amount1 == 0) amount1 = 1;
        
        console.log("Final amounts for position:");
        console.log("- Amount0:", amount0);
        console.log("- Amount1:", amount1);
        
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
            console.log("New liquidity position created at target price:");
            console.log("- Token ID:", tokenId);
            console.log("- Liquidity:", uint256(liquidity));
            console.log("- Amount token0 used:", amount0Mint);
            console.log("- Amount token1 used:", amount1Mint);
            
            // Set the flag to indicate we've done a direct price reset
            didDirectPriceReset = true;
        } catch Error(string memory reason) {
            console.log("Failed to mint position at target price: %s", reason);
            
            // Try with even smaller amounts and narrower range as a fallback
            tryFallbackPositionCreation(token0, token1, morpherTokenAddress, currentTick);
        } catch {
            console.log("Failed to mint position at target price: unknown error");
            
            // Try with even smaller amounts and narrower range as a fallback
            tryFallbackPositionCreation(token0, token1, morpherTokenAddress, currentTick);
        }
    }
    
    // Swap WETH for MPH to adjust price
    function swapWethForMph(address morpherTokenAddress, uint24 fee) internal {
        console.log("Swapping WETH for MPH to adjust price...");
        
        // Use a very small amount to avoid extreme price movement
        uint256 wethAmount = 0.0001 ether;
        
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
        
        // Use a very small amount to avoid extreme price movement
        uint256 mphAmount = 10 ether; // 10 MPH
        
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
        
        // Get token order and current tick
        address token0 = pool.token0();
        address token1 = pool.token1();
        (,int24 currentTick,,,,,) = pool.slot0();
        console.log("Current tick after swap:", currentTick);
        
        // Check if the tick is in a valid range
        if (currentTick > 800000 || currentTick < -800000) {
            console.log("Current tick is too extreme for adding liquidity, attempting to reset price first");
            // Try to reset the price to something more reasonable
            tryResetPoolToReasonableTick(poolAddress, morpherTokenAddress);
            
            // Get the new tick after reset attempt
            (,currentTick,,,,,) = pool.slot0();
            console.log("Tick after reset attempt:", currentTick);
            
            // If still extreme, we can't add liquidity
            if (currentTick > 800000 || currentTick < -800000) {
                console.log("Tick is still too extreme, cannot add liquidity safely");
                return;
            }
        }
        
        // Prepare liquidity amounts - use smaller amounts for extreme ticks
        uint256 ethAmount = 0.1 ether; // 0.1 WETH
        uint256 mphAmount = 10000 ether; // 10,000 MPH
        
        console.log("Adding liquidity with:");
        console.log("- WETH amount:", ethAmount / 1e18);
        console.log("- MPH amount:", mphAmount / 1e18);
        
        // Ensure we have enough tokens
        ensureTokenBalances(morpherTokenAddress, ethAmount, mphAmount);
        
        // Calculate tick range and create position
        createPositionAtCurrentPrice(token0, token1, morpherTokenAddress, ethAmount, mphAmount, currentTick);
    }
    
    // Try to reset the pool to a more reasonable tick
    function tryResetPoolToReasonableTick(address poolAddress, address morpherTokenAddress) internal {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        address token0 = pool.token0();
        address token1 = pool.token1();
        
        console.log("Attempting to reset pool to a more reasonable tick");
        
        // Try a small swap to move the price
        if (token0 == WETH) {
            // If WETH is token0, swap WETH for MPH to move price down
            console.log("Swapping a tiny amount of WETH for MPH to normalize price");
            uint256 tinyAmount = 0.0001 ether;
            
            // Ensure we have WETH
            uint256 wethBalance = IWETH9(WETH).balanceOf(msg.sender);
            if (wethBalance < tinyAmount) {
                IWETH9(WETH).deposit{value: tinyAmount}();
            }
            
            // Approve and swap
            IWETH9(WETH).approve(SWAP_ROUTER, tinyAmount);
            
            try IV3SwapRouter(SWAP_ROUTER).exactInputSingle(
                IV3SwapRouter.ExactInputSingleParams({
                    tokenIn: WETH,
                    tokenOut: morpherTokenAddress,
                    fee: FEE,
                    recipient: msg.sender,
                    amountIn: tinyAmount,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            ) returns (uint256 amountOut) {
                console.log("Reset swap completed with output:", amountOut);
            } catch {
                console.log("Reset swap failed");
            }
        } else {
            // If MPH is token0, swap MPH for WETH to move price down
            console.log("Swapping a tiny amount of MPH for WETH to normalize price");
            uint256 tinyAmount = 1 ether; // 1 MPH
            
            // Ensure we have MPH
            uint256 mphBalance = IERC20(morpherTokenAddress).balanceOf(msg.sender);
            if (mphBalance < tinyAmount) {
                try MorpherToken(morpherTokenAddress).mint(msg.sender, tinyAmount) {
                    console.log("Minted MPH for reset swap");
                } catch {
                    console.log("Failed to mint MPH for reset swap");
                    return;
                }
            }
            
            // Approve and swap
            IERC20(morpherTokenAddress).approve(SWAP_ROUTER, tinyAmount);
            
            try IV3SwapRouter(SWAP_ROUTER).exactInputSingle(
                IV3SwapRouter.ExactInputSingleParams({
                    tokenIn: morpherTokenAddress,
                    tokenOut: WETH,
                    fee: FEE,
                    recipient: msg.sender,
                    amountIn: tinyAmount,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            ) returns (uint256 amountOut) {
                console.log("Reset swap completed with output:", amountOut);
            } catch {
                console.log("Reset swap failed");
            }
        }
    }
    
    // Helper function to ensure we have enough tokens
    function ensureTokenBalances(address morpherTokenAddress, uint256 ethAmount, uint256 mphAmount) internal {
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
    }
    
    // Helper function to create position at current price
    function createPositionAtCurrentPrice(
        address token0, 
        address token1, 
        address morpherTokenAddress,
        uint256 ethAmount,
        uint256 mphAmount,
        int24 currentTick
    ) internal {
        // Calculate a wider tick range around the current price for better liquidity distribution
        int24 tickSpacing = 60; // 0.3% fee tier has 60 tick spacing
        
        // Ensure the tick range is valid
        // Uniswap V3 has a max tick of 887272 and min tick of -887272
        int24 maxValidTick = 887270;
        int24 minValidTick = -887270;
        
        // Ensure current tick is within valid range
        currentTick = currentTick > maxValidTick ? maxValidTick : currentTick;
        currentTick = currentTick < minValidTick ? minValidTick : currentTick;
        
        // Calculate tick range, ensuring we stay within valid bounds
        int24 minTick = (currentTick / tickSpacing) * tickSpacing - tickSpacing * 10;
        int24 maxTick = (currentTick / tickSpacing) * tickSpacing + tickSpacing * 10;
        
        // Ensure ticks are within valid range
        minTick = minTick < minValidTick ? minValidTick : minTick;
        maxTick = maxTick > maxValidTick ? maxValidTick : maxTick;
        
        // Ensure min tick is less than max tick
        if (minTick >= maxTick) {
            minTick = maxTick - tickSpacing;
        }
        
        console.log("Using tick range:");
        console.log("- Min tick:", minTick);
        console.log("- Max tick:", maxTick);
        
        // Ensure we have non-zero amounts for both tokens
        if (mphAmount == 0) {
            mphAmount = 10 ether; // Set a minimum of 10 MPH
            console.log("MPH amount was 0, setting to minimum:", mphAmount / 1e18);
        }
        
        // Determine token amounts based on token order
        uint256 amount0 = token0 == morpherTokenAddress ? mphAmount : ethAmount;
        uint256 amount1 = token0 == morpherTokenAddress ? ethAmount : mphAmount;
        
        // Ensure both amounts are non-zero
        if (amount0 == 0) amount0 = 1; // Set to minimum value
        if (amount1 == 0) amount1 = 1; // Set to minimum value
        
        console.log("Final amounts for position:");
        console.log("- Amount0:", amount0);
        console.log("- Amount1:", amount1);
        
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
            console.log("- Token ID:", tokenId);
            console.log("- Liquidity:", uint256(liquidity));
            console.log("- Amount token0 used:", amount0Mint);
            console.log("- Amount token1 used:", amount1Mint);
        } catch Error(string memory reason) {
            console.log("Failed to mint position: %s", reason);
            
            // Try with even smaller amounts and narrower range as a fallback
            tryFallbackPositionCreation(token0, token1, morpherTokenAddress, currentTick);
        } catch {
            console.log("Failed to mint position: unknown error");
            
            // Try with even smaller amounts and narrower range as a fallback
            tryFallbackPositionCreation(token0, token1, morpherTokenAddress, currentTick);
        }
    }
    
    // Try a fallback position creation with minimal values
    function tryFallbackPositionCreation(
        address token0,
        address token1,
        address morpherTokenAddress,
        int24 currentTick
    ) internal {
        console.log("Trying fallback position creation with minimal values");
        
        int24 tickSpacing = 60;
        
        // Use a very narrow range
        int24 minTick = (currentTick / tickSpacing) * tickSpacing - tickSpacing;
        int24 maxTick = (currentTick / tickSpacing) * tickSpacing + tickSpacing;
        
        // Ensure ticks are within valid range
        minTick = minTick < -887270 ? -887270 : minTick;
        maxTick = maxTick > 887270 ? 887270 : maxTick;
        
        // Use minimal amounts
        uint256 minEthAmount = 0.001 ether;
        uint256 minMphAmount = 1 ether;
        
        // Ensure we have the tokens
        ensureTokenBalances(morpherTokenAddress, minEthAmount, minMphAmount);
        
        // Determine token amounts based on token order
        uint256 amount0 = token0 == morpherTokenAddress ? minMphAmount : minEthAmount;
        uint256 amount1 = token0 == morpherTokenAddress ? minEthAmount : minMphAmount;
        
        console.log("Fallback position parameters:");
        console.log("- Min tick:", minTick);
        console.log("- Max tick:", maxTick);
        console.log("- Amount0:", amount0);
        console.log("- Amount1:", amount1);
        
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
            console.log("- Token ID:", tokenId);
            console.log("- Liquidity:", uint256(liquidity));
            console.log("- Amount token0 used:", amount0Mint);
            console.log("- Amount token1 used:", amount1Mint);
        } catch Error(string memory reason) {
            console.log("Fallback position creation failed: %s", reason);
        } catch {
            console.log("Fallback position creation failed: unknown error");
        }
    }
}
