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

interface IPositionManager {
    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results);
    
    function modifyLiquidities(
        bytes calldata data,
        uint256 deadline
    ) external payable returns (bytes memory result);
}

interface IPoolInitializer {
    function initializePool(
        PoolKey calldata key,
        uint160 sqrtPriceX96
    ) external returns (address pool);
}

interface IPermit2 {
    function approve(
        address token,
        address spender,
        uint160 amount,
        uint48 expiration
    ) external;
}

// Uniswap v4 types
struct PoolKey {
    address currency0;
    address currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

// Enum for actions in modifyLiquidities
enum Actions {
    MINT_POSITION,
    SETTLE_PAIR
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
    address public POSITION_MANAGER;
    address public UNIVERSAL_ROUTER;
    address public PERMIT2;
    address public WETH;
    address public HOOKS; // No hooks for this example
    uint24 constant FEE = 3000; // 0.3%
    int24 constant TICK_SPACING = 60; // For 0.3% fee

    // Set up addresses based on the chain we're deploying to
    function setupAddresses() internal {
        uint256 chainId = block.chainid;
    
        // WETH is the same on both Base and Base Sepolia
        WETH = 0x4200000000000000000000000000000000000006;
        HOOKS = address(0); // No hooks for this example
    
        if (chainId == 8453) {
            // Base Mainnet
            POOL_MANAGER = 0x498581ff718922c3f8e6a244956af099b2652b2b;
            POSITION_MANAGER = 0x7c5f5a4bbd8fd63184577525326123b519429bdc;
            UNIVERSAL_ROUTER = 0x6ff5693b99212da76ad316178a184ab56d299b43;
            PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // Standard permit2 address
        } else if (chainId == 84532) {
            // Base Sepolia
            POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
            POSITION_MANAGER = 0x4b2c77d209d3405f41a037ec6c77f7f5b8e2ca80;
            UNIVERSAL_ROUTER = 0x492e6456d9528771018deb9e87ef7750ef184104;
            PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // Standard permit2 address
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
        console.log("Using Position Manager:", POSITION_MANAGER);
        
        // Load MorpherToken address
        address morpherTokenAddress = loadAddress("MorpherToken");
        require(morpherTokenAddress != address(0), "MorpherToken must be deployed first");
        
        console.log("MorpherToken address:", morpherTokenAddress);
        console.log("WETH address:", WETH);

        // Create pool and add liquidity in one transaction
        address poolAddress = createPoolAndAddLiquidity(morpherTokenAddress);
        
        // Save the pool address
        saveAddress("UniswapV4Pool", poolAddress);
        
        vm.stopBroadcast();
    }
    
    // Create pool and add liquidity in one transaction using multicall
    function createPoolAndAddLiquidity(address morpherTokenAddress) internal returns (address poolAddress) {
        // 1. Initialize the parameters for multicall
        bytes[] memory params = new bytes[](2);
        
        // 2. Configure the pool
        PoolKey memory pool = PoolKey({
            currency0: morpherTokenAddress < WETH ? morpherTokenAddress : WETH,
            currency1: morpherTokenAddress < WETH ? WETH : morpherTokenAddress,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOKS
        });
        
        console.log("Pool configuration:");
        console.log("- Currency0:", pool.currency0);
        console.log("- Currency1:", pool.currency1);
        console.log("- Fee:", pool.fee);
        console.log("- TickSpacing:", pool.tickSpacing);
        
        // 3. Encode initializePool parameters
        // Price = 100,000 MPH per 1 WETH
        uint160 sqrtPriceX96;
        if (pool.currency0 == morpherTokenAddress) {
            // If MPH is token0, price = WETH/MPH = 1/100000 = 0.00001
            // sqrt(0.00001) * 2^96 = sqrt(1/100000) * 2^96
            sqrtPriceX96 = 2505414483809435;
            console.log("MPH is token0, WETH is token1");
            console.log("Setting price: 100,000 MPH per 1 WETH");
        } else {
            // If MPH is token1, price = MPH/WETH = 100000
            // sqrt(100000) * 2^96
            sqrtPriceX96 = 25054144837438405210904448839064;
            console.log("WETH is token0, MPH is token1");
            console.log("Setting price: 100,000 MPH per 1 WETH");
        }
        
        params[0] = abi.encodeWithSelector(
            IPoolInitializer.initializePool.selector,
            pool,
            sqrtPriceX96
        );
        
        // 4. Initialize mint-liquidity parameters
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));
        
