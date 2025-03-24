//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.15;

import "./MorpherTradeEngine.sol";
import "./MorpherState.sol";
import "./MorpherAccessControl.sol";

import "../lib/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/MerkleProofUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/EIP712Upgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/ECDSAUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/utils/CountersUpgradeable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";

import "../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

import { IV4Router, PoolKey } from "../lib/v4-periphery/src/interfaces/IV4Router.sol";
import { Actions } from "../lib/v4-periphery/src/libraries/Actions.sol";
import "../lib/v4-periphery/src/interfaces/external/IWETH9.sol";
import { IUniversalRouter } from "../lib/universal-router/contracts/interfaces/IUniversalRouter.sol";
import { Commands } from "../lib/universal-router/contracts/libraries/Commands.sol";
import { IPermit2 } from "../lib/permit2/src/interfaces/IPermit2.sol";
// import {PoolKey} from "../lib/v4-core/src/types/PoolKey.sol";
import {IHooks} from "../lib/v4-periphery/lib/v4-core/src/interfaces/IHooks.sol";
import "../lib/v4-periphery/lib/v4-core/src/types/Currency.sol";

// ----------------------------------------------------------------------------------
// Morpher Oracle contract v 2.0
// The oracle initates a new trade by calling trade engine and requesting a new orderId.
// An event is fired by the contract notifying the oracle operator to query a price/liquidation unchecked
// for a market/user and return the information via the callback function. Since calling
// the callback function requires gas, the user must send a fixed amount of Ether when
// creating their order.
// ----------------------------------------------------------------------------------

