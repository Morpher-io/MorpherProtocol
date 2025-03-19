//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {DeployOrUpgrade} from "./deployOrUpgrade.sol";
import {MorpherToken} from "../contracts/MorpherToken.sol";
import {INonfungiblePositionManager} from "../lib/uniswap-v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

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

        // Check if pool already exists
        IUniswapV3Factory factory = IUniswapV3Factory(UNISWAP_V3_FACTORY);
        address poolAddress = factory.getPool(morpherTokenAddress, WETH, FEE);
        
        if (poolAddress == address(0)) {
            // Create a new pool if it doesn't exist
            poolAddress = factory.createPool(morpherTokenAddress, WETH, FEE);
            console.log("New pool created at:", poolAddress);
            
            // Initialize the pool with the price
            IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
            
            // Determine token order (Uniswap sorts tokens by address)
            address token0 = pool.token0();
            address token1 = pool.token1();
            
            // Price = 5000 MPH per 0.05 WETH = 100,000 MPH per 1 WETH
            // For Uniswap, we need sqrtPriceX96 = sqrt(price) * 2^96
            // Where price is token1/token0 in the pool
            uint160 sqrtPriceX96;
            
            if (token0 == morpherTokenAddress) {
                // If MPH is token0, price = WETH/MPH = 1/100000 = 0.00001
                // sqrt(0.00001) * 2^96
                sqrtPriceX96 = 79228162514264337593543;
                console.log("MPH is token0, WETH is token1");
            } else {
                // If MPH is token1, price = MPH/WETH = 100000
                // sqrt(100000) * 2^96
                sqrtPriceX96 = 7922816251426433759354395033;
                console.log("WETH is token0, MPH is token1");
            }
            
            pool.initialize(sqrtPriceX96);
            console.log("Pool initialized with price");
        } else {
            console.log("Using existing pool at:", poolAddress);
            
            // Get current pool state
            IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
            (uint160 sqrtPriceX96, int24 tick, , , , , ) = pool.slot0();
            console.log("Current pool tick:", tick);
            console.log("Current sqrtPriceX96:", uint256(sqrtPriceX96));
        }

        // Get the pool instance
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        
        // Get token order
        address token0 = pool.token0();
        address token1 = pool.token1();
        console.log("Pool token0:", token0);
        console.log("Pool token1:", token1);
        
        // Check if we need to burn any existing positions
        INonfungiblePositionManager posManager = INonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER);
        
        // Prepare to add liquidity with the correct ratio
        // We want 5000 MPH = 0.05 WETH (ratio 100,000:1)
        uint256 ethAmount = 0.05 ether;
        uint256 mphAmount = 5000 ether; // 5000 MPH tokens (with 18 decimals)
        
        // Convert ETH to WETH
        IWETH9(WETH).deposit{value: ethAmount}();
        
        // Check WETH balance
        uint256 wethBalance = IWETH9(WETH).balanceOf(address(this));
        console.log("WETH balance:", wethBalance / 1e18);
        
        // Approve tokens for the position manager
        IWETH9(WETH).approve(NONFUNGIBLE_POSITION_MANAGER, ethAmount);
        MorpherToken(morpherTokenAddress).approve(NONFUNGIBLE_POSITION_MANAGER, mphAmount);
        
        // Calculate ticks for the position
        // Use a more reasonable tick range instead of the full range
        int24 minTick = -46080; // Approximately 1/100 of the current price
        int24 maxTick = 46080;  // Approximately 100x the current price
        
        // Determine which amounts go with which token
        uint256 amount0;
        uint256 amount1;
        
        if (token0 == morpherTokenAddress) {
            amount0 = mphAmount;
            amount1 = ethAmount;
        } else {
            amount0 = ethAmount;
            amount1 = mphAmount;
        }
        
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
        (uint256 tokenId, uint128 liquidity, uint256 amount0Mint, uint256 amount1Mint) = posManager.mint(params);
        
        console.log("Liquidity position created:");
        console.log("- Token ID:", tokenId);
        console.log("- Liquidity:", uint256(liquidity));
        console.log("- Amount token0 used:", amount0Mint);
        console.log("- Amount token1 used:", amount1Mint);
        
        // Save the pool address
        saveAddress("UniswapV3Pool", poolAddress);
        
        vm.stopBroadcast();
    }
    
    // Helper function to burn a position if needed
    function burnPosition(uint256 tokenId) internal {
        INonfungiblePositionManager posManager = INonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER);
        
        // First decrease all liquidity
        (,,,,,,,uint128 liquidity,,,,) = posManager.positions(tokenId);
        
        if (liquidity > 0) {
            INonfungiblePositionManager.DecreaseLiquidityParams memory params = 
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: tokenId,
                    liquidity: liquidity,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp + 15 minutes
                });
                
            (uint256 amount0, uint256 amount1) = posManager.decreaseLiquidity(params);
            console.log("Decreased liquidity from position:");
            console.log("- Amount token0 received:", amount0);
            console.log("- Amount token1 received:", amount1);
        }
        
        // Then collect all fees and tokens
        INonfungiblePositionManager.CollectParams memory collectParams = 
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });
            
        (uint256 collected0, uint256 collected1) = posManager.collect(collectParams);
        console.log("Collected from position:");
        console.log("- Amount token0 collected:", collected0);
        console.log("- Amount token1 collected:", collected1);
        
        // Finally burn the position
        posManager.burn(tokenId);
        console.log("Burned position with token ID:", tokenId);
    }
}
