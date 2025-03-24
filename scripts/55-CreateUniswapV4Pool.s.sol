//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {DeployOrUpgrade} from "./deployOrUpgrade.sol";
import {MorpherToken} from "../contracts/MorpherToken.sol";

// Uniswap v4 interfaces
interface IPoolManager {
    function initialize(
        address tokenA,
        address tokenB,
        uint24 fee,
        uint160 sqrtPriceX96,
        bytes calldata hookData
    ) external returns (address pool);
    
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pool);
}

interface IHooks {
    function beforeInitialize(
        address tokenA,
        address tokenB,
        uint24 fee,
        uint160 sqrtPriceX96,
        bytes calldata hookData
    ) external returns (bytes4);
    
    function afterInitialize(
        address tokenA,
        address tokenB,
        uint24 fee,
        uint160 sqrtPriceX96,
        bytes calldata hookData
    ) external returns (bytes4);
}

interface ILiquidityManager {
    struct ModifyPositionParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        int256 liquidityDelta;
        address recipient;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }
    
    function modifyPosition(
        ModifyPositionParams calldata params
    ) external returns (uint256 amount0, uint256 amount1);
}

interface IWETH9 {
    function deposit() external payable;
    function approve(address guy, uint wad) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract CreateUniswapV4Pool is DeployOrUpgrade {
    using stdJson for string;

    // Uniswap V4 addresses - will be set based on chainId
    address public POOL_MANAGER;
    address public LIQUIDITY_MANAGER;
    address public WETH;
    uint24 constant FEE = 3000; // 0.3%

    // Set up addresses based on the chain we're deploying to
    function setupAddresses() internal {
        uint256 chainId = block.chainid;
    
        // WETH is the same on both Base and Base Sepolia
        WETH = 0x4200000000000000000000000000000000000006;
    
        if (chainId == 8453) {
            // Base Mainnet
            POOL_MANAGER = 0x1234567890123456789012345678901234567890; // Replace with actual address
            LIQUIDITY_MANAGER = 0x1234567890123456789012345678901234567890; // Replace with actual address
        } else if (chainId == 84532) {
            // Base Sepolia
            POOL_MANAGER = 0x1234567890123456789012345678901234567890; // Replace with actual address
            LIQUIDITY_MANAGER = 0x1234567890123456789012345678901234567890; // Replace with actual address
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
        console.log("Using Liquidity Manager:", LIQUIDITY_MANAGER);
        
        // Load MorpherToken address
        address morpherTokenAddress = loadAddress("MorpherToken");
        require(morpherTokenAddress != address(0), "MorpherToken must be deployed first");
        
        console.log("MorpherToken address:", morpherTokenAddress);
        console.log("WETH address:", WETH);

        // Initialize or get pool
        address poolAddress = initializeOrGetPool(morpherTokenAddress);
        
        // Add liquidity to the pool
        addLiquidityToPool(poolAddress, morpherTokenAddress);
        
        // Save the pool address
        saveAddress("UniswapV4Pool", poolAddress);
        
        vm.stopBroadcast();
    }
    
    // Initialize a new pool or get existing pool
    function initializeOrGetPool(address morpherTokenAddress) internal returns (address poolAddress) {
        // Check if pool already exists
        IPoolManager poolManager = IPoolManager(POOL_MANAGER);
        poolAddress = poolManager.getPool(morpherTokenAddress, WETH, FEE);
        
        if (poolAddress == address(0)) {
            // Create a new pool if it doesn't exist
            // Price = 100,000 MPH per 1 WETH
            // For Uniswap, we need sqrtPriceX96 = sqrt(price) * 2^96
            uint160 sqrtPriceX96;
            
            // Determine token order (Uniswap v4 sorts tokens by address)
            bool mphIsToken0 = morpherTokenAddress < WETH;
            
            if (mphIsToken0) {
                // If MPH is token0, price = WETH/MPH = 1/100000 = 0.00001
                // sqrt(0.00001) * 2^96
                sqrtPriceX96 = 79228162514264337593543;
                console.log("MPH is token0, WETH is token1");
                console.log("Setting price: 100,000 MPH per 1 WETH");
            } else {
                // If MPH is token1, price = MPH/WETH = 100000
                // sqrt(100000) * 2^96
                sqrtPriceX96 = 7922816251426433759354395033;
                console.log("WETH is token0, MPH is token1");
                console.log("Setting price: 100,000 MPH per 1 WETH");
            }
            
            // Initialize the pool with empty hook data
            bytes memory hookData = new bytes(0);
            poolAddress = poolManager.initialize(
                morpherTokenAddress,
                WETH,
                FEE,
                sqrtPriceX96,
                hookData
            );
            
            console.log("New pool created at:", poolAddress);
        } else {
            console.log("Using existing pool at:", poolAddress);
        }
        
        return poolAddress;
    }
    
    // Add liquidity to the pool
    function addLiquidityToPool(address poolAddress, address morpherTokenAddress) internal {
        // Determine token order (Uniswap v4 sorts tokens by address)
        address token0 = morpherTokenAddress < WETH ? morpherTokenAddress : WETH;
        address token1 = morpherTokenAddress < WETH ? WETH : morpherTokenAddress;
        
        console.log("Pool token0:", token0);
        console.log("Pool token1:", token1);
        
        // Prepare to add liquidity with the correct ratio
        // We want 100,000 MPH = 1 WETH (ratio 100,000:1)
        uint256 ethAmount = 1 ether;
        uint256 mphAmount = 100000 ether; // 100,000 MPH tokens (with 18 decimals)
        
        // Ensure we have enough WETH
        uint256 wethBalance = IWETH9(WETH).balanceOf(msg.sender);
        if (wethBalance < ethAmount) {
            console.log("Not enough WETH, depositing ETH...");
            IWETH9(WETH).deposit{value: ethAmount}();
        }
        
        // Approve tokens for the liquidity manager
        IWETH9(WETH).approve(LIQUIDITY_MANAGER, ethAmount);
        MorpherToken(morpherTokenAddress).approve(LIQUIDITY_MANAGER, mphAmount);
        
        // Use a reasonable tick range
        int24 tickSpacing = 60; // 0.3% fee tier has 60 tick spacing
        int24 minTick = -887272 / tickSpacing * tickSpacing; // Round to nearest tick spacing
        int24 maxTick = 887272 / tickSpacing * tickSpacing;
        
        // Create the modify position parameters
        ILiquidityManager.ModifyPositionParams memory params = ILiquidityManager.ModifyPositionParams({
            token0: token0,
            token1: token1,
            fee: FEE,
            tickLower: minTick,
            tickUpper: maxTick,
            liquidityDelta: 1000000000000000000, // Positive value to add liquidity
            recipient: msg.sender,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp + 15 minutes
        });
        
        // Add liquidity with try/catch to handle errors
        try ILiquidityManager(LIQUIDITY_MANAGER).modifyPosition(params) returns (
            uint256 amount0, 
            uint256 amount1
        ) {
            console.log("Liquidity position created:");
            console.log("- Amount token0 used:", amount0);
            console.log("- Amount token1 used:", amount1);
        } catch Error(string memory reason) {
            console.log("Failed to add liquidity: %s", reason);
            
            // Try with a smaller amount as fallback
            console.log("Trying with smaller amounts...");
            
            // Reduce amounts by half
            uint256 reducedEthAmount = ethAmount / 2;
            uint256 reducedMphAmount = mphAmount / 2;
            
            // Update approvals
            IWETH9(WETH).approve(LIQUIDITY_MANAGER, reducedEthAmount);
            MorpherToken(morpherTokenAddress).approve(LIQUIDITY_MANAGER, reducedMphAmount);
            
            // Create new params with reduced amounts
            ILiquidityManager.ModifyPositionParams memory reducedParams = ILiquidityManager.ModifyPositionParams({
                token0: token0,
                token1: token1,
                fee: FEE,
                tickLower: minTick,
                tickUpper: maxTick,
                liquidityDelta: 500000000000000000, // Half the original liquidity
                recipient: msg.sender,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 15 minutes
            });
            
            try ILiquidityManager(LIQUIDITY_MANAGER).modifyPosition(reducedParams) returns (
                uint256 amount0, 
                uint256 amount1
            ) {
                console.log("Liquidity position created with reduced amounts:");
                console.log("- Amount token0 used:", amount0);
                console.log("- Amount token1 used:", amount1);
            } catch Error(string memory fallbackReason) {
                console.log("Failed to add liquidity with reduced amounts: %s", fallbackReason);
            } catch {
                console.log("Failed to add liquidity with reduced amounts: unknown error");
            }
        } catch {
            console.log("Failed to add liquidity: unknown error");
        }
    }
}