/// @custom:oz-upgrades-from contracts/prev/contracts/MorpherOracle.sol:MorpherOracle
contract MorpherOracle is Initializable, ContextUpgradeable, PausableUpgradeable {
	MorpherState state; // read only, Oracle doesn't need writing access to state

	bool public useWhiteList; //always false at the moment

	uint256 public gasForCallback;

	address payable public callBackCollectionAddress;

	mapping(address => bool) public callBackAddress;
	mapping(address => bool) public whiteList;

	mapping(bytes32 => uint256) public priceBelow;
	mapping(bytes32 => uint256) public priceAbove;
	mapping(bytes32 => uint256) public goodFrom;
	mapping(bytes32 => uint256) public goodUntil;

	mapping(bytes32 => bool) public orderCancellationRequested;

	/**
	 * ROLES KNOWN TO ORACLE
	 */
	bytes32 public constant ADMINISTRATOR_ROLE = keccak256("ADMINISTRATOR_ROLE");
	bytes32 public constant ORACLEOPERATOR_ROLE = keccak256("ORACLEOPERATOR_ROLE"); //used for callbacks from API
	bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE"); //can pause oracle

	uint delistMarketFromIx;

	using CountersUpgradeable for CountersUpgradeable.Counter;

	/**
	 * Permit functionality
	 * Added after proxy was deployed, so manually adding functionality here
	 */
	bytes32 public constant _HASHED_NAME = 0xca82a94b3c35be4fb8e06faa102ba96b016e9c5dd45f747224333f012bfd5e6a;
	bytes32 public constant _HASHED_VERSION = 0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6;
	bytes32 public constant _TYPE_HASH =
		keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

	
	
	// solhint-disable-next-line var-name-mixedcase
	bytes32 public constant _PERMIT_TYPEHASH =
		keccak256(
			"CreateOrder(bytes32 _marketId,uint256 _closeSharesAmount,uint256 _openMPHTokenAmount,address _msgSender,uint256 nonce,uint256 deadline)"
		);
		
	bytes32 public constant _CANCEL_ORDER_TYPEHASH =
		keccak256(
			"CancelOrder(bytes32 _orderId,address _msgSender,uint256 nonce,uint256 deadline)"
		);

	struct CreateOrderStruct {
		bytes32 _marketId;
		uint256 _closeSharesAmount;
		uint256 _openMPHTokenAmount;
		bool _tradeDirection;
		uint256 _orderLeverage;
		uint256 _onlyIfPriceAbove;
		uint256 _onlyIfPriceBelow;
		uint256 _goodUntil;
		uint256 _goodFrom;
	}

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

	uint24 public constant poolFee = 3000; // 0.3% fee tier for v4 pools

	mapping(bytes32 => TokenPermitEIP712Struct) closeOrderIdSwapToToken; //tokenAddress will be the target address, the permit needs to be for MPH and needs to be larger than the MPH amount to be closed otherwise it will fail.

	address private msgSenderOverride;

	address public wMaticAddress;

	mapping(address => CountersUpgradeable.Counter) private _nonces;


	// MorpherSwapHelper addresses by chain
	address public morpherSwapHelperAddress;


	// Universal Router address - used for swaps
	address public universalRouter;
	
	// Permit2 address
	address public permit2Address;
	
	// Uniswap v4 pool address
	address public uniswapV4Pool;


	// ----------------------------------------------------------------------------------
	// Events
	// ----------------------------------------------------------------------------------
	event OrderCreated(
		bytes32 indexed _orderId,
		address indexed _address,
		bytes32 indexed _marketId,
		uint256 _closeSharesAmount,
		uint256 _openMPHTokenAmount,
		bool _tradeDirection,
		uint256 _orderLeverage,
		uint256 _onlyIfPriceBelow,
		uint256 _onlyIfPriceAbove,
		uint256 _goodFrom,
		uint256 _goodUntil
	);

	event LiquidationOrderCreated(
		bytes32 indexed _orderId,
		address _sender,
		address indexed _address,
		bytes32 indexed _marketId
	);

	event OrderProcessed(
		bytes32 indexed _orderId,
		uint256 _price,
		uint256 _unadjustedMarketPrice,
		uint256 _spread,
		uint256 _positionLiquidationTimestamp,
		uint256 _timeStamp,
		uint256 _newLongShares,
		uint256 _newShortShares,
		uint256 _newMeanEntry,
		uint256 _newMeanSprad,
		uint256 _newMeanLeverage,
		uint256 _liquidationPrice
	);

	event OrderFailed(
		bytes32 indexed _orderId,
		address indexed _address,
		bytes32 indexed _marketId,
		uint256 _closeSharesAmount,
		uint256 _openMPHTokenAmount,
		bool _tradeDirection,
		uint256 _orderLeverage,
		uint256 _onlyIfPriceBelow,
		uint256 _onlyIfPriceAbove,
		uint256 _goodFrom,
		uint256 _goodUntil
	);

	event OrderCancelled(bytes32 indexed _orderId, address indexed _sender, address indexed _oracleAddress);

	event AdminOrderCancelled(bytes32 indexed _orderId, address indexed _sender, address indexed _oracleAddress);

	event OrderCancellationRequestedEvent(bytes32 indexed _orderId, address indexed _sender);

	event CallbackAddressEnabled(address indexed _address);

	event CallbackAddressDisabled(address indexed _address);

	event OraclePaused(bool _paused);

	event CallBackCollectionAddressChange(address _address);

	event SetGasForCallback(uint256 _gasForCallback);

	event LinkTradeEngine(address _address);
	event LinkWMatic(address _address);
	event LinkUniversalRouter(address _address);
	event LinkPermit2(address _address);
	event LinkUniswapV4Pool(address _address);

	event LinkMorpherState(address _address);

	event SetUseWhiteList(bool _useWhiteList);

	event AddressWhiteListed(address _address);

	event AddressBlackListed(address _address);

	event AdminLiquidationOrderCreated(
		bytes32 indexed _orderId,
		address indexed _address,
		bytes32 indexed _marketId,
		uint256 _closeSharesAmount,
		uint256 _openMPHTokenAmount,
		bool _tradeDirection,
		uint256 _orderLeverage
	);

	/**
	 * Delisting markets is a function that stops when gas is running low
	 * if it reached all positions it will emit "DelistMarketComplete"
	 * otherwise it needs to be re-run.
	 */
	event DelistMarketIncomplete(bytes32 _marketId, uint256 _processedUntilIndex);
	event DelistMarketComplete(bytes32 _marketId);
	event LockedPriceForClosingPositions(bytes32 _marketId, uint256 _price);

	/**
	 * MPH Uniswap Conversion Events
	 */
	event MphCloseOrderSoftFail(bytes32 _orderId, uint _mphTokenAmountCloseOrder, uint _mphTokenAmountPermit); //used when on close order all tokens cannot be converted back, so it fails, but it will still close the position just keep it in MPH token then

	/**
	 * Overrides the msgSender Context to understand when a subsequent token sale happened
	 */
	function _msgSender() internal view override returns (address) {
		if (msgSenderOverride != address(0)) {
			return msgSenderOverride;
		}

		return msg.sender;
	}

	modifier onlyRole(bytes32 role) {
		require(
			MorpherAccessControl(state.morpherAccessControlAddress()).hasRole(role, _msgSender()),
			"MorpherOracle: Permission denied."
		);
		_;
	}

	function initialize(
		address _morpherState,
		address payable _gasCollectionAddress,
		uint256 _gasForCallback
	) public initializer {
		ContextUpgradeable.__Context_init();
		PausableUpgradeable.__Pausable_init();

		state = MorpherState(_morpherState);

		setCallbackCollectionAddress(_gasCollectionAddress);
		setGasForCallback(_gasForCallback);
	}

	// ----------------------------------------------------------------------------------
	// Setter/getter functions for trade engine address, oracle operator (callback) address,
	// and prepaid gas limit for callback function
	// ----------------------------------------------------------------------------------

	function setStateAddress(address _address) public onlyRole(ADMINISTRATOR_ROLE) {
		state = MorpherState(_address);
		emit LinkMorpherState(_address);
	}

	function setWmaticAddress(address _address) public onlyRole(ADMINISTRATOR_ROLE) {
		wMaticAddress = _address;
		emit LinkWMatic(_address);
	}
	
	function setUniversalRouter(address _address) public onlyRole(ADMINISTRATOR_ROLE) {
		universalRouter = _address;
		emit LinkUniversalRouter(_address);
	}
	
	function setPermit2Address(address _address) public onlyRole(ADMINISTRATOR_ROLE) {
		permit2Address = _address;
		emit LinkPermit2(_address);
	}
	
	function setUniswapV4Pool(address _address) public onlyRole(ADMINISTRATOR_ROLE) {
		uniswapV4Pool = _address;
		emit LinkUniswapV4Pool(_address);
		
		// Verify the pool exists
		require(_address != address(0), "MorpherOracle: Pool address cannot be zero");
	}

	function overrideGasForCallback(uint256 _gasForCallback) public onlyRole(ADMINISTRATOR_ROLE) {
		gasForCallback = _gasForCallback;
		emit SetGasForCallback(_gasForCallback);
	}

	function setGasForCallback(uint256 _gasForCallback) private {
		gasForCallback = _gasForCallback;
		emit SetGasForCallback(_gasForCallback);
	}

	function setCallbackCollectionAddress(address payable _address) public onlyRole(ADMINISTRATOR_ROLE) {
		callBackCollectionAddress = _address;
		emit CallBackCollectionAddressChange(_address);
	}

	// ----------------------------------------------------------------------------------
	// emitOrderFailed
	// Can be called by Oracle Operator to notifiy user of failed order
	// ----------------------------------------------------------------------------------
	function emitOrderFailed(
		bytes32 _orderId,
		address _address,
		bytes32 _marketId,
		uint256 _closeSharesAmount,
		uint256 _openMPHTokenAmount,
		bool _tradeDirection,
		uint256 _orderLeverage,
		uint256 _onlyIfPriceBelow,
		uint256 _onlyIfPriceAbove,
		uint256 _goodFrom,
		uint256 _goodUntil
	) public onlyRole(ORACLEOPERATOR_ROLE) {
		emit OrderFailed(
			_orderId,
			_address,
			_marketId,
			_closeSharesAmount,
			_openMPHTokenAmount,
			_tradeDirection,
			_orderLeverage,
			_onlyIfPriceBelow,
			_onlyIfPriceAbove,
			_goodFrom,
			_goodUntil
		);
	}

	// ----------------------------------------------------------------------------------
	// createOrder(bytes32  _marketId, bool _tradeAmountGivenInShares, uint256 _tradeAmount, bool _tradeDirection, uint256 _orderLeverage)
	// Request a new orderId from trade engine and fires event for price/liquidation check request.
	// ----------------------------------------------------------------------------------
	function createOrder(
		bytes32 _marketId,
		uint256 _closeSharesAmount,
		uint256 _openMPHTokenAmount,
		bool _tradeDirection,
		uint256 _orderLeverage,
		uint256 _onlyIfPriceAbove,
		uint256 _onlyIfPriceBelow,
		uint256 _goodUntil,
		uint256 _goodFrom
	) public payable whenNotPaused returns (bytes32 _orderId) {
		CreateOrderStruct memory createOrderStruct = CreateOrderStruct(
			_marketId,
			_closeSharesAmount,
			_openMPHTokenAmount,
			_tradeDirection,
			_orderLeverage,
			_onlyIfPriceAbove,
			_onlyIfPriceBelow,
			_goodUntil,
			_goodFrom
		);
		return createOrder(createOrderStruct);
	}

	function createOrder(
		CreateOrderStruct memory createOrderParams
	) public payable whenNotPaused returns (bytes32 _orderId) {
		if (gasForCallback > 0) {
			require(
				msg.value >= gasForCallback,
				"MorpherOracle: Must transfer gas costs for Oracle Callback function."
			);
			callBackCollectionAddress.transfer(msg.value);
		}
		_orderId = MorpherTradeEngine(state.morpherTradeEngineAddress()).requestOrderId(
			_msgSender(),
			createOrderParams._marketId,
			createOrderParams._closeSharesAmount,
			createOrderParams._openMPHTokenAmount,
			createOrderParams._tradeDirection,
			createOrderParams._orderLeverage
		);

		//if the market was deactivated, and the trader didn't fail yet, then we got an orderId to close the position with a locked in price
		if (state.getMarketActive(createOrderParams._marketId) == false) {
			//price will come from the position where price is stored forever
			MorpherTradeEngine(state.morpherTradeEngineAddress()).processOrder(
				_orderId,
				MorpherTradeEngine(state.morpherTradeEngineAddress()).getDeactivatedMarketPrice(
					createOrderParams._marketId
				),
				0,
				0,
				block.timestamp * (1000)
			);

			emit OrderProcessed(
				_orderId,
				MorpherTradeEngine(state.morpherTradeEngineAddress()).getDeactivatedMarketPrice(
					createOrderParams._marketId
				),
				0,
				0,
				0,
				block.timestamp * (1000),
				0,
				0,
				0,
				0,
				0,
				0
			);
		} else {
			priceAbove[_orderId] = createOrderParams._onlyIfPriceAbove;
			priceBelow[_orderId] = createOrderParams._onlyIfPriceBelow;
			goodFrom[_orderId] = createOrderParams._goodFrom;
			goodUntil[_orderId] = createOrderParams._goodUntil;
			emit OrderCreated(
				_orderId,
				_msgSender(),
				createOrderParams._marketId,
				createOrderParams._closeSharesAmount,
				createOrderParams._openMPHTokenAmount,
				createOrderParams._tradeDirection,
				createOrderParams._orderLeverage,
				createOrderParams._onlyIfPriceBelow,
				createOrderParams._onlyIfPriceAbove,
				createOrderParams._goodFrom,
				createOrderParams._goodUntil
			);
		}

		return _orderId;
	}

	function createOrderPermittedBySignature(
		CreateOrderStruct memory createOrderParams,
		address _addressPositionOwner,
		uint256 deadline,
		uint8 v,
		bytes32 r,
		bytes32 s
	) public returns (bytes32 orderId) {
		require(block.timestamp <= deadline, "MorpherOracle: expired deadline");

		bytes32 structHash = keccak256(
			abi.encode(
				_PERMIT_TYPEHASH,
				createOrderParams._marketId,
				createOrderParams._closeSharesAmount,
				createOrderParams._openMPHTokenAmount,
				_addressPositionOwner,
				_useNonce(_addressPositionOwner),
				deadline
			)
		);

		bytes32 hash = _hashTypedDataV4(structHash);

		address signer = ECDSAUpgradeable.recover(hash, v, r, s);
		require(signer == _addressPositionOwner, "MorpherOracle: invalid signature");
		msgSenderOverride = _addressPositionOwner;
		orderId = createOrder(createOrderParams);
		msgSenderOverride = address(0);
	}

	//sent directly from the owner
	function createOrderFromToken(
		CreateOrderStruct memory createOrderParams, //_openMphTokenAmount is the minimum swap amount (including slippage). the Actual token amount will be overwritten by the swapped output amount
		TokenPermitEIP712Struct memory inputToken
	) public {
		if (createOrderParams._openMPHTokenAmount > 0) {
			uint mphTokenAmountAfterSwap = permitTransferAndSwap(inputToken, createOrderParams._openMPHTokenAmount);
			createOrderParams._openMPHTokenAmount = mphTokenAmountAfterSwap; //overriding this as its exactInput for UI reasons
			// require(createOrderParams.openMPHTokenAmount <= amountOut, "MorpherOracle: OpenMPHTokenAmount bigger than conversion amount, aborting"); //it does not matter, because total balance of MPH counts here more
			createOrder(createOrderParams);
		} else {
			bytes32 orderId = createOrder(createOrderParams);
			closeOrderIdSwapToToken[orderId] = inputToken;
		}
	}

	function createOrderFromToken(
		CreateOrderStruct memory createOrderParams,
		TokenPermitEIP712Struct memory inputToken,
		address _addressPositionOwner,
		uint256 deadline,
		uint8 v,
		bytes32 r,
		bytes32 s
	) public {
		require(block.timestamp <= deadline, "MorpherOracle: expired deadline");

		bytes32 structHash = keccak256(
			abi.encode(
				_PERMIT_TYPEHASH,
				createOrderParams._marketId,
				createOrderParams._closeSharesAmount,
				createOrderParams._openMPHTokenAmount, //minimum amount of MPH token to be traded with, actual amount depends on the swap
				_addressPositionOwner,
				_useNonce(_addressPositionOwner),
				deadline
			)
		);

		bytes32 hash = _hashTypedDataV4(structHash);

		address signer = ECDSAUpgradeable.recover(hash, v, r, s);
		require(signer == _addressPositionOwner, "MorpherOracle: invalid signature");
		msgSenderOverride = _addressPositionOwner;

		createOrderFromToken(createOrderParams, inputToken);
		msgSenderOverride = address(0);
	}

	function permitTransferAndSwap(
		TokenPermitEIP712Struct memory inputToken,
		uint256 mphTokenAmount
	) internal returns (uint amountOut) {
		// Increase allowance with permit
		IERC20Permit(inputToken.tokenAddress).permit(
			inputToken.owner,
			address(this),
			inputToken.value,
			inputToken.deadline,
			inputToken.v,
			inputToken.r,
			inputToken.s
		);

		// Transfer input tokens to this contract
		SafeERC20Upgradeable.safeTransferFrom(
			IERC20Upgradeable(inputToken.tokenAddress),
			inputToken.owner,
			address(this),
			inputToken.value
		);

		// Approve tokens for Permit2
		IERC20Upgradeable(inputToken.tokenAddress).approve(permit2Address, type(uint256).max);
		
		// Approve Universal Router via Permit2
		IPermit2(permit2Address).approve(
			inputToken.tokenAddress,
			universalRouter,
			type(uint160).max,
			type(uint48).max
		);
		
		// Create PoolKey for the swap
		PoolKey memory poolKey;
		
		// Determine if we need a two-hop swap or a direct swap
		if (inputToken.tokenAddress != wMaticAddress) {
			// Two-hop swap: First swap input token to WETH, then WETH to MPH
			
			// First swap: input token to WETH
			// Create pool key for first swap (input token -> WETH)
			poolKey = createPoolKey(inputToken.tokenAddress, wMaticAddress);
			
			// Execute first swap
			uint256 wethAmount = executeSwap(
				poolKey,
				inputToken.tokenAddress,
				wMaticAddress,
				inputToken.value,
				0, // No minimum for intermediate swap
				address(this) // Receive WETH in this contract
			);
			
			// Second swap: WETH to MPH
			// Create pool key for second swap (WETH -> MPH)
			poolKey = createPoolKey(wMaticAddress, state.morpherTokenAddress());
			
			// Approve WETH for Permit2
			IERC20Upgradeable(wMaticAddress).approve(permit2Address, type(uint256).max);
			
			// Approve Universal Router via Permit2 for WETH
			IPermit2(permit2Address).approve(
				wMaticAddress,
				universalRouter,
				type(uint160).max,
				type(uint48).max
			);
			
			// Execute second swap
			amountOut = executeSwap(
				poolKey,
				wMaticAddress,
				state.morpherTokenAddress(),
				wethAmount,
				mphTokenAmount, // Minimum MPH to receive
				_msgSender() // Send MPH directly to the user
			);
		} else {
			// Direct swap from WETH to MPH
			poolKey = createPoolKey(wMaticAddress, state.morpherTokenAddress());
			
			amountOut = executeSwap(
				poolKey,
				wMaticAddress,
				state.morpherTokenAddress(),
				inputToken.value,
				mphTokenAmount, // Minimum MPH to receive
				_msgSender() // Send MPH directly to the user
			);
		}

		// Reset approvals (optional, since we used max approval)
		IERC20Upgradeable(inputToken.tokenAddress).approve(permit2Address, 0);
		
		return amountOut;
	}
	
	/**
	 * @dev Helper function to create a PoolKey for a token pair
	 * @param tokenA First token address
	 * @param tokenB Second token address
	 * @return key The PoolKey for the token pair
	 */
	function createPoolKey(address tokenA, address tokenB) internal pure returns (PoolKey memory key) {
		// Sort tokens by address
		(address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
		
		// Create Currency objects
		Currency currency0 = Currency.wrap(token0);
		Currency currency1 = Currency.wrap(token1);
		
		// Create and return the PoolKey
		return PoolKey({
			currency0: currency0,
			currency1: currency1,
			fee: 3000, // 0.3% fee tier
			tickSpacing: 60, // Standard tick spacing for 0.3% fee
			hooks: IHooks(address(0x0)) // No hooks
		});
	}
	
	/**
	 * @dev Execute a swap using Universal Router
	 * @param poolKey The PoolKey for the pool to swap on
	 * @param tokenIn Input token address
	 * @param tokenOut Output token address
	 * @param amountIn Amount of input tokens to swap
	 * @param amountOutMinimum Minimum amount of output tokens to receive
	 * @param recipient Address to receive the output tokens
	 * @return amountOut Amount of output tokens received
	 */
	function executeSwap(
		PoolKey memory poolKey,
		address tokenIn,
		address tokenOut,
		uint256 amountIn,
		uint256 amountOutMinimum,
		address recipient
	) internal returns (uint256 amountOut) {
		// Encode the Universal Router command
		bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
		bytes[] memory inputs = new bytes[](1);
		
		// Determine if we're swapping token0 for token1 or vice versa
		bool zeroForOne = equals(poolKey.currency0, Currency.wrap(tokenIn));
		
		// Encode V4Router actions
		bytes memory actions = abi.encodePacked(
			uint8(Actions.SWAP_EXACT_IN_SINGLE),
			uint8(Actions.SETTLE_ALL),
			uint8(Actions.TAKE_ALL)
		);
		
		// Prepare parameters for each action
		bytes[] memory params = new bytes[](3);
		
		// First parameter: swap configuration
		params[0] = abi.encode(
			IV4Router.ExactInputSingleParams({
				poolKey: PoolKey({
					currency0: poolKey.currency0,
					currency1: poolKey.currency1,
					fee: poolKey.fee,
					tickSpacing: poolKey.tickSpacing,
					hooks: poolKey.hooks
				}),
				zeroForOne: zeroForOne,
				amountIn: uint128(amountIn),
				amountOutMinimum: uint128(amountOutMinimum),
				hookData: bytes("")
			})
		);
		
		// Second parameter: specify input tokens for the swap (SETTLE_ALL)
		params[1] = abi.encode(zeroForOne ? poolKey.currency0 : poolKey.currency1, amountIn);
		
		// Third parameter: specify output tokens from the swap (TAKE_ALL)
		params[2] = abi.encode(zeroForOne ? poolKey.currency1 : poolKey.currency0, amountOutMinimum);
		
		// Combine actions and params into inputs
		inputs[0] = abi.encode(actions, params);
		
		// Get balance before swap to calculate actual output amount
		uint256 balanceBefore = IERC20(tokenOut).balanceOf(recipient);
		
		// Execute the swap
		IUniversalRouter(universalRouter).execute(
			commands,
			inputs,
			block.timestamp + 15 minutes // 15 minute deadline
		);
		
		// Calculate actual output amount
		if (recipient == address(this)) {
			amountOut = IERC20(tokenOut).balanceOf(recipient) - balanceBefore;
		} else {
			// For external recipient, we can't directly check the balance
			// We assume the swap was successful if we got here (no revert)
			amountOut = amountOutMinimum;
		}
		
		return amountOut;
	}

	function convertMphAndPayout(bytes32 orderId, uint mphTokenAmount) internal {
		//convert the MPH paid out by the close order back to the
		if (closeOrderIdSwapToToken[orderId].tokenAddress != address(0)) {
			TokenPermitEIP712Struct memory inputToken = closeOrderIdSwapToToken[orderId];
			//increase allowance
			IERC20Permit(state.morpherTokenAddress()).permit(
				inputToken.owner,
				address(this),
				inputToken.value,
				inputToken.deadline,
				inputToken.v,
				inputToken.r,
				inputToken.s
			);
			delete closeOrderIdSwapToToken[orderId];

			if (mphTokenAmount > inputToken.value) {
				emit MphCloseOrderSoftFail(orderId, mphTokenAmount, inputToken.value);
				return; //do nothing here, don't error out, just keep the MPH.
			}

			// Transfer `MPH payout` of Close position to this contract.
			SafeERC20Upgradeable.safeTransferFrom(
				IERC20Upgradeable(state.morpherTokenAddress()),
				inputToken.owner,
				address(this),
				mphTokenAmount
			);

			// Approve MPH for Permit2
			IERC20Upgradeable(state.morpherTokenAddress()).approve(permit2Address, type(uint256).max);
			
			// Approve Universal Router via Permit2
			IPermit2(permit2Address).approve(
				state.morpherTokenAddress(),
				universalRouter,
				type(uint160).max,
				type(uint48).max
			);

			if (inputToken.tokenAddress != wMaticAddress) {
				// Two-hop swap: First MPH to WETH, then WETH to target token
				
				// First swap: MPH to WETH
				PoolKey memory poolKey1 = createPoolKey(state.morpherTokenAddress(), wMaticAddress);
				
				uint256 wethAmount = executeSwap(
					poolKey1,
					state.morpherTokenAddress(),
					wMaticAddress,
					mphTokenAmount,
					0, // No minimum for intermediate swap
					address(this) // Receive WETH in this contract
				);
				
				// Approve WETH for Permit2
				IERC20Upgradeable(wMaticAddress).approve(permit2Address, type(uint256).max);
				
				// Approve Universal Router via Permit2 for WETH
				IPermit2(permit2Address).approve(
					wMaticAddress,
					universalRouter,
					type(uint160).max,
					type(uint48).max
				);
				
				// Second swap: WETH to target token
				PoolKey memory poolKey2 = createPoolKey(wMaticAddress, inputToken.tokenAddress);
				
				executeSwap(
					poolKey2,
					wMaticAddress,
					inputToken.tokenAddress,
					wethAmount,
					inputToken.minOutValue, // Minimum output value
					inputToken.owner // Send directly to the user
				);
			} else {
				// Direct swap from MPH to WETH
				PoolKey memory poolKey = createPoolKey(state.morpherTokenAddress(), wMaticAddress);
				
				executeSwap(
					poolKey,
					state.morpherTokenAddress(),
					wMaticAddress,
					mphTokenAmount,
					inputToken.minOutValue, // Minimum output value
					inputToken.owner // Send directly to the user
				);
			}
			
			// Reset approvals (optional, since we used max approval)
			IERC20Upgradeable(state.morpherTokenAddress()).approve(permit2Address, 0);
		}
	}

	/**
	 * @dev Returns the domain separator for the current chain.
	 */
	function _domainSeparatorV4() internal view returns (bytes32) {
		return _buildDomainSeparator(_TYPE_HASH, _EIP712NameHash(), _EIP712VersionHash());
	}

	function _buildDomainSeparator(
		bytes32 typeHash,
		bytes32 nameHash,
		bytes32 versionHash
	) private view returns (bytes32) {
		return keccak256(abi.encode(typeHash, nameHash, versionHash, block.chainid, address(this)));
	}

	/**
	 * @dev Given an already https://eips.ethereum.org/EIPS/eip-712#definition-of-hashstruct[hashed struct], this
	 * function returns the hash of the fully encoded EIP712 message for this domain.
	 *
	 * This hash can be used together with {ECDSA-recover} to obtain the signer of a message. For example:
	 *
	 * ```solidity
	 * bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(
	 *     keccak256("Mail(address to,string contents)"),
	 *     mailTo,
	 *     keccak256(bytes(mailContents))
	 * )));
	 * address signer = ECDSA.recover(digest, signature);
	 * ```
	 */
	function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32) {
		return ECDSAUpgradeable.toTypedDataHash(_domainSeparatorV4(), structHash);
	}

	/**
	 * @dev The hash of the name parameter for the EIP712 domain.
	 *
	 * NOTE: This function reads from storage by default, but can be redefined to return a constant value if gas costs
	 * are a concern.
	 */
	function _EIP712NameHash() internal view virtual returns (bytes32) {
		return _HASHED_NAME;
	}

	/**
	 * @dev The hash of the version parameter for the EIP712 domain.
	 *
	 * NOTE: This function reads from storage by default, but can be redefined to return a constant value if gas costs
	 * are a concern.
	 */
	function _EIP712VersionHash() internal view virtual returns (bytes32) {
		return _HASHED_VERSION;
	}
	
		
	/**
	 * @dev Set the MorpherSwapHelper address
	 * @param _helperAddress Address of the MorpherSwapHelper contract
	 */
	function setMorpherSwapHelperAddress(address _helperAddress) public onlyRole(ADMINISTRATOR_ROLE) {
		morpherSwapHelperAddress = _helperAddress;
	}
	
	/**
	 * @dev Get the MorpherSwapHelper address
	 * @return Address of the MorpherSwapHelper contract
	 */
	function getMorpherSwapHelperAddress() public view returns (address) {
		return morpherSwapHelperAddress;
	}

	/**
	 * @dev See {IERC20Permit-nonces}.
	 */
	function nonces(address owner) public view virtual returns (uint256) {
		return _nonces[owner].current();
	}

	/**
	 * @dev See {IERC20Permit-DOMAIN_SEPARATOR}.
	 */
	// solhint-disable-next-line func-name-mixedcase
	function DOMAIN_SEPARATOR() external view returns (bytes32) {
		return _domainSeparatorV4();
	}

	/**
	 * @dev "Consume a nonce": return the current value and increment.
	 *
	 * _Available since v4.1._
	 */
	function _useNonce(address owner) internal virtual returns (uint256 current) {
		CountersUpgradeable.Counter storage nonce = _nonces[owner];
		current = nonce.current();
		nonce.increment();
	}

	function initiateCancelOrder(bytes32 _orderId) public virtual {
		MorpherTradeEngine _tradeEngine = MorpherTradeEngine(state.morpherTradeEngineAddress());
		require(orderCancellationRequested[_orderId] == false, "MorpherOracle: Order was already canceled.");
		(address userId, , , , , , ) = _tradeEngine.getOrder(_orderId);
		require(userId == _msgSender(), "MorpherOracle: Only the user can request an order cancellation.");
		orderCancellationRequested[_orderId] = true;
		emit OrderCancellationRequestedEvent(_orderId, _msgSender());
	}

	function initiateCancelOrderPermitted(
		bytes32 _orderId,
		address _owner,
		uint256 deadline,
		uint8 v,
		bytes32 r,
		bytes32 s
	) public virtual {
		require(block.timestamp <= deadline, "MorpherOracle: expired deadline");

		bytes32 structHash = keccak256(
			abi.encode(
				_CANCEL_ORDER_TYPEHASH,
				_orderId,
				_owner,
				_useNonce(_owner),
				deadline
			)
		);

		bytes32 hash = _hashTypedDataV4(structHash);

		address signer = ECDSAUpgradeable.recover(hash, v, r, s);
		require(signer == _owner, "MorpherOracle: invalid signature");
		
		msgSenderOverride = _owner;
		initiateCancelOrder(_orderId);
		msgSenderOverride = address(0);
	}

	// ----------------------------------------------------------------------------------
	// cancelOrder(bytes32  _orderId)
	// User or Administrator can cancel their own orders before the _callback has been executed
	// ----------------------------------------------------------------------------------
	function cancelOrder(bytes32 _orderId) public onlyRole(ORACLEOPERATOR_ROLE) {
		require(orderCancellationRequested[_orderId] == true, "MorpherOracle: Order-Cancellation was not requested.");
		MorpherTradeEngine _tradeEngine = MorpherTradeEngine(state.morpherTradeEngineAddress());
		(address userId, , , , , , ) = _tradeEngine.getOrder(_orderId);
		_tradeEngine.cancelOrder(_orderId, userId);
		clearOrderConditions(_orderId);
		emit OrderCancelled(_orderId, userId, _msgSender());
	}

	// ------------------------------------------------------------------------
	// checkOrderConditions(bytes32 _orderId, uint256 _price)
	// Checks if callback satisfies the order conditions
	// ------------------------------------------------------------------------
	function checkOrderConditions(bytes32 _orderId, uint256 _price) public view returns (bool _conditionsMet) {
		_conditionsMet = true;
		if (block.timestamp > goodUntil[_orderId] && goodUntil[_orderId] > 0) {
			_conditionsMet = false;
		}
		if (block.timestamp < goodFrom[_orderId] && goodFrom[_orderId] > 0) {
			_conditionsMet = false;
		}

		if (priceAbove[_orderId] > 0 && priceBelow[_orderId] > 0) {
			if (_price < priceAbove[_orderId] && _price > priceBelow[_orderId]) {
				_conditionsMet = false;
			}
		} else {
			if (_price < priceAbove[_orderId] && priceAbove[_orderId] > 0) {
				_conditionsMet = false;
			}
			if (_price > priceBelow[_orderId] && priceBelow[_orderId] > 0) {
				_conditionsMet = false;
			}
		}

		return _conditionsMet;
	}

	// ----------------------------------------------------------------------------------
	// Deletes parameters of cancelled or processed orders
	// ----------------------------------------------------------------------------------
	function clearOrderConditions(bytes32 _orderId) internal {
		priceAbove[_orderId] = 0;
		priceBelow[_orderId] = 0;
		goodFrom[_orderId] = 0;
		goodUntil[_orderId] = 0;
	}

	function pause() public virtual onlyRole(PAUSER_ROLE) {
		_pause();
	}

	function unpause() public virtual onlyRole(PAUSER_ROLE) {
		_unpause();
	}

	// ----------------------------------------------------------------------------------
	// createLiquidationOrder(address _address, bytes32 _marketId)
	// Checks if position has been liquidated since last check. Requires gas for callback
	// function. Anyone can issue a liquidation order for any other address and market.
	// ----------------------------------------------------------------------------------
	function createLiquidationOrder(
		address _address,
		bytes32 _marketId
	) public payable whenNotPaused onlyRole(ORACLEOPERATOR_ROLE) returns (bytes32 _orderId) {
		if (gasForCallback > 0) {
			require(
				msg.value >= gasForCallback,
				"MorpherOracle: Must transfer gas costs for Oracle Callback function."
			);
			callBackCollectionAddress.transfer(msg.value);
		}
		_orderId = MorpherTradeEngine(state.morpherTradeEngineAddress()).requestOrderId(
			_address,
			_marketId,
			0,
			0,
			true,
			10 ** 8
		);
		emit LiquidationOrderCreated(_orderId, _msgSender(), _address, _marketId);
		return _orderId;
	}

	// ----------------------------------------------------------------------------------
	// __callback(bytes32 _orderId, uint256 _price, uint256 _spread, uint256 _liquidationTimestamp, uint256 _timeStamp)
	// Called by the oracle operator. Writes price/spread/liquidiation check to the blockchain.
	// Trade engine processes the order and updates the portfolio in state if successful.
	// ----------------------------------------------------------------------------------
	function __callback(
		bytes32 _orderId,
		uint256 _price,
		uint256 _unadjustedMarketPrice,
		uint256 _spread,
		uint256 _liquidationTimestamp,
		uint256 _timeStamp,
		uint256 _gasForNextCallback
	) public onlyRole(ORACLEOPERATOR_ROLE) whenNotPaused returns (MorpherTradeEngine.position memory createdPosition) {
		require(checkOrderConditions(_orderId, _price), "MorpherOracle Error: Order Conditions are not met");
		(address positionOwnerAddress, , , , , , , , , , , ) = MorpherTradeEngine(state.morpherTradeEngineAddress())
			.orders(_orderId);
		uint balanceBeforeClose = IERC20Upgradeable(state.morpherTokenAddress()).balanceOf(positionOwnerAddress);

		createdPosition = MorpherTradeEngine(state.morpherTradeEngineAddress()).processOrder(
			_orderId,
			_price,
			_spread,
			_liquidationTimestamp,
			_timeStamp
		);

		clearOrderConditions(_orderId);
		emit OrderProcessed(
			_orderId,
			_price,
			_unadjustedMarketPrice,
			_spread,
			_liquidationTimestamp,
			_timeStamp,
			createdPosition.longShares,
			createdPosition.shortShares,
			createdPosition.meanEntryPrice,
			createdPosition.meanEntrySpread,
			createdPosition.meanEntryLeverage,
			createdPosition.liquidationPrice
		);
		setGasForCallback(_gasForNextCallback);

		uint balanceBeforeAfter = IERC20Upgradeable(state.morpherTokenAddress()).balanceOf(positionOwnerAddress);
		if (balanceBeforeAfter > balanceBeforeClose) {
			convertMphAndPayout(_orderId, balanceBeforeAfter - balanceBeforeClose);
		}
		return createdPosition;
	}

	// ----------------------------------------------------------------------------------
	// delistMarket(bytes32 _marketId)
	// Administrator closes out all existing positions on _marketId market at current prices
	// ----------------------------------------------------------------------------------

	function delistMarket(bytes32 _marketId, bool _startFromScratch) public onlyRole(ADMINISTRATOR_ROLE) {
		require(state.getMarketActive(_marketId) == true, "Market must be active to process position liquidations.");
		// If no _fromIx and _toIx specified, do entire _list
		if (_startFromScratch) {
			delistMarketFromIx = 0;
		}

		uint _toIx = MorpherTradeEngine(state.morpherTradeEngineAddress()).getMaxMappingIndex(_marketId);

		address _address;
		for (uint256 i = delistMarketFromIx; i <= _toIx; i++) {
			if (gasleft() < 250000 && i != _toIx) {
				//stop if there's not enough gas to write the next transaction
				delistMarketFromIx = i;
				emit DelistMarketIncomplete(_marketId, _toIx);
				return;
			}

			_address = MorpherTradeEngine(state.morpherTradeEngineAddress()).getExposureMappingAddress(_marketId, i);
			adminLiquidationOrder(_address, _marketId);
		}
		emit DelistMarketComplete(_marketId);
	}

	// ----------------------------------------------------------------------------------
	// adminLiquidationOrder(address _address, bytes32 _marketId)
	// Administrator closes out an existing position of _address on _marketId market at current price
	// ----------------------------------------------------------------------------------
	function adminLiquidationOrder(
		address _address,
		bytes32 _marketId
	) public onlyRole(ADMINISTRATOR_ROLE) returns (bytes32 _orderId) {
		MorpherTradeEngine.position memory position = MorpherTradeEngine(state.morpherTradeEngineAddress()).getPosition(
			_address,
			_marketId
		);

		if (position.longShares > 0) {
			_orderId = MorpherTradeEngine(state.morpherTradeEngineAddress()).requestOrderId(
				_address,
				_marketId,
				position.longShares,
				0,
				false,
				10 ** 8
			);
			emit AdminLiquidationOrderCreated(_orderId, _address, _marketId, position.longShares, 0, false, 10 ** 8);
		}
		if (position.shortShares > 0) {
			_orderId = MorpherTradeEngine(state.morpherTradeEngineAddress()).requestOrderId(
				_address,
				_marketId,
				position.shortShares,
				0,
				true,
				10 ** 8
			);
			emit AdminLiquidationOrderCreated(_orderId, _address, _marketId, position.shortShares, 0, true, 10 ** 8);
		}
		return _orderId;
	}

	/**
	 * @dev Create an order using native ETH/gas token
	 * @param createOrderParams The order parameters
	 * @return orderId The ID of the created order
	 */
	function createOrderFromGasToken(
		CreateOrderStruct memory createOrderParams
	) public payable whenNotPaused returns (bytes32 orderId) {
		require(msg.value > 0, "MorpherOracle: Must send ETH to swap");
		
		// Calculate gas for callback
		uint256 ethForSwap = msg.value;
		if (gasForCallback > 0) {
			require(
				msg.value > gasForCallback,
				"MorpherOracle: Must transfer gas costs for Oracle Callback function."
			);
			callBackCollectionAddress.transfer(gasForCallback);
			ethForSwap = msg.value - gasForCallback;
		}
		
		// Wrap ETH to WETH
		IWETH9(wMaticAddress).deposit{value: ethForSwap}();
		
		// Swap WETH for MPH
		uint256 mphTokenAmount = swapWETHForMPH(ethForSwap, createOrderParams._openMPHTokenAmount);
		
		// Update the order params with the actual MPH amount received
		createOrderParams._openMPHTokenAmount = mphTokenAmount;
		
		// Create the order
		return createOrder(createOrderParams);
	}

	/**
	 * @dev Swap WETH for MPH tokens using Universal Router
	 * @param wethAmount Amount of WETH to swap
	 * @param minMphAmount Minimum amount of MPH tokens to receive
	 * @return amountOut Amount of MPH tokens received
	 */
	function swapWETHForMPH(uint256 wethAmount, uint256 minMphAmount) internal returns (uint256 amountOut) {
		// Approve WETH for Permit2
		IWETH9(wMaticAddress).approve(permit2Address, type(uint256).max);
		
		// Approve Universal Router via Permit2
		IPermit2(permit2Address).approve(
			wMaticAddress,
			universalRouter,
			type(uint160).max,
			type(uint48).max
		);
		
		// Create pool key for the swap
		PoolKey memory poolKey = createPoolKey(wMaticAddress, state.morpherTokenAddress());
		
		// Execute the swap
		amountOut = executeSwap(
			poolKey,
			wMaticAddress,
			state.morpherTokenAddress(),
			wethAmount,
			minMphAmount,
			_msgSender() // Send MPH directly to the user
		);
		
		return amountOut;
	}

	/**
	 * Deprecated function
	 */
	function getTradeEngineFromOrderId(uint orderId) public view returns (address) {
		orderId = orderId; //mute the warning
		return state.morpherTradeEngineAddress();
	}
}
