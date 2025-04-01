//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.15;

/**
*  
*  
*  ███╗   ███╗ ██████╗ ██████╗ ██████╗ ██╗  ██╗███████╗██████╗ 
*  ████╗ ████║██╔═══██╗██╔══██╗██╔══██╗██║  ██║██╔════╝██╔══██╗
*  ██╔████╔██║██║   ██║██████╔╝██████╔╝███████║█████╗  ██████╔╝
*  ██║╚██╔╝██║██║   ██║██╔══██╗██╔═══╝ ██╔══██║██╔══╝  ██╔══██╗
*  ██║ ╚═╝ ██║╚██████╔╝██║  ██║██║     ██║  ██║███████╗██║  ██║
*  ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝
*                                                              
*  Website: https://www.morpher.com - Operating Since 2021
*  
*  This is the Morpher Oracle, a contract that allows anyone to trade synthetic markets directly on-chain.
*
*  Positions can be opened using MPH or a number of ERC20 tokens which are converted transparently via 
*  uniswap to MPH. Trades can also be made in ETH (gas tokens), which are auto-wrapped into WETH and then 
*  converted via uniswap to MPH.
*
*  Positions are created via the Morpher Trade Engine and held in your own wallet until closed.
*
*  This means: 
*  Your keys - your money. You own it. No bureaucracy. No paperwork. No backdoors. Audited and proven. 
*  Transparent with verified sources on-chain.
*  
*  Margin: You can never go into debt. No separate margin account needed. Trade with up to 10x leverage. 
*
*  Trade Stocks, Crypto, Commodities, Forex and some really unique markets without the complexity and 
*  without the platform risk. 
*
*  Join the trading revolution today! Open your first position at https://www.morpher.com
*  
**/

import "./MorpherTradeEngine.sol";
import "./MorpherState.sol";
import "./MorpherAccessControl.sol"; // Use adapted v5 interface

