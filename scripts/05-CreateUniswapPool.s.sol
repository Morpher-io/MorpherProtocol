//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {DeployOrUpgrade} from "./deployOrUpgrade.sol";

// Uniswap interfaces
interface IUniswapV3Factory {
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);
}

interface IUniswapV3Pool {
    function initialize(uint160 sqrtPriceX96) external;
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );
}

interface IWETH9 {
    function deposit() external payable;
    function approve(address guy, uint wad) external returns (bool);
}

import {MorpherToken} from "../contracts/MorpherToken.sol";

contract CreateUniswapPool is DeployOrUpgrade {
    using stdJson for string;

    // Uniswap V3 addresses on Base
    address constant UNISWAP_V3_FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
    address constant NONFUNGIBLE_POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    uint24 constant FEE = 3000; // 0.3%

    function run() public {
        vm.startBroadcast();

        // Load MorpherToken address
        address morpherTokenAddress = loadAddress("MorpherToken");
        require(morpherTokenAddress != address(0), "MorpherToken must be deployed first");
        
        console.log("MorpherToken address:", morpherTokenAddress);
        console.log("WETH address:", WETH);

        // Create the pool
        IUniswapV3Factory factory = IUniswapV3Factory(UNISWAP_V3_FACTORY);
        address poolAddress = factory.createPool(morpherTokenAddress, WETH, FEE);
        console.log("Pool created at:", poolAddress);

        // Determine token order (Uniswap sorts tokens by address)
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        
        // Initialize the pool with the price
        // Price = 5000 MPH per 0.05 WETH = 100,000 MPH per 1 WETH
        // For Uniswap, we need sqrtPriceX96 = sqrt(price) * 2^96
        // Where price is token1/token0 in the pool
        
        uint160 sqrtPriceX96;
        if (pool.token0() == morpherTokenAddress) {
            // If MPH is token0, price = WETH/MPH = 1/100000 = 0.00001
            sqrtPriceX96 = 79228162514264337593543; // sqrt(0.00001) * 2^96
        } else {
            // If MPH is token1, price = MPH/WETH = 100000
            sqrtPriceX96 = 7922816251426433759354395033; // sqrt(100000) * 2^96
        }
        
        pool.initialize(sqrtPriceX96);
        console.log("Pool initialized with price");

        // Prepare to add liquidity
        uint256 ethAmount = 0.05 ether;
        uint256 mphAmount = 5000 ether; // 5000 MPH tokens (with 18 decimals)
        
        // Convert ETH to WETH
        IWETH9(WETH).deposit{value: ethAmount}();
        
        // Approve tokens for the position manager
        IWETH9(WETH).approve(NONFUNGIBLE_POSITION_MANAGER, ethAmount);
        MorpherToken(morpherTokenAddress).approve(NONFUNGIBLE_POSITION_MANAGER, mphAmount);
        
        // Calculate ticks for the position
        // For a full range position, we can use min and max ticks
        int24 minTick = -887272;
        int24 maxTick = 887272;
        
        // Add liquidity
        INonfungiblePositionManager posManager = INonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER);
        
        INonfungiblePositionManager.MintParams memory params;
        
        if (pool.token0() == morpherTokenAddress) {
            params = INonfungiblePositionManager.MintParams({
                token0: morpherTokenAddress,
                token1: WETH,
                fee: FEE,
                tickLower: minTick,
                tickUpper: maxTick,
                amount0Desired: mphAmount,
                amount1Desired: ethAmount,
                amount0Min: 0,
                amount1Min: 0,
                recipient: msg.sender,
                deadline: block.timestamp + 15 minutes
            });
        } else {
            params = INonfungiblePositionManager.MintParams({
                token0: WETH,
                token1: morpherTokenAddress,
                fee: FEE,
                tickLower: minTick,
                tickUpper: maxTick,
                amount0Desired: ethAmount,
                amount1Desired: mphAmount,
                amount0Min: 0,
                amount1Min: 0,
                recipient: msg.sender,
                deadline: block.timestamp + 15 minutes
            });
        }
        
        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = posManager.mint(params);
        
        console.log("Liquidity position created:");
        console.log("- Token ID:", tokenId);
        console.log("- Liquidity:", uint256(liquidity));
        console.log("- Amount token0 used:", amount0);
        console.log("- Amount token1 used:", amount1);
        
        // Save the pool address
        saveAddress("UniswapV3Pool", poolAddress);
        
        vm.stopBroadcast();
    }
}
