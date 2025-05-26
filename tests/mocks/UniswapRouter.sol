// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "../../lib/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import "../../lib/openzeppelin-contracts-5/contracts/token/ERC20/IERC20.sol";
import "../../lib/uniswap-v3-periphery/contracts/interfaces/external/IWETH9.sol";
import "../../lib/forge-std/src/console2.sol";

contract MockUniswapRouter is IV3SwapRouter {
	uint256 public mockAmountOut;
	address public mockWethAddress; // To store the address of the mock WETH

	function setWethAddress(address _wethAddress) public { // Setter for mock WETH address
		mockWethAddress = _wethAddress;
	}

	function WETH9() external view returns (address) { // Implementation of WETH9
		require(mockWethAddress != address(0), "MockUniswapRouter: Mock WETH address not set");
		return mockWethAddress;
	}

	function setAmountOut(uint256 _amountOut) public {
		mockAmountOut = _amountOut;
	}

	function exactInput(ExactInputParams calldata params) external payable override returns (uint256 amountOut) {
		if (mockAmountOut > 0) {
			amountOut = mockAmountOut;
		} else {
			amountOut = params.amountOutMinimum;
		}
		(address start, address end) = extractFirstAndLastAddress(params.path);
		IERC20 tokenIn = IERC20(start);
		IERC20 tokenOut = IERC20(end); // This should be wethMock

		console2.log("MockUniswapRouter.exactInput CALLED");
		console2.log("  Router WETH balance (tokenOut) BEFORE tokenIn.transferFrom:", tokenOut.balanceOf(address(this)));
		console2.log("  Bridge WETH balance (params.recipient) BEFORE tokenIn.transferFrom:", tokenOut.balanceOf(params.recipient));
		console2.log("  Bridge MPH balance (tokenIn) BEFORE tokenIn.transferFrom:", tokenIn.balanceOf(msg.sender));
		console2.log("  Router MPH balance (tokenIn) BEFORE tokenIn.transferFrom:", tokenIn.balanceOf(address(this)));
		
		tokenIn.transferFrom(msg.sender, address(this), params.amountIn); // Bridge -> Router (MPH)
		
		console2.log("MockUniswapRouter.exactInput - AFTER tokenIn.transferFrom");
		console2.log("  Router WETH balance (tokenOut) AFTER tokenIn.transferFrom:", tokenOut.balanceOf(address(this)));
		console2.log("  Bridge WETH balance (params.recipient) AFTER tokenIn.transferFrom:", tokenOut.balanceOf(params.recipient));
		console2.log("  Bridge MPH balance (tokenIn) AFTER tokenIn.transferFrom:", tokenIn.balanceOf(msg.sender));
		console2.log("  Router MPH balance (tokenIn) AFTER tokenIn.transferFrom:", tokenIn.balanceOf(address(this)));

		tokenOut.transfer(params.recipient, amountOut); // Router -> Bridge (WETH)

		console2.log("MockUniswapRouter.exactInput - AFTER tokenOut.transfer");
		console2.log("  Router WETH balance (tokenOut) AFTER tokenOut.transfer:", tokenOut.balanceOf(address(this)));
		console2.log("  Bridge WETH balance (params.recipient) AFTER tokenOut.transfer:", tokenOut.balanceOf(params.recipient));
	}

	function exactInputSingle(ExactInputSingleParams calldata params) external payable override returns (uint256 amountOut) { 
		console2.log("MockUniswapRouter.exactInputSingle: ENTERED"); 
		
		if (mockAmountOut > 0) {
			amountOut = mockAmountOut;
		} else {
			amountOut = params.amountOutMinimum; 
		}

		IERC20 tokenIn = IERC20(params.tokenIn);
		IERC20 tokenOut = IERC20(params.tokenOut); // This should be wethMock

		console2.log("  MockUniswapRouter.exactInputSingle - msg.sender (Bridge):", msg.sender);
		console2.log("  MockUniswapRouter.exactInputSingle - Router address (this):", address(this));
		console2.log("  MockUniswapRouter.exactInputSingle - tokenIn:", address(tokenIn));
		console2.log("  MockUniswapRouter.exactInputSingle - tokenOut:", address(tokenOut));
		console2.log("  MockUniswapRouter.exactInputSingle - params.amountIn:", params.amountIn);
		console2.log("  MockUniswapRouter.exactInputSingle - calculated amountOut:", amountOut);
		console2.log("  MockUniswapRouter.exactInputSingle - params.recipient (should be Bridge):", params.recipient);

		uint256 allowance = tokenIn.allowance(msg.sender, address(this));
		console2.log("  MockUniswapRouter.exactInputSingle - Allowance tokenIn for router by bridge:", allowance);
		uint256 bridgeTokenInBalance = tokenIn.balanceOf(msg.sender);
		console2.log("  MockUniswapRouter.exactInputSingle - Bridge balance of tokenIn:", bridgeTokenInBalance);

		// Router receives tokenIn from the caller (MorpherBridge)
		tokenIn.transferFrom(msg.sender, address(this), params.amountIn);
		console2.log("  MockUniswapRouter.exactInputSingle - tokenIn.transferFrom successful");

		uint256 routerTokenOutBalance = tokenOut.balanceOf(address(this));
		console2.log("  MockUniswapRouter.exactInputSingle - Router balance of tokenOut (WETH):", routerTokenOutBalance);

		// Router sends tokenOut (WETH) to the recipient (MorpherBridge)
		// Ensure the mock router has enough tokenOut balance (seeded in test setup)
		tokenOut.transfer(params.recipient, amountOut);
		console2.log("  MockUniswapRouter.exactInputSingle - tokenOut.transfer successful to recipient:", params.recipient);
	}

	function exactOutput(ExactOutputParams calldata  /*unused*/) external payable returns (uint256 amountIn) {
		amountIn = 0;
	}

	function exactOutputSingle(ExactOutputSingleParams calldata /*unused*/) external payable returns (uint256 amountIn) {
		amountIn = 0;
	}

	function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {}

	function extractFirstAndLastAddress(
		bytes memory path
	) public pure returns (address firstAddress, address lastAddress) {
		require(path.length >= 40, "Path too short");

		assembly {
			firstAddress := div(mload(add(path, 32)), 0x1000000000000000000000000)
		}

		assembly {
			lastAddress := div(mload(add(add(path, 32), sub(mload(path), 20))), 0x1000000000000000000000000)
		}
	}
}