// --- V5 Imports ---
// import "../lib/openzeppelin-contracts-upgradeable-5/contracts/utils/cryptography/MerkleProofUpgradeable.sol"; // MerkleProof not used? Remove if unused.
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ContextUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/utils/ContextUpgradeable.sol"; // Keep for _msgSender override
import {PausableUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/utils/PausableUpgradeable.sol";
import {EIP712Upgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/utils/cryptography/EIP712Upgradeable.sol";
import {NoncesUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/utils/NoncesUpgradeable.sol"; // Use Nonces instead of Counters
import {ECDSAUpgradeable} from "../lib/openzeppelin-contracts-5/contracts/utils/cryptography/ECDSA.sol"; // Use non-upgradeable ECDSA
import {IERC20Permit} from "../lib/openzeppelin-contracts-5/contracts/token/ERC20/extensions/IERC20Permit.sol"; // Use non-upgradeable interface

import {IERC20} from "../lib/openzeppelin-contracts-5/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts-5/contracts/token/ERC20/utils/SafeERC20.sol";

import "../lib/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol"; // Keep external interface
import "../lib/uniswap-v3-periphery/contracts/interfaces/IPeripheryPayments.sol";
import "../lib/uniswap-v3-periphery/contracts/interfaces/external/IWETH9.sol";
import "../lib/universal-router/contracts/interfaces/IUniversalRouter.sol";

// ----------------------------------------------------------------------------------
// Morpher Oracle contract v 2.0
// The oracle initates a new trade by calling trade engine and requesting a new orderId.
// An event is fired by the contract notifying the oracle operator to query a price/liquidation unchecked
// for a market/user and return the information via the callback function. Since calling
// the callback function requires gas, the user must send a fixed amount of Ether when
// creating their order.
// ----------------------------------------------------------------------------------

/// @custom:oz-upgrades-from contracts/prev/contracts/MorpherOracle.sol:MorpherOracle
contract MorpherOracle is UUPSUpgradeable, ContextUpgradeable, PausableUpgradeable, EIP712Upgradeable, NoncesUpgradeable { // Update inheritance
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

	// using CountersUpgradeable for CountersUpgradeable.Counter; // Replaced by NoncesUpgradeable

	/**
	 * Permit functionality (using EIP712Upgradeable base)
	 * Added after proxy was deployed, so manually adding functionality here
	 */
	// --- Remove manual EIP712 state ---
	// bytes32 public constant _HASHED_NAME = ...; // Handled by EIP712Upgradeable
	// bytes32 public constant _HASHED_VERSION = ...; // Handled by EIP712Upgradeable
	// bytes32 public constant _TYPE_HASH = ...; // Handled by EIP712Upgradeable

	// --- Keep action-specific typehashes ---
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

	uint24 public constant poolFee = 3000;

	mapping(bytes32 => TokenPermitEIP712Struct) closeOrderIdSwapToToken; //tokenAddress will be the target address, the permit needs to be for MPH and needs to be larger than the MPH amount to be closed otherwise it will fail.

	address private msgSenderOverride;

	address public wMaticAddress;

	// mapping(address => CountersUpgradeable.Counter) private _nonces; // Replaced by NoncesUpgradeable internal mapping

	// MorpherSwapHelper addresses by chain
	address public morpherSwapHelperAddress;


	// SwapRouter address - used for direct swaps
	address public uniswapRouter;


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
	event LinkUniswapRouter(address _address);

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
		require( // Keep using _msgSender()
			MorpherAccessControl(state.morpherAccessControlAddress()).hasRole(role, _msgSender()),
			"MorpherOracle: Permission denied."
		);
		_;
	}

	// --- Updated Initializer ---
	function initialize(
		address _morpherState,
		address payable _gasCollectionAddress,
		uint256 _gasForCallback,
		string memory _eip712Name, // Add EIP712 params
		string memory _eip712Version
	) public initializer {
		__UUPSUpgradeable_init();
		__Context_init(); // Initialize Context
		__Pausable_init(); // Initialize Pausable
		__EIP712_init(_eip712Name, _eip712Version); // Initialize EIP712
		__Nonces_init(); // Initialize Nonces

		state = MorpherState(_morpherState);

		callBackCollectionAddress = _gasCollectionAddress; // Set directly, avoid extra function call if possible
		gasForCallback = _gasForCallback; // Set directly
		// Emit events if needed
		emit CallBackCollectionAddressChange(_gasCollectionAddress);
		emit SetGasForCallback(_gasForCallback);
	}

	// --- Implement _authorizeUpgrade ---
	function _authorizeUpgrade(address newImplementation)
		internal
		override
	{
		address accessControlAddress = state.morpherAccessControlAddress();
		require(accessControlAddress != address(0), "MorpherOracle: AccessControl not set in State");
		// Check if the sender has the PROXYUPDATER_ROLE defined in MorpherAccessControl
		require(
			MorpherAccessControl(accessControlAddress).hasRole(
				MorpherAccessControl(accessControlAddress).PROXYUPDATER_ROLE(), // Get role hash from AC
				msg.sender // Use msg.sender directly
			),
			"MorpherOracle: Caller is not the proxy updater"
		);
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
	
	function setUniswapRouter(address _address) public onlyRole(ADMINISTRATOR_ROLE) {
		uniswapRouter = _address;
		emit LinkUniswapRouter(_address);
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

		// Use _useNonce from NoncesUpgradeable
		uint256 currentNonce = _useNonce(_addressPositionOwner);

		bytes32 structHash = keccak256(
			abi.encode(
				_PERMIT_TYPEHASH,
				createOrderParams._marketId,
				createOrderParams._closeSharesAmount,
				createOrderParams._openMPHTokenAmount,
				_addressPositionOwner,
				currentNonce, // Use the consumed nonce
				deadline
			)
		);

		// Use _hashTypedDataV4 from EIP712Upgradeable
		bytes32 digest = _hashTypedDataV4(structHash);

		// Use ECDSA library directly
		address signer = ECDSAUpgradeable.recover(digest, v, r, s);
		require(signer == _addressPositionOwner, "MorpherOracle: invalid signature");

		// Keep msgSenderOverride logic
		msgSenderOverride = _addressPositionOwner;
		orderId = createOrder(createOrderParams);
		msgSenderOverride = address(0);
	}

	//sent directly from the owner
	function createOrderFromToken(
		CreateOrderStruct memory createOrderParams, //_openMphTokenAmount is the minimum swap amount (including slippage). the Actual token amount will be overwritten by the swapped output amount
		TokenPermitEIP712Struct memory inputToken
	) public returns(bytes32) {
		if (createOrderParams._openMPHTokenAmount > 0) {
			uint mphTokenAmountAfterSwap = permitTransferAndSwap(inputToken, createOrderParams._openMPHTokenAmount);
			createOrderParams._openMPHTokenAmount = mphTokenAmountAfterSwap; //overriding this as its exactInput for UI reasons
			// require(createOrderParams.openMPHTokenAmount <= amountOut, "MorpherOracle: OpenMPHTokenAmount bigger than conversion amount, aborting"); //it does not matter, because total balance of MPH counts here more
			return createOrder(createOrderParams);
		} else {
			bytes32 orderId = createOrder(createOrderParams);
			closeOrderIdSwapToToken[orderId] = inputToken;
			return orderId;
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

		// Use _hashTypedDataV4 from EIP712Upgradeable
		bytes32 digest = _hashTypedDataV4(structHash);

		// Use ECDSA library directly
		address signer = ECDSAUpgradeable.recover(digest, v, r, s);
		require(signer == _addressPositionOwner, "MorpherOracle: invalid signature");

		// Keep msgSenderOverride logic
		msgSenderOverride = _addressPositionOwner;
		createOrderFromToken(createOrderParams, inputToken);
		msgSenderOverride = address(0);
	}

	function permitTransferAndSwap(
		TokenPermitEIP712Struct memory inputToken,
		uint256 mphTokenAmount
	) internal returns (uint amountOut) {
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
		IERC20(state.morpherTokenAddress()).approve(uniswapRouter, mphTokenAmount);

		bytes memory path;

		if (inputToken.tokenAddress != wMaticAddress) {
			path = abi.encodePacked( //reversed path for exactOutput! FU oz!
					inputToken.tokenAddress,
					poolFee,
					wMaticAddress,
					poolFee,
					state.morpherTokenAddress()
				);
		} else {
			path = abi.encodePacked(wMaticAddress, poolFee, state.morpherTokenAddress()); //reversed path for exactOutput! FU oz!
		}

		IV3SwapRouter swapRouter = IV3SwapRouter(uniswapRouter);
		IV3SwapRouter.ExactInputParams memory inputSwapParams = IV3SwapRouter.ExactInputParams({
			path: path,
			recipient: _msgSender(),
			amountOutMinimum: mphTokenAmount,
			amountIn: inputToken.value //safeguarded by the permit functionality.
		});

		amountOut = swapRouter.exactInput(inputSwapParams);

		// ISwapRouter swapRouter = ISwapRouter(UNISWAP_ROUTER);
		// ISwapRouter.ExactOutputParams memory outputSwapParams = ISwapRouter.ExactOutputParams({
		// 	path: path,
		// 	recipient: _msgSender(),
		// 	deadline: block.timestamp,
		// 	amountOut: mphTokenAmount,
		// 	amountInMaximum: inputToken.value //safeguarded by the permit functionality.
		// });

		// uint amountIn = swapRouter.exactOutput(outputSwapParams);

		// //TransferBack the remainder
		// IERC20(inputToken.tokenAddress).transfer(inputToken.owner, inputToken.value - amountIn);

		//reset the approved amounts
		IERC20(inputToken.tokenAddress).approve(uniswapRouter, 0);
		IERC20(state.morpherTokenAddress()).approve(uniswapRouter, 0);
	}

	function convertMphAndPayout(bytes32 orderId, uint mphTokenAmount) internal {
		//convert the MPH paid out by the close order back to the
		if (closeOrderIdSwapToToken[orderId].tokenAddress != address(0)) {
			IV3SwapRouter swapRouter = IV3SwapRouter(uniswapRouter);

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

			// MorpherTradeEngine tradeEngine = MorpherTradeEngine(state.morpherTradeEngineAddress());
			// (, , , , , , , , , , , MorpherTradeEngine.OrderModifier memory oldOrder) = tradeEngine.orders(orderId);
			// uint mphTokenAmount = oldOrder.balanceUp; //never try to transfer more than the user gave permission for
			if (mphTokenAmount > inputToken.value) {
				emit MphCloseOrderSoftFail(orderId, mphTokenAmount, inputToken.value);
				return; //do nothing here, don't error out, just keep the MPH.
			}

			// Transfer `MPH payout` of Close position to this contract.
			SafeERC20.safeTransferFrom(
				IERC20(state.morpherTokenAddress()),
				inputToken.owner,
				address(this),
				mphTokenAmount
			);

			// Approve the router to spend the token.
			IERC20(state.morpherTokenAddress()).approve(uniswapRouter, mphTokenAmount);

			// SafeERC20.safeApprove(
			// 	IERC20(state.morpherTokenAddress()),
			// 	address(swapRouter),
			// 	mphTokenAmount
			// );

			bytes memory path;

			if (inputToken.tokenAddress != wMaticAddress) {
				path = abi.encodePacked(
					state.morpherTokenAddress(),
					poolFee,
					wMaticAddress,
					poolFee,
					inputToken.tokenAddress
				);
			} else {
				path = abi.encodePacked(state.morpherTokenAddress(), poolFee, wMaticAddress);
			}

			IV3SwapRouter.ExactInputParams memory backConvertParams = IV3SwapRouter.ExactInputParams({
				path: path,
				recipient: inputToken.owner,
				amountIn: mphTokenAmount,
				amountOutMinimum: inputToken.minOutValue
			});

			// swap the remaining token back
			swapRouter.exactInput(backConvertParams);
			IERC20(state.morpherTokenAddress()).approve(uniswapRouter, 0);
		}
	}

	// --- Remove manual EIP712 functions ---
	// function _domainSeparatorV4() ... // Provided by EIP712Upgradeable
	// function _buildDomainSeparator(...) ... // Handled by EIP712Upgradeable
	// function _hashTypedDataV4(...) ... // Provided by EIP712Upgradeable
	// function _EIP712NameHash() ... // Handled by EIP712Upgradeable
	// function _EIP712VersionHash() ... // Handled by EIP712Upgradeable

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
	 * @dev See {IERC20Permit-nonces}. Returns the nonce used by NoncesUpgradeable.
	 */
	function nonces(address owner) public view virtual override(NoncesUpgradeable) returns (uint256) {
		return super.nonces(owner); // Use implementation from NoncesUpgradeable
	}

	/**
	 * @dev See {IERC20Permit-DOMAIN_SEPARATOR}. Returns the domain separator provided by EIP712Upgradeable.
	 */
	// solhint-disable-next-line func-name-mixedcase
	function DOMAIN_SEPARATOR() external view override returns (bytes32) { // Add override
		return _domainSeparatorV4(); // Use implementation from EIP712Upgradeable
	}

	// --- Remove manual _useNonce ---
	// function _useNonce(...) ... // Provided by NoncesUpgradeable

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

		// Use _useNonce from NoncesUpgradeable
		uint256 currentNonce = _useNonce(_owner);

		bytes32 structHash = keccak256(
			abi.encode(
				_CANCEL_ORDER_TYPEHASH,
				_orderId,
				_owner,
				currentNonce, // Use consumed nonce
				deadline
			)
		);

		// Use _hashTypedDataV4 from EIP712Upgradeable
		bytes32 digest = _hashTypedDataV4(structHash);

		// Use ECDSA library directly
		address signer = ECDSAUpgradeable.recover(digest, v, r, s);
		require(signer == _owner, "MorpherOracle: invalid signature");

		// Keep msgSenderOverride logic
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
		uint balanceBeforeClose = IERC20(state.morpherTokenAddress()).balanceOf(positionOwnerAddress);

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

		uint balanceBeforeAfter = IERC20(state.morpherTokenAddress()).balanceOf(positionOwnerAddress);
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
	 * @dev Swap WETH for MPH tokens
	 * @param wethAmount Amount of WETH to swap
	 * @param minMphAmount Minimum amount of MPH tokens to receive
	 * @return amountOut Amount of MPH tokens received
	 */
	function swapWETHForMPH(uint256 wethAmount, uint256 minMphAmount) internal returns (uint256 amountOut) {
		// Approve the router to spend WETH
		IWETH9(wMaticAddress).approve(uniswapRouter, wethAmount);
		
		// Create the swap path
		bytes memory path = abi.encodePacked(
			wMaticAddress,
			poolFee,
			state.morpherTokenAddress()
		);
		
		// Execute the swap
		IV3SwapRouter swapRouter = IV3SwapRouter(uniswapRouter);
		IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter.ExactInputParams({
			path: path,
			recipient: _msgSender(),
			amountIn: wethAmount,
			amountOutMinimum: minMphAmount
		});
		
		amountOut = swapRouter.exactInput(params);
		
		// Reset approvals
		IWETH9(wMaticAddress).approve(uniswapRouter, 0);
		
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
