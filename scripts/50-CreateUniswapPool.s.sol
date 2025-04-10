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
}

interface IWETH9 {
    function deposit() external payable;
    function approve(address guy, uint wad) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract CreateUniswapPool is DeployOrUpgrade {
    using stdJson for string;

    // Uniswap V3 addresses - will be set based on chainId
    address public UNISWAP_V3_FACTORY;
    address public NONFUNGIBLE_POSITION_MANAGER;
    address public WETH;
    uint24 constant FEE = 3000; // 0.3%

    // Struct to store position details
    struct Deposit {
        uint256 tokenId;
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }

    // Set up addresses based on the chain we're deploying to
    function setupAddresses() internal {
        uint256 chainId = block.chainid;
    
        // WETH is the same on both Base and Base Sepolia
        WETH = 0x4200000000000000000000000000000000000006;
    
        if (chainId == 8453) {
            // Base Mainnet
            UNISWAP_V3_FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
            NONFUNGIBLE_POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
        } else if (chainId == 84532) {
            // Base Sepolia
            UNISWAP_V3_FACTORY = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
            NONFUNGIBLE_POSITION_MANAGER = 0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2;
        } else {
            revert("Unsupported chain ID");
        }
    }

    function run() public {
        // Set up the correct addresses based on the chain
        setupAddresses();
        
        vm.startBroadcast();

        console.log("Deploying on chain ID:", uint256(block.chainid));
        console.log("Using Uniswap V3 Factory:", UNISWAP_V3_FACTORY);
        console.log("Using Nonfungible Position Manager:", NONFUNGIBLE_POSITION_MANAGER);
        
        // Load MorpherToken address
        address morpherTokenAddress = loadAddress("MorpherToken");
        require(morpherTokenAddress != address(0), "MorpherToken must be deployed first");
        
        console.log("MorpherToken address:", morpherTokenAddress);
        console.log("WETH address:", WETH);

        // Check for existing positions and burn them
        checkAndBurnPositions();
        
        // Initialize or get pool
        address poolAddress = initializeOrGetPool(morpherTokenAddress);
        
        // Add liquidity to the pool
        addLiquidityToPool(poolAddress, morpherTokenAddress);
        
        // Save the pool address
        // saveAddress("UniswapV3Pool", poolAddress);
        
        vm.stopBroadcast();
    }
    
    // Check for existing positions and burn them
    function checkAndBurnPositions() internal {
        INonfungiblePositionManager posManager = INonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER);
        
        // Get the balance of NFTs for this address
        uint256 balance = posManager.balanceOf(msg.sender);
        console.log("Found existing positions", balance);
        
        // Loop through and burn all positions
        for (uint256 i = 0; i < balance; i++) {
            // Always get the first token since the array shifts when we burn
            uint256 tokenId = posManager.tokenOfOwnerByIndex(msg.sender, 0);
            console.log("Burning position with token ID: ", tokenId);
            burnPosition(tokenId);
        }
    }
    
    // Initialize a new pool or get existing pool
    function initializeOrGetPool(address morpherTokenAddress) internal returns (address poolAddress) {
        // Check if pool already exists
        IUniswapV3Factory factory = IUniswapV3Factory(UNISWAP_V3_FACTORY);
        poolAddress = factory.getPool(morpherTokenAddress, WETH, FEE);
        
        if (poolAddress == address(0)) {
            // Create a new pool if it doesn't exist
            poolAddress = factory.createPool(morpherTokenAddress, WETH, FEE);
            console.log("New pool created at:", poolAddress);
            
            // Initialize the pool with the price
            IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
            
            // Price = 100,000 MPH per 1 WETH
            // For Uniswap, we need sqrtPriceX96 = sqrt(price) * 2^96
            uint160 sqrtPriceX96;
            
            if (pool.token0() == morpherTokenAddress) {
                // If MPH is token0, price = WETH/MPH = 1/100000 = 0.00001
                // sqrt(0.00001) * 2^96 = sqrt(1/100000) * 2^96
                sqrtPriceX96 = 250541448375048000000000000;
                console.log("MPH is token0, WETH is token1");
                console.log("Setting price: 100,000 MPH per 1 WETH");
            } else {
                // If MPH is token1, price = MPH/WETH = 100000
                // sqrt(100000) * 2^96
                sqrtPriceX96 = 25054144837504800000000000000000;
                console.log("WETH is token0, MPH is token1");
                console.log("Setting price: 100,000 MPH per 1 WETH");
            }
            
            pool.initialize(sqrtPriceX96);
            console.log("Pool initialized with price");
        } else {
            console.log("Using existing pool at:", poolAddress);
            
            // Get current pool state
            (uint160 sqrtPriceX96, int24 tick, , , , , ) = IUniswapV3Pool(poolAddress).slot0();
            console.log("Current pool tick:", tick);
            console.log("Current sqrtPriceX96:", uint256(sqrtPriceX96));
        }
        
        return poolAddress;
    }
    
