// SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.15;

import "./MorpherState.sol";
import "./MorpherAccessControl.sol"; // Use adapted v5 interface

// --- V5 Imports ---
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ContextUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/utils/ContextUpgradeable.sol"; // Keep for _msgSender override if needed, though likely not here
import {PausableUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/utils/PausableUpgradeable.sol";
import {IERC20Permit} from "../lib/openzeppelin-contracts-5/contracts/token/ERC20/extensions/IERC20Permit.sol"; // Use non-upgradeable interface
import {IERC20} from "../lib/openzeppelin-contracts-5/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts-5/contracts/token/ERC20/utils/SafeERC20.sol";

import "../lib/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol"; // Keep external interface
import "../lib/uniswap-v3-periphery/contracts/interfaces/external/IWETH9.sol"; // Needed for WETH address reference

/**
 * @title MorpherSwapHelper
 * @notice Facilitates swapping whitelisted ERC20 tokens into MPH using user-signed permits.
 * @dev Allows relayers to execute swaps on behalf of users and receive a fee.
 * Inherits UUPSUpgradeable for upgradeability and PausableUpgradeable for emergency stops.
 * Uses MorpherState to access shared contract addresses like MorpherAccessControl, MPH token, WETH.
 */
contract MorpherSwapHelper is UUPSUpgradeable, ContextUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    MorpherState public state;
    address public uniswapRouter;
    address public wethAddress; // WETH or WMATIC etc.

    mapping(address => bool) public whitelistedTokens;

    uint256 public relayerFee; // Fee in MPH (with decimals) paid to msg.sender


    // --- Roles (fetched from MorpherAccessControl via MorpherState) ---
    bytes32 public constant ADMINISTRATOR_ROLE = keccak256("ADMINISTRATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    // Role for updating the proxy implementation via UUPS
    bytes32 public constant PROXYUPDATER_ROLE = keccak256("PROXYUPDATER_ROLE");

    // --- Uniswap V3 Pool Fee Tier ---
    // TODO: Consider making this configurable if different pools are needed
    uint24 public constant poolFee = 3000; // 0.3%

    bool private _allowReceiveETH; // Flag to allow ETH reception only during WETH withdrawal

    // --- Structs ---
    // Replicated from MorpherOracle for compatibility with frontend/signing logic
    struct TokenPermitEIP712Struct {
        address tokenAddress; // The token being swapped IN
        address owner;        // The user who owns the token and signed the permit
        uint256 value;        // Amount of tokenIn to swap
        uint256 minOutValue;  // Minimum amount of MPH expected (slippage protection)
        uint256 deadline;     // Permit deadline
        uint8 v;              // Permit signature v
        bytes32 r;            // Permit signature r
        bytes32 s;            // Permit signature s
    }

    // Struct for swapping MPH -> Token via Permit
    struct MphPermitSwapStruct {
        // address mphTokenAddress; // Implicitly fetched from state
        address owner;        // The user who owns MPH and signed the permit
        uint256 value;        // Amount of MPH to permit (includes fee)
        address targetTokenAddress; // The token to receive (e.g., WETH, USDC)
        uint256 minOutValue;  // Minimum amount of target token expected
        address recipient;    // Final destination address for output token/ETH
        uint256 deadline;     // Permit deadline
        uint8 v;              // Permit signature v
        bytes32 r;            // Permit signature r
        bytes32 s;            // Permit signature s
    }

    // --- Events ---
    event LinkState(address indexed oldAddress, address indexed newAddress);
    event LinkUniswapRouter(address indexed oldAddress, address indexed newAddress);
    event LinkWethAddress(address indexed oldAddress, address indexed newAddress);
    event TokenWhitelisted(address indexed token);
    event TokenRemovedFromWhitelist(address indexed token);
    event RelayerFeeSet(uint256 oldFee, uint256 newFee);
    event SwapExecuted(
        address indexed user,          // The owner who signed the permit
        address indexed relayer,       // The msg.sender executing the swap
        address tokenIn,
        uint256 amountIn,
        address tokenOut,      // Should always be MPH token
        uint256 amountOutTotal,    // Total MPH received from swap
        uint256 amountOutUser,     // MPH sent to user
        uint256 amountOutRelayer   // MPH sent to relayer (fee)
    );
    event SwapFailedInsufficientMph(
        address indexed user,
        address indexed relayer,
        address indexed tokenIn,
        uint256 amountIn,
        uint256 amountOutTotal,
        uint256 requiredFee
    );
    event SwapMphExecuted( // Event for MPH -> Token swap
        address indexed user,          // The owner who signed the permit
        address indexed relayer,       // The msg.sender executing the swap
        address tokenIn,       // Should always be MPH token
        uint256 totalAmountIn, // Total MPH permitted by user (value from struct)
        uint256 feeTaken,      // MPH fee taken by relayer
        uint256 amountInSwapped, // MPH amount actually swapped (totalAmountIn - feeTaken)
        address tokenOut,      // The target token address (e.g., WETH, USDC)
        uint256 amountOutTotal,    // Amount of tokenOut received from swap (or ETH if unwrapped)
        address recipient      // Final recipient of tokenOut/ETH
    );


    // --- Modifiers ---
    modifier onlyRole(bytes32 role) {
        address accessControlAddress = state.morpherAccessControlAddress();
        require(accessControlAddress != address(0), "SwapHelper: AccessControl not set");
        require(
            MorpherAccessControl(accessControlAddress).hasRole(role, _msgSender()),
            "SwapHelper: Permission denied."
        );
        _;
    }

    // --- Initializer ---
    function initialize(
        address _stateAddress,
        address _uniswapRouter,
        address _wethAddress
    ) public initializer {
        require(_stateAddress != address(0), "SwapHelper: Invalid state address");
        require(_uniswapRouter != address(0), "SwapHelper: Invalid router address");
        require(_wethAddress != address(0), "SwapHelper: Invalid WETH address");

        __UUPSUpgradeable_init();
        __Context_init();
        __Pausable_init();

        state = MorpherState(_stateAddress);
        uniswapRouter = _uniswapRouter;
        wethAddress = _wethAddress;
        // Set initial fee: 100 MPH (assuming 8 decimals for MPH)
        relayerFee = 100 * (10**8);

        // Grant initial roles (optional, could be done separately)
        // address deployer = _msgSender();
        // MorpherAccessControl accessControl = MorpherAccessControl(state.morpherAccessControlAddress());
        // accessControl.grantRole(ADMINISTRATOR_ROLE, deployer);
        // accessControl.grantRole(PAUSER_ROLE, deployer);
        // accessControl.grantRole(PROXYUPDATER_ROLE, deployer);
        // accessControl.renounceRole(ADMINISTRATOR_ROLE, deployer); // Example: if deployer shouldn't keep admin
        // accessControl.renounceRole(PAUSER_ROLE, deployer);

        emit LinkState(address(0), _stateAddress);
        emit LinkUniswapRouter(address(0), _uniswapRouter);
        emit LinkWethAddress(address(0), _wethAddress);
        emit RelayerFeeSet(0, relayerFee);
    }

    // --- Receive ETH ---
    // Required to receive ETH from WETH unwrapping, protected by a flag
    receive() external payable {
        require(_allowReceiveETH, "SwapHelper: Direct ETH transfers not allowed");
    }

    // --- UUPS Upgrade ---
    function _authorizeUpgrade(address /** unused */)
        internal
        view
        override
        onlyRole(PROXYUPDATER_ROLE) // Use PROXYUPDATER_ROLE defined in MorpherAccessControl
    {
        // solhint-disable-next-line no-empty-blocks
        // Allow upgrade only if caller has the correct role
    }

    // --- Core Swap Logic ---

    /**
     * @notice Swaps a whitelisted token for MPH using a user's permit signature.
     * @dev The caller (`msg.sender`) acts as a relayer, pays gas, and receives a fee in MPH.
     * @param inputToken Struct containing token details, amount, permit signature, and slippage protection.
     */
    function swapTokenToMphPermitted(
        TokenPermitEIP712Struct calldata inputToken
    ) public whenNotPaused {
        address tokenIn = inputToken.tokenAddress;
        address mphToken = state.morpherTokenAddress();
        address owner = inputToken.owner;
        uint256 amountIn = inputToken.value;
        uint256 minAmountOut = inputToken.minOutValue;
        address relayer = _msgSender(); // The address calling this function

        require(tokenIn != address(0), "SwapHelper: Invalid input token");
        require(owner != address(0), "SwapHelper: Invalid owner address");
        require(mphToken != address(0), "SwapHelper: MPH address not set in state");
        require(tokenIn != mphToken, "SwapHelper: Input token cannot be MPH");
        require(whitelistedTokens[tokenIn], "SwapHelper: Input token not whitelisted");
        require(amountIn > 0, "SwapHelper: Input amount must be positive");

        // 1. Use the permit to gain approval
        IERC20Permit(tokenIn).permit(
            owner,
            address(this), // spender is this contract
            amountIn,
            inputToken.deadline,
            inputToken.v,
            inputToken.r,
            inputToken.s
        );

        // 2. Transfer the input token from the owner to this contract
        IERC20(tokenIn).safeTransferFrom(owner, address(this), amountIn);

        // 3. Approve the Uniswap Router to spend the input token
        IERC20(tokenIn).approve(uniswapRouter, amountIn);

        // 4. Prepare the swap path
        bytes memory path;
        if (tokenIn == wethAddress) {
            // Path: WETH -> MPH
            path = abi.encodePacked(wethAddress, poolFee, mphToken);
        } else {
            // Path: Token -> WETH -> MPH
            path = abi.encodePacked(tokenIn, poolFee, wethAddress, poolFee, mphToken);
        }

        // 5. Execute the swap via Uniswap V3 Router
        IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter.ExactInputParams({
            path: path,
            recipient: address(this), // Swap sends MPH output to this contract first
            amountIn: amountIn,
            amountOutMinimum: minAmountOut // Slippage protection from input struct
        });

        uint256 amountOutTotal = IV3SwapRouter(uniswapRouter).exactInput(params);

        // 6. Reset approval for the router (good practice)
        IERC20(tokenIn).approve(uniswapRouter, 0);

        // 7. Distribute the received MPH
        uint256 fee = relayerFee;
        if (amountOutTotal < fee) {
            // If the total output is less than the fee, the swap effectively failed
            // to meet the fee requirement. Send everything back to the user to avoid
            // locking funds or penalizing the relayer unfairly.
            IERC20(mphToken).safeTransfer(owner, amountOutTotal);
            emit SwapFailedInsufficientMph(owner, relayer, tokenIn, amountIn, amountOutTotal, fee);
            // Optionally revert here if this case should be treated as a hard failure:
            // revert("SwapHelper: Swap output less than relayer fee");
            return; // Or just return if sending back is preferred
        }

        uint256 amountOutUser = amountOutTotal - fee;

        // Transfer fee to the relayer (msg.sender)
        IERC20(mphToken).safeTransfer(relayer, fee);

        // Transfer the remaining amount to the original owner
        IERC20(mphToken).safeTransfer(owner, amountOutUser);

        emit SwapExecuted(
            owner,
            relayer,
            tokenIn,
            amountIn,
            mphToken,
            amountOutTotal,
            amountOutUser,
            fee
        );
    }

    /**
     * @notice Swaps user's MPH for a target token (or ETH) using a permit signature.
     * @dev The caller (`msg.sender`) acts as a relayer, pays gas, takes a fee in MPH before the swap.
     * @param input Struct containing MPH amount, target token, recipient, permit signature, etc.
     */
    function swapMphToTokenPermitted(
        MphPermitSwapStruct calldata input
    ) public whenNotPaused {
        // Inlined variables: mphToken, minAmountOut, fee
        address owner = input.owner;
        address targetToken = input.targetTokenAddress;
        uint256 totalAmountIn = input.value; // Total MPH user permits spending
        address recipient = input.recipient;
        address relayer = _msgSender();

        require(owner != address(0), "SwapHelper: Invalid owner address");
        require(state.morpherTokenAddress() != address(0), "SwapHelper: MPH address not set in state");
        require(targetToken != address(0), "SwapHelper: Invalid target token");
        require(recipient != address(0), "SwapHelper: Invalid recipient address");
        require(targetToken != state.morpherTokenAddress(), "SwapHelper: Target token cannot be MPH");
        require(
            targetToken == wethAddress || whitelistedTokens[targetToken],
            "SwapHelper: Target token not WETH or whitelisted"
        );
        require(totalAmountIn > relayerFee, "SwapHelper: Input amount must be greater than fee"); // Use relayerFee directly

        // 1. Use the permit to gain approval for the *total* amount (including fee)
        IERC20Permit(state.morpherTokenAddress()).permit( // Use state.morpherTokenAddress()
            owner,
            address(this), // spender is this contract
            totalAmountIn,
            input.deadline,
            input.v,
            input.r,
            input.s
        );

        // 2. Transfer fee from owner to relayer
        // Requires owner to have approved 'totalAmountIn' via permit
        IERC20(state.morpherTokenAddress()).safeTransferFrom(owner, relayer, relayerFee); // Use relayerFee directly

        // 3. Transfer the remaining MPH to swap from owner to this contract
        uint256 amountInToSwap = totalAmountIn - relayerFee; // Use relayerFee directly
        IERC20(state.morpherTokenAddress()).safeTransferFrom(owner, address(this), amountInToSwap); // Use state.morpherTokenAddress()

        // 4. Approve the Uniswap Router to spend the MPH to be swapped
        IERC20(state.morpherTokenAddress()).approve(uniswapRouter, amountInToSwap); // Use state.morpherTokenAddress()

        // 5 & 6. Prepare path and execute swap via Uniswap V3 Router (inlining path and params)
        uint256 amountOutTotal = IV3SwapRouter(uniswapRouter).exactInput(
            IV3SwapRouter.ExactInputParams({
                path: targetToken == wethAddress
                    ? abi.encodePacked(state.morpherTokenAddress(), poolFee, wethAddress) // Path: MPH -> WETH
                    : abi.encodePacked(state.morpherTokenAddress(), poolFee, wethAddress, poolFee, targetToken), // Path: MPH -> WETH -> TargetToken
                recipient: address(this), // Swap sends output to this contract first
                amountIn: amountInToSwap,
                amountOutMinimum: input.minOutValue // Inline minAmountOut from input struct
            })
        );

        // 7. Reset approval for the router (good practice)
        IERC20(state.morpherTokenAddress()).approve(uniswapRouter, 0); // Use state.morpherTokenAddress()

        // 8. Handle and send the output
        if (targetToken == wethAddress) {
            // Temporarily allow receiving ETH, unwrap WETH, then disallow again
            _allowReceiveETH = true;
            IWETH9(wethAddress).withdraw(amountOutTotal);
            _allowReceiveETH = false; // Disallow immediately after withdrawal

            // Send received ETH to recipient
            (bool sent, ) = recipient.call{value: amountOutTotal}("");
            require(sent, "SwapHelper: ETH transfer failed");
        } else {
            // Transfer ERC20 token to recipient
            IERC20(targetToken).safeTransfer(recipient, amountOutTotal);
        }

        emit SwapMphExecuted(
            owner,
            relayer,
            state.morpherTokenAddress(), // Use state.morpherTokenAddress()
            totalAmountIn,
            relayerFee, // Use relayerFee directly
            amountInToSwap,
            targetToken, // Log the target ERC20 address (even if WETH was unwrapped)
            amountOutTotal,
            recipient
        );
    }


    // --- Admin Functions ---

    function setStateAddress(address _address) public onlyRole(ADMINISTRATOR_ROLE) {
        require(_address != address(0), "SwapHelper: Invalid state address");
        address oldAddress = address(state);
        state = MorpherState(_address);
        emit LinkState(oldAddress, _address);
    }

    function setUniswapRouter(address _address) public onlyRole(ADMINISTRATOR_ROLE) {
        require(_address != address(0), "SwapHelper: Invalid router address");
        address oldAddress = uniswapRouter;
        uniswapRouter = _address;
        emit LinkUniswapRouter(oldAddress, _address);
    }

    function setWethAddress(address _address) public onlyRole(ADMINISTRATOR_ROLE) {
        require(_address != address(0), "SwapHelper: Invalid WETH address");
        address oldAddress = wethAddress;
        wethAddress = _address;
        emit LinkWethAddress(oldAddress, _address);
    }

    function whitelistToken(address _token) public onlyRole(ADMINISTRATOR_ROLE) {
        require(_token != address(0), "SwapHelper: Invalid token address");
        require(_token != state.morpherTokenAddress(), "SwapHelper: Cannot whitelist MPH token");
        whitelistedTokens[_token] = true;
        emit TokenWhitelisted(_token);
    }

    function removeTokenFromWhitelist(address _token) public onlyRole(ADMINISTRATOR_ROLE) {
        require(_token != address(0), "SwapHelper: Invalid token address");
        whitelistedTokens[_token] = false;
        emit TokenRemovedFromWhitelist(_token);
    }

     function setRelayerFee(uint256 _newFee) public onlyRole(ADMINISTRATOR_ROLE) {
        uint256 oldFee = relayerFee;
        relayerFee = _newFee;
        emit RelayerFeeSet(oldFee, _newFee);
    }

    // --- Pausable Functions ---

    function pause() public virtual onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public virtual onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // --- View Functions ---

    /**
     * @notice Returns the address of the MPH token configured in the linked MorpherState.
     */
    function getMphTokenAddress() public view returns (address) {
        return state.morpherTokenAddress();
    }

    /**
     * @notice Checks if a token is whitelisted for swapping.
     */
    function isTokenWhitelisted(address _token) public view returns (bool) {
        return whitelistedTokens[_token];
    }
}
