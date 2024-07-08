// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

// Import the required libraries and contracts
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../installed_contracts/openzeppelin-contracts-5/contracts/utils/cryptography/EIP712.sol";

import "../installed_contracts/eth-infinitism/contracts/interfaces/IEntryPoint.sol";
import "../installed_contracts/eth-infinitism/contracts/core/BasePaymaster.sol";
import "../installed_contracts/eth-infinitism/contracts/interfaces/UserOperation.sol";
import "../installed_contracts/eth-infinitism-dev/contracts/samples/utils/UniswapHelper.sol";
import "../installed_contracts/eth-infinitism-dev/contracts/samples/utils/OracleHelper.sol";

/// @title Sample ERC-20 Token Paymaster for ERC-4337
/// This Paymaster covers gas fees in exchange for ERC20 tokens charged using allowance pre-issued by ERC-4337 accounts.
/// The contract refunds excess tokens if the actual gas cost is lower than the initially provided amount.
/// The token price cannot be queried in the validation code due to storage access restrictions of ERC-4337.
/// The price is cached inside the contract and is updated in the 'postOp' stage if the change is >10%.
/// It is theoretically possible the token has depreciated so much since the last 'postOp' the refund becomes negative.
/// The contract reverts the inner user transaction in that case but keeps the charge.
/// The contract also allows honest clients to prepay tokens at a higher price to avoid getting reverted.
/// It also allows updating price configuration and withdrawing tokens by the contract owner.
/// The contract uses an Oracle to fetch the latest token prices.
/// @dev Inherits from BasePaymaster.
contract MorpherTokenPaymaster is BasePaymaster, UniswapHelper, OracleHelper {

    
    struct TokenPaymasterConfig {
        /// @notice The price markup percentage applied to the token price (1e6 = 100%)
        uint256 priceMarkup;

        /// @notice Exchange tokens to native currency if the EntryPoint balance of this Paymaster falls below this value
        uint128 minEntryPointBalance;

        /// @notice Estimated gas cost for refunding tokens after the transaction is completed
        uint48 refundPostopCost;

        /// @notice Transactions are only valid as long as the cached price is not older than this value
        uint48 priceMaxAge;
    }

    struct PermitParams {
        address thisAddress;
        bytes4 permitFunctionHash;
        address owner;
		address spender;
		uint256 value;
		uint256 deadline;
		uint8 v;
		bytes32 r;
		bytes32 s;
    }


    event ConfigUpdated(TokenPaymasterConfig tokenPaymasterConfig);

    event UserOperationSponsored(address indexed user, uint256 actualTokenCharge, uint256 actualGasCost, uint256 actualTokenPrice);

    event Received(address indexed sender, uint256 value);

    /// @notice All 'price' variables are multiplied by this value to avoid rounding up
    uint256 private constant PRICE_DENOMINATOR = 1e26;

    TokenPaymasterConfig private tokenPaymasterConfig;

    /// @notice Initializes the TokenPaymaster contract with the given parameters.
    /// @param _token The ERC20 token used for transaction fee payments.
    /// @param _entryPoint The EntryPoint contract used in the Account Abstraction infrastructure.
    /// @param _wrappedNative The ERC-20 token that wraps the native asset for current chain.
    /// @param _uniswap The Uniswap V3 SwapRouter contract.
    /// @param _tokenPaymasterConfig The configuration for the Token Paymaster.
    /// @param _oracleHelperConfig The configuration for the Oracle Helper.
    /// @param _uniswapHelperConfig The configuration for the Uniswap Helper.
    /// @param _owner The address that will be set as the owner of the contract.
    constructor(
        IERC20Metadata _token, //0x322531297FAb2e8FeAf13070a7174a83117ADAd4
        IEntryPoint _entryPoint, //0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789
        IERC20 _wrappedNative, //0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889
        ISwapRouter _uniswap, //0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45
        TokenPaymasterConfig memory _tokenPaymasterConfig, //[100000000000000000000000000,100000000000000,20000,60]
        OracleHelperConfig memory _oracleHelperConfig, //[60,"0xBde0eDd749f225dbD9e6b79BE0ED7F5B1b80A65d","0xBde0eDd749f225dbD9e6b79BE0ED7F5B1b80A65d",true,false,false,100000]
        UniswapHelperConfig memory _uniswapHelperConfig,//[100000000,300,100]
        address _owner
    )
    BasePaymaster(
    _entryPoint
    )
    OracleHelper(
    _oracleHelperConfig
    )
    UniswapHelper(
    _token,
    _wrappedNative,
    _uniswap,
    10 ** _token.decimals(),
    _uniswapHelperConfig
    )
    Ownable(
        msg.sender
    )
    {
        setTokenPaymasterConfig(_tokenPaymasterConfig);
        transferOwnership(_owner);
    }

    /// @notice Updates the configuration for the Token Paymaster.
    /// @param _tokenPaymasterConfig The new configuration struct.
    function setTokenPaymasterConfig(
        TokenPaymasterConfig memory _tokenPaymasterConfig
    ) public onlyOwner {
        require(_tokenPaymasterConfig.priceMarkup <= 2 * PRICE_DENOMINATOR, "TPM: price markup too high");
        require(_tokenPaymasterConfig.priceMarkup >= PRICE_DENOMINATOR, "TPM: price markup too low");
        tokenPaymasterConfig = _tokenPaymasterConfig;
        emit ConfigUpdated(_tokenPaymasterConfig);
    }

    function setUniswapConfiguration(
        UniswapHelperConfig memory _uniswapHelperConfig
    ) external onlyOwner {
        _setUniswapHelperConfiguration(_uniswapHelperConfig);
    }
    

    /// @notice Allows the contract owner to withdraw a specified amount of tokens from the contract.
    /// @param to The address to transfer the tokens to.
    /// @param amount The amount of tokens to transfer.
    function withdrawToken(address to, uint256 amount) external onlyOwner {
        SafeERC20.safeTransfer(token, to, amount);
    }

    /// @notice Validates a paymaster user operation and calculates the required token amount for the transaction.
    /// @param userOp The user operation data.
    /// @param requiredPreFund The amount of tokens required for pre-funding.
    /// @return context The context containing the token amount and user sender address (if applicable).
    /// @return validationResult A uint256 value indicating the result of the validation (always 0 in this implementation).
    function _validatePaymasterUserOp(UserOperation calldata userOp, bytes32, uint256 requiredPreFund)
    internal
    override
    returns (bytes memory context, uint256 validationResult) {unchecked {
            uint256 priceMarkup = tokenPaymasterConfig.priceMarkup;
            uint256 paymasterAndDataLength = userOp.paymasterAndData.length - 20;
            // require(paymasterAndDataLength == 0 || paymasterAndDataLength == 32,
            //     "TPM: invalid data length"
            // );
            //check singature function call etc
            uint256 preChargeNative = requiredPreFund + (tokenPaymasterConfig.refundPostopCost * userOp.maxFeePerGas);
        // note: as price is in ether-per-token and we want more tokens increasing it means dividing it by markup
            updateCachedPrice(cachedPriceTimestamp < block.timestamp + tokenPaymasterConfig.priceMaxAge); //force a price update?! why? so that the timestamp is correct for the validationResult.
            uint256 cachedPriceWithMarkup = cachedPrice * PRICE_DENOMINATOR / priceMarkup;

            uint256 tokenAmount = weiToToken(preChargeNative, cachedPriceWithMarkup);

            
            if (paymasterAndDataLength > 0) {
                //PermitParams memory permitParams = abi.decode(userOp.paymasterAndData, (PermitParams));
                address originalOwner = address(bytes20(userOp.paymasterAndData[(20+4+12) : (20+4+32)]));
                (bool success, ) = address(token).call{gas: gasleft(), value: 0}(userOp.paymasterAndData[20 :]); //permit functionality :)
                require(success, "ERC20 Permit failed. Aborting"); //potentially just retry charging the userOp sender here?!
                SafeERC20.safeTransferFrom(token, originalOwner, address(this), tokenAmount);
                context = abi.encode(tokenAmount, userOp.maxFeePerGas, userOp.maxPriorityFeePerGas, originalOwner);
            } else {
                SafeERC20.safeTransferFrom(token, userOp.sender, address(this), tokenAmount);
                context = abi.encode(tokenAmount, userOp.maxFeePerGas, userOp.maxPriorityFeePerGas, userOp.sender);
            }
            
            validationResult = _packValidationData(
                false,
                uint48(cachedPriceTimestamp + tokenPaymasterConfig.priceMaxAge),
                0
            );
        }
    }

    /// @notice Performs post-operation tasks, such as updating the token price and refunding excess tokens.
    /// @dev This function is called after a user operation has been executed or reverted.
    /// @param context The context containing the token amount and user sender address.
    /// @param actualGasCost The actual gas cost of the transaction.
    function _postOp(PostOpMode, bytes calldata context, uint256 actualGasCost) internal override {
        unchecked {
            uint256 priceMarkup = tokenPaymasterConfig.priceMarkup;
            (
                uint256 preCharge,
                uint256 maxFeePerGas,
                uint256 maxPriorityFeePerGas,
                address userOpSender
            ) = abi.decode(context, (uint256, uint256, uint256, address));
            uint256 gasPrice = getGasPrice(maxFeePerGas, maxPriorityFeePerGas);
            uint256 _cachedPrice = updateCachedPrice(false);
        // note: as price is in ether-per-token and we want more tokens increasing it means dividing it by markup
            uint256 cachedPriceWithMarkup = _cachedPrice * PRICE_DENOMINATOR / priceMarkup;
        // Refund tokens based on actual gas cost
            uint256 actualChargeNative = actualGasCost + tokenPaymasterConfig.refundPostopCost * gasPrice;
            uint256 actualTokenNeeded = weiToToken(actualChargeNative, cachedPriceWithMarkup);
            if (preCharge > actualTokenNeeded) {
                // If the initially provided token amount is greater than the actual amount needed, refund the difference
                SafeERC20.safeTransfer(
                    token,
                    userOpSender,
                    preCharge - actualTokenNeeded
                );
            } else if (preCharge < actualTokenNeeded) {
                // Attempt to cover Paymaster's gas expenses by withdrawing the 'overdraft' from the client
                // If the transfer reverts also revert the 'postOp' to remove the incentive to cheat
                SafeERC20.safeTransferFrom(
                    token,
                    userOpSender,
                    address(this),
                    actualTokenNeeded - preCharge
                );
            }

            emit UserOperationSponsored(userOpSender, actualTokenNeeded, actualGasCost, _cachedPrice);
            refillEntryPointDeposit(_cachedPrice);
        }
    }

    /// @notice If necessary this function uses this Paymaster's token balance to refill the deposit on EntryPoint
    /// @param _cachedPrice the token price that will be used to calculate the swap amount.
    function refillEntryPointDeposit(uint256 _cachedPrice) private {
        uint256 currentEntryPointBalance = entryPoint.balanceOf(address(this));
        if (
            currentEntryPointBalance < tokenPaymasterConfig.minEntryPointBalance
        ) {
            uint256 swappedWeth = _maybeSwapTokenToWeth(token, _cachedPrice);
            unwrapWeth(swappedWeth);
            entryPoint.depositTo{value: address(this).balance}(address(this));
        }
    }

    function getGasPrice(uint256 maxFeePerGas, uint256 maxPriorityFeePerGas) internal view returns (uint256) {
        if (maxFeePerGas == maxPriorityFeePerGas) {
            // legacy mode (for networks that don't support the 'basefee' opcode)
            return maxFeePerGas;
        }
        return min(maxFeePerGas, maxPriorityFeePerGas + block.basefee);
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}