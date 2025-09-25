//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.15;

import {IERC20Permit} from "../../lib/openzeppelin-contracts-5/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "../../lib/openzeppelin-contracts-5/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts-5/contracts/token/ERC20/utils/SafeERC20.sol";
import {IV3SwapRouter} from "../../lib/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import {IWETH9} from "../../lib/uniswap-v3-periphery/contracts/interfaces/external/IWETH9.sol";

library UniswapHelper {
    struct TokenPermitEIP712Struct {
        address tokenAddress;
        address owner;
        uint256 value;
        uint256 minOutValue;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    uint24 public constant poolFee = 3000;

    event MphCloseOrderSoftFail(bytes32 _orderId, uint _mphTokenAmountCloseOrder, uint _mphTokenAmountPermit);

    function permitTransferAndSwap(
        address uniswapRouter,
        address wMaticAddress,
        address morpherTokenAddress,
        address msgSender,
        TokenPermitEIP712Struct memory inputToken,
        uint256 mphTokenAmount
    ) public returns (uint amountOut) {
        //increase allowance
        IERC20Permit(inputToken.tokenAddress).permit(
            inputToken.owner,
            address(this),
            inputToken.value,
            inputToken.deadline,
            inputToken.v,
            inputToken.r,
            inputToken.s
        );

        // Transfer `amountIn` of inputToken to this contract.
        SafeERC20.safeTransferFrom(
            IERC20(inputToken.tokenAddress),
            inputToken.owner,
            address(this),
            inputToken.value
        );

        // Approve the router to spend the token.
        IERC20(inputToken.tokenAddress).approve(uniswapRouter, inputToken.value);
        IERC20(morpherTokenAddress).approve(uniswapRouter, mphTokenAmount);

        bytes memory path;

        if (inputToken.tokenAddress != wMaticAddress) {
            path = abi.encodePacked( //reversed path for exactOutput! FU oz!
                    inputToken.tokenAddress,
                    poolFee,
                    wMaticAddress,
                    poolFee,
                    morpherTokenAddress
                );
        } else {
            path = abi.encodePacked(wMaticAddress, poolFee, morpherTokenAddress); //reversed path for exactOutput! FU oz!
        }

        IV3SwapRouter swapRouter = IV3SwapRouter(uniswapRouter);
        IV3SwapRouter.ExactInputParams memory inputSwapParams = IV3SwapRouter.ExactInputParams({
            path: path,
            recipient: msgSender,
            amountOutMinimum: mphTokenAmount,
            amountIn: inputToken.value //safeguarded by the permit functionality.
        });

        amountOut = swapRouter.exactInput(inputSwapParams);

        //reset the approved amounts
        IERC20(inputToken.tokenAddress).approve(uniswapRouter, 0);
        IERC20(morpherTokenAddress).approve(uniswapRouter, 0);
    }

    function convertMphAndPayout(
        address uniswapRouter,
        address wMaticAddress,
        address morpherTokenAddress,
        bytes32 orderId,
        uint mphTokenAmount,
        TokenPermitEIP712Struct memory inputToken
    ) public {
        IV3SwapRouter swapRouter = IV3SwapRouter(uniswapRouter);

        //increase allowance
        IERC20Permit(morpherTokenAddress).permit(
            inputToken.owner,
            address(this),
            inputToken.value,
            inputToken.deadline,
            inputToken.v,
            inputToken.r,
            inputToken.s
        );

        if (mphTokenAmount > inputToken.value) {
            emit MphCloseOrderSoftFail(orderId, mphTokenAmount, inputToken.value);
            return; //do nothing here, don't error out, just keep the MPH.
        }

        // Transfer `MPH payout` of Close position to this contract.
        SafeERC20.safeTransferFrom(
            IERC20(morpherTokenAddress),
            inputToken.owner,
            address(this),
            mphTokenAmount
        );

        // Approve the router to spend the token.
        IERC20(morpherTokenAddress).approve(uniswapRouter, mphTokenAmount);

        bytes memory path;

        if (inputToken.tokenAddress != wMaticAddress) {
            path = abi.encodePacked(
                morpherTokenAddress,
                poolFee,
                wMaticAddress,
                poolFee,
                inputToken.tokenAddress
            );
        } else {
            path = abi.encodePacked(morpherTokenAddress, poolFee, wMaticAddress);
        }

        IV3SwapRouter.ExactInputParams memory backConvertParams = IV3SwapRouter.ExactInputParams({
            path: path,
            recipient: inputToken.owner,
            amountIn: mphTokenAmount,
            amountOutMinimum: inputToken.minOutValue
        });

        // swap the remaining token back
        swapRouter.exactInput(backConvertParams);
        IERC20(morpherTokenAddress).approve(uniswapRouter, 0);
    }

    function swapWETHForMPH(
        address uniswapRouter,
        address wMaticAddress,
        address morpherTokenAddress,
        address msgSender,
        uint256 wethAmount,
        uint256 minMphAmount
    ) public returns (uint256 amountOut) {
        // Approve the router to spend WETH
        IWETH9(wMaticAddress).approve(uniswapRouter, wethAmount);
        
        // Create the swap path
        bytes memory path = abi.encodePacked(
            wMaticAddress,
            poolFee,
            morpherTokenAddress
        );
        
        // Execute the swap
        IV3SwapRouter swapRouter = IV3SwapRouter(uniswapRouter);
        IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter.ExactInputParams({
            path: path,
            recipient: msgSender,
            amountIn: wethAmount,
            amountOutMinimum: minMphAmount
        });
        
        amountOut = swapRouter.exactInput(params);
        
        // Reset approvals
        IWETH9(wMaticAddress).approve(uniswapRouter, 0);
        
        return amountOut;
    }
}
