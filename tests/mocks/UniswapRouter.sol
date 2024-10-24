// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract MockUniswapRouter is ISwapRouter {
	function exactInput(ExactInputParams calldata params) external payable override returns (uint256 amountOut) {
		amountOut = params.amountOutMinimum;
		(address start, address end) = extractFirstAndLastAddress(params.path);
		IERC20 tokenIn = IERC20(start);
		IERC20 tokenOut = IERC20(end);
		tokenIn.transferFrom(msg.sender, address(this), params.amountIn);
		tokenOut.transfer(params.recipient, amountOut);
	}

	function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut) {
		amountOut = 0;
	}

	function exactOutput(ExactOutputParams calldata params) external payable returns (uint256 amountIn) {
		amountIn = 0;
	}

	function exactOutputSingle(ExactOutputSingleParams calldata params) external payable returns (uint256 amountIn) {
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
