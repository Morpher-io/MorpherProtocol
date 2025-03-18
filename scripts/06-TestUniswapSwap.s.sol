//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {DeployOrUpgrade} from "./deployOrUpgrade.sol";
import {MorpherToken} from "../contracts/MorpherToken.sol";

// Universal Router imports
import {Commands} from "../lib/universal-router/contracts/libraries/Commands.sol";
import {IUniversalRouter} from "../lib/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {IPermit2} from "../lib/permit2/src/interfaces/IPermit2.sol";
import {MorpherSwapHelper} from "./MorpherSwapHelper.sol";

// Uniswap V3 imports
import {IV3SwapRouter} from "../lib/universal-router/contracts/interfaces/external/IV3SwapRouter.sol";

interface IWETH9 {
    function deposit() external payable;
    function approve(address guy, uint wad) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract TestUniswapSwap is DeployOrUpgrade {
    using stdJson for string;

    // Universal Router addresses - will be set based on chainId
    address public UNIVERSAL_ROUTER;
    address public PERMIT2;
    address public WETH;
    address public SWAP_HELPER;

    // Set up addresses based on the chain we're deploying to
    function setupAddresses() internal {
        uint256 chainId = block.chainid;
    
        // WETH is the same on both Base and Base Sepolia
        WETH = 0x4200000000000000000000000000000000000006;
    
        if (chainId == 8453) {
            // Base Mainnet
            UNIVERSAL_ROUTER = 0x6ff5693b99212da76ad316178a184ab56d299b43;
            PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        } else if (chainId == 84532) {
            // Base Sepolia
            UNIVERSAL_ROUTER = 0x492e6456d9528771018deb9e87ef7750ef184104;
            PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        } else {
            revert("Unsupported chain ID");
        }
    }

    function run() public {
        // Set up the correct addresses based on the chain
        setupAddresses();
        
        vm.startBroadcast();

        console.log("Testing swap on chain ID:", uint256(block.chainid));
        console.log("Using Universal Router:", UNIVERSAL_ROUTER);
        console.log("Using Permit2:", PERMIT2);
        
        // Load MorpherToken address
        address morpherTokenAddress = loadAddress("MorpherToken");
        require(morpherTokenAddress != address(0), "MorpherToken must be deployed first");
        
        console.log("MorpherToken address:", morpherTokenAddress);
        console.log("WETH address:", WETH);

        // Prepare for swap
        // 1. Convert ETH to WETH
        uint256 swapAmount = 0.005 ether;
        IWETH9(WETH).deposit{value: swapAmount}();
        
        // 2. Check WETH balance
        uint256 wethBalance = IWETH9(WETH).balanceOf(msg.sender);
        console.log("WETH balance:", wethBalance);
        
        // Load SwapHelper address
        SWAP_HELPER = loadAddress("MorpherSwapHelper");
        if (SWAP_HELPER == address(0)) {
            // If not deployed yet, deploy it
            MorpherSwapHelper swapHelper = new MorpherSwapHelper(UNIVERSAL_ROUTER, PERMIT2);
            SWAP_HELPER = address(swapHelper);
            saveAddress("MorpherSwapHelper", SWAP_HELPER);
            console.log("Deployed new MorpherSwapHelper at:", SWAP_HELPER);
        } else {
            console.log("Using existing MorpherSwapHelper at:", SWAP_HELPER);
        }

        // 3. Approve WETH to SwapHelper
        IWETH9(WETH).approve(SWAP_HELPER, swapAmount);
        console.log("Approved WETH to SwapHelper");
        
        // Encode the path for the swap (WETH -> MPH)
        uint24 poolFee = 3000; // 0.3%
        bytes memory path = abi.encodePacked(WETH, poolFee, morpherTokenAddress);
        
        // For testing purposes, we'll use a mock permit signature (all zeros)
        // In a real scenario, this would be a valid signature
        uint8 v = 0;
        bytes32 r = bytes32(0);
        bytes32 s = bytes32(0);
        
        // Execute the swap through the helper
        // In a real scenario, we would use the permit signature
        uint256 deadline = block.timestamp + 1 hours;
        
        // For testing, we'll directly approve the tokens instead of using permit
        IWETH9(WETH).approve(SWAP_HELPER, swapAmount);
        
        // Transfer tokens to the helper
        // Note: In production, this would be handled by the helper using the permit
        IWETH9(WETH).transfer(SWAP_HELPER, swapAmount);
        
        // Execute the swap through the helper
        MorpherSwapHelper(SWAP_HELPER).swapWithPermit(
            WETH,                       // inputToken
            morpherTokenAddress,        // outputToken
            swapAmount,                 // amountIn
            0,                          // amountOutMin
            path,                       // path
            deadline,                   // deadline
            deadline,                   // permitDeadline
            v, r, s                     // signature components
        );
        
        // 8. Check MPH balance after swap
        uint256 mphBalance = IERC20(morpherTokenAddress).balanceOf(msg.sender);
        console.log("MPH balance after swap:", mphBalance);
        
        vm.stopBroadcast();
    }
}