    // Add liquidity to the pool
    function addLiquidityToPool(address poolAddress, address morpherTokenAddress) internal {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        
        // Get token order
        address token0 = pool.token0();
        address token1 = pool.token1();
        console.log("Pool token0:", token0);
        console.log("Pool token1:", token1);
        
        // Prepare to add liquidity with the correct ratio
        // We want 100,000 MPH = 1 WETH (ratio 100,000:1)
        uint256 ethAmount = 1 ether;
        uint256 mphAmount = 100_000 ether; // 100,000 MPH tokens (with 18 decimals)
        
        // // Convert ETH to WETH
        IWETH9(WETH).deposit{value: ethAmount}();
        
        // Check WETH balance
        console.log("WETH balance:", IWETH9(WETH).balanceOf(address(this)) / 1e18);
        
        // Approve tokens for the position manager
        IWETH9(WETH).approve(NONFUNGIBLE_POSITION_MANAGER, ethAmount);
        MorpherToken(morpherTokenAddress).approve(NONFUNGIBLE_POSITION_MANAGER, mphAmount);
        
        // Use a more reasonable tick range instead of the full range
        // The full range is too extreme and can cause issues
        int24 minTick = -840000; // A bit less than MIN_TICK to avoid edge issues
        int24 maxTick = -minTick;  // A bit less than MAX_TICK to avoid edge issues
        
        // Create the mint parameters with inline token amount determination
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
        
        // Mint the position with try/catch to handle errors
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
            
            // Try with a smaller amount as fallback
            console.log("Trying with smaller amounts...");
            
            // Reduce amounts by half
            uint256 reducedEthAmount = ethAmount / 2;
            uint256 reducedMphAmount = mphAmount / 2;
            
            // Update approvals
            IWETH9(WETH).approve(NONFUNGIBLE_POSITION_MANAGER, reducedEthAmount);
            MorpherToken(morpherTokenAddress).approve(NONFUNGIBLE_POSITION_MANAGER, reducedMphAmount);
            
            // Create new params with reduced amounts
            INonfungiblePositionManager.MintParams memory reducedParams = INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: FEE,
                tickLower: minTick,
                tickUpper: maxTick,
                amount0Desired: token0 == morpherTokenAddress ? reducedMphAmount : reducedEthAmount,
                amount1Desired: token0 == morpherTokenAddress ? reducedEthAmount : reducedMphAmount,
                amount0Min: 0,
                amount1Min: 0,
                recipient: msg.sender,
                deadline: block.timestamp + 15 minutes
            });
            
            try INonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER).mint(reducedParams) returns (
                uint256 tokenId, 
                uint128 liquidity, 
                uint256 amount0Mint, 
                uint256 amount1Mint
            ) {
                console.log("Liquidity position created with reduced amounts:");
                console.log("- Token ID:", tokenId);
                console.log("- Liquidity:", uint256(liquidity));
                console.log("- Amount token0 used:", amount0Mint);
                console.log("- Amount token1 used:", amount1Mint);
            } catch Error(string memory fallbackReason) {
                console.log("Failed to mint position with reduced amounts: %s", fallbackReason);
            } catch {
                console.log("Failed to mint position with reduced amounts: unknown error");
            }
        } catch {
            console.log("Failed to mint position: unknown error");
        }
    }
    
    // Helper function to burn a position if needed
    function burnPosition(uint256 tokenId) internal {
        INonfungiblePositionManager posManager = INonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER);
        
        // Get position details
        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,
        ) = posManager.positions(tokenId);
        
        console.log("Position details:");
        console.log("- Token0: %s", token0);
        console.log("- Token1: %s", token1);
        console.log("- Fee: %d", fee);
        console.log("- Liquidity: %d", uint256(liquidity));
        
        if (liquidity > 0) {
            // Decrease liquidity
            console.log("Decreasing liquidity...");
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
            console.log("- Amount token0: %d", amount0);
            console.log("- Amount token1: %d", amount1);
            
            // Collect all tokens
            console.log("Collecting tokens...");
            (uint256 collected0, uint256 collected1) = posManager.collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: tokenId,
                    recipient: address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );
            
            console.log("Tokens collected:");
            console.log("- Amount token0: %d", collected0);
            console.log("- Amount token1: %d", collected1);
        }
        
        // Finally burn the position
        posManager.burn(tokenId);
        console.log("Position with token ID %d successfully burned", tokenId);
    }
}