        // 5. Encode MINT_POSITION parameters
        bytes[] memory mintParams = new bytes[](2);
        
        // Define liquidity parameters
        int24 tickLower = -887272; // Full range
        int24 maxTick = 887272;
        uint128 liquidity = 1000000000000000000; // 1.0 in Uniswap liquidity units
        uint256 ethAmount = 1 ether;
        uint256 mphAmount = 100000 ether; // 100,000 MPH tokens
        
        // Determine token amounts based on token order
        uint256 amount0Max = pool.currency0 == morpherTokenAddress ? mphAmount : ethAmount;
        uint256 amount1Max = pool.currency0 == morpherTokenAddress ? ethAmount : mphAmount;
        
        // Encode mint parameters
        mintParams[0] = abi.encode(
            pool,
            tickLower,
            maxTick,
            liquidity,
            amount0Max,
            amount1Max,
            msg.sender,
            new bytes(0) // No hook data
        );
        
        // 6. Encode SETTLE_PAIR parameters
        mintParams[1] = abi.encode(pool.currency0, pool.currency1);
        
        // 7. Encode modifyLiquidities call
        uint256 deadline = block.timestamp + 60;
        params[1] = abi.encodeWithSelector(
            IPositionManager.modifyLiquidities.selector,
            abi.encode(actions, mintParams),
            deadline
        );
        
        // 8. Approve tokens
        // Ensure we have enough WETH
        uint256 wethBalance = IWETH9(WETH).balanceOf(msg.sender);
        if (wethBalance < ethAmount) {
            console.log("Not enough WETH, depositing ETH...");
            IWETH9(WETH).deposit{value: ethAmount}();
        }
        
        // Approve tokens for Permit2
        IERC20(WETH).approve(PERMIT2, type(uint256).max);
        IERC20(morpherTokenAddress).approve(PERMIT2, type(uint256).max);
        
        // Approve Position Manager via Permit2
        IPermit2(PERMIT2).approve(WETH, POSITION_MANAGER, type(uint160).max, type(uint48).max);
        IPermit2(PERMIT2).approve(morpherTokenAddress, POSITION_MANAGER, type(uint160).max, type(uint48).max);
        
        console.log("Tokens approved for Position Manager");
        
        // 9. Execute the multicall
        try IPositionManager(POSITION_MANAGER).multicall(params) returns (bytes[] memory results) {
            console.log("Pool created and liquidity added successfully");
            
            // Get the pool address from the results
            poolAddress = IPoolManager(POOL_MANAGER).getPool(
                pool.currency0,
                pool.currency1,
                pool.fee
            );
            
            console.log("Pool address:", poolAddress);
        } catch Error(string memory reason) {
            console.log("Failed to create pool and add liquidity: %s", reason);
            
            // Try to create just the pool without liquidity as fallback
            console.log("Trying to create just the pool without liquidity...");
            
            try IPoolInitializer(POSITION_MANAGER).initializePool(pool, sqrtPriceX96) returns (address _poolAddress) {
                console.log("Pool created successfully at:", _poolAddress);
                poolAddress = _poolAddress;
            } catch Error(string memory fallbackReason) {
                console.log("Failed to create pool: %s", fallbackReason);
                
                // Check if pool already exists
                poolAddress = IPoolManager(POOL_MANAGER).getPool(
                    pool.currency0,
                    pool.currency1,
                    pool.fee
                );
                
                if (poolAddress != address(0)) {
                    console.log("Pool already exists at:", poolAddress);
                } else {
                    console.log("Could not create or find pool");
                }
            } catch {
                console.log("Failed to create pool: unknown error");
            }
        } catch {
            console.log("Failed to create pool and add liquidity: unknown error");
            
            // Check if pool already exists
            poolAddress = IPoolManager(POOL_MANAGER).getPool(
                pool.currency0,
                pool.currency1,
                pool.fee
            );
            
            if (poolAddress != address(0)) {
                console.log("Pool already exists at:", poolAddress);
            } else {
                console.log("Could not create or find pool");
            }
        }
        
        return poolAddress;
    }
}
