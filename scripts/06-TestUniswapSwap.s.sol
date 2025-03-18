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
        
        // 3. Approve WETH to Permit2
        IWETH9(WETH).approve(PERMIT2, swapAmount);
        console.log("Approved WETH to Permit2");
        
        // 4. Approve Permit2 to Universal Router
        IPermit2(PERMIT2).approve(WETH, UNIVERSAL_ROUTER, uint160(swapAmount), uint48(block.timestamp + 1 hours));
        console.log("Approved Permit2 to Universal Router");

        // 5. Prepare the swap command
        bytes memory commands = abi.encodePacked(uint8(Commands.V3_SWAP_EXACT_IN));
        
        // 6. Prepare the swap inputs
        bytes[] memory inputs = new bytes[](1);
        
        // Encode the path for the swap (WETH -> MPH)
        // The path is encoded as a sequence of (tokenIn, fee, tokenOut)
        uint24 poolFee = 3000; // 0.3%
        bytes memory path = abi.encodePacked(WETH, poolFee, morpherTokenAddress);
        
        // Encode the parameters for the V3_SWAP_EXACT_IN command
        inputs[0] = abi.encode(
            msg.sender,                  // recipient
            swapAmount,                  // amountIn
            0,                           // amountOutMinimum (0 for simplicity, but in production use a real value)
            path,                        // path
            true                         // payerIsUser - true means the tokens come from the caller via Permit2
        );
        
        // 7. Execute the swap
        uint256 deadline = block.timestamp + 1 hours;
        IUniversalRouter(UNIVERSAL_ROUTER).execute(commands, inputs, deadline);
        
        // 8. Check MPH balance after swap
        uint256 mphBalance = IERC20(morpherTokenAddress).balanceOf(msg.sender);
        console.log("MPH balance after swap:", mphBalance);
        
        vm.stopBroadcast();
    }
}
