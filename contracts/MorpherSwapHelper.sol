//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts-5/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts-5/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "../lib/openzeppelin-contracts-5/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts-5/contracts/utils/ReentrancyGuard.sol";

// Universal Router imports
import "../lib/universal-router/contracts/interfaces/IUniversalRouter.sol";
import "../lib/universal-router/contracts/libraries/Commands.sol";
import "../lib/universal-router/permit2/src/interfaces/IAllowanceTransfer.sol";

/**
 * @title MorpherSwapHelper
 * @dev Helper contract to simplify swapping with Universal Router by requiring only one permit
 */
contract MorpherSwapHelper is Ownable, ReentrancyGuard {
    // Universal Router and Permit2 addresses
    address public immutable universalRouter;
    address public immutable permit2;
    
    // Events
    event SwapExecuted(address indexed user, address inputToken, address outputToken, uint256 amountIn, uint256 amountOut);
    
    /**
     * @dev Constructor sets the Universal Router and Permit2 addresses
     * @param _universalRouter Address of the Universal Router
     * @param _permit2 Address of the Permit2 contract
     */
    constructor(address _universalRouter, address _permit2) Ownable(msg.sender) {
        universalRouter = _universalRouter;
        permit2 = _permit2;
    }
    
    /**
     * @dev Execute a swap with a single permit
     * @param inputToken Address of the input token
     * @param outputToken Address of the output token
     * @param amountIn Amount of input tokens to swap
     * @param amountOutMin Minimum amount of output tokens expected
     * @param path Encoded path for the swap
     * @param deadline Deadline for the transaction
     * @param permitDeadline Deadline for the permit
     * @param v v component of the signature
     * @param r r component of the signature
     * @param s s component of the signature
     * @return amountOut Amount of output tokens received
     */
    function swapWithPermit(
        address inputToken,
        address outputToken,
        uint256 amountIn,
        uint256 amountOutMin,
        bytes memory path,
        uint256 deadline,
        uint256 permitDeadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant returns (uint256 amountOut) {
        // 1. Use the permit to get approval for this contract to spend user's tokens
        IERC20Permit(inputToken).permit(
            msg.sender,
            address(this),
            amountIn,
            permitDeadline,
            v,
            r,
            s
        );
        
        // 2. Transfer tokens from user to this contract
        IERC20(inputToken).transferFrom(msg.sender, address(this), amountIn);
        
        // 3. Approve Permit2 to spend our tokens
        IERC20(inputToken).approve(permit2, amountIn);
        
        // 4. Approve Permit2 to Universal Router
        IAllowanceTransfer(permit2).approve(
            inputToken,
            universalRouter,
            uint160(amountIn),
            uint48(deadline)
        );
        
        // 5. Prepare the swap command
        bytes memory commands = abi.encodePacked(uint8(Commands.V3_SWAP_EXACT_IN));
        
        // 6. Prepare the swap inputs
        bytes[] memory inputs = new bytes[](1);
        
        // Encode the parameters for the V3_SWAP_EXACT_IN command
        inputs[0] = abi.encode(
            msg.sender,          // recipient (send tokens directly to user)
            amountIn,            // amountIn
            amountOutMin,        // amountOutMinimum
            path,                // path
            true                // payerIsUser - false because tokens come from this contract
        );
        
        // 7. Record balance before swap to calculate output amount
        uint256 balanceBefore = IERC20(outputToken).balanceOf(msg.sender);
        
        // 8. Execute the swap
        IUniversalRouter(universalRouter).execute(commands, inputs, deadline);
        
        // 9. Calculate amount received
        amountOut = IERC20(outputToken).balanceOf(msg.sender) - balanceBefore;
        
        // 10. Emit event
        emit SwapExecuted(msg.sender, inputToken, outputToken, amountIn, amountOut);
        
        return amountOut;
    }
    
    /**
     * @dev Rescue any tokens accidentally sent to this contract
     * @param token Address of the token to rescue
     * @param to Address to send the tokens to
     * @param amount Amount of tokens to rescue
     */
    function rescueTokens(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }
}
