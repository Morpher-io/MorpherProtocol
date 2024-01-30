//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.11;

import "./MorpherTradeEngine.sol";
import "./MorpherState.sol";
import "./MorpherAccessControl.sol";

import "@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IPeripheryPayments.sol";

// ----------------------------------------------------------------------------------
// Morpher Oracle contract v 2.0
// The oracle initates a new trade by calling trade engine and requesting a new orderId.
// An event is fired by the contract notifying the oracle operator to query a price/liquidation unchecked
// for a market/user and return the information via the callback function. Since calling
// the callback function requires gas, the user must send a fixed amount of Ether when
// creating their order.
// ----------------------------------------------------------------------------------

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

	/**
	 * Permit functionality
	 * Added after proxy was deployed, so manually adding functionality here
	 */
	bytes32 public constant _HASHED_NAME = 0xca82a94b3c35be4fb8e06faa102ba96b016e9c5dd45f747224333f012bfd5e6a;
	bytes32 public constant _HASHED_VERSION = 0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6;
	bytes32 public constant _TYPE_HASH =
		keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

	address public constant UNISWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

	using CountersUpgradeable for CountersUpgradeable.Counter;

	mapping(address => CountersUpgradeable.Counter) private _nonces;

	// solhint-disable-next-line var-name-mixedcase
	bytes32 public constant _PERMIT_TYPEHASH =
		keccak256(
			"CreateOrder(bytes32 _marketId,uint256 _closeSharesAmount,uint256 _openMPHTokenAmount,address _msgSender,uint256 nonce,uint256 deadline)"
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

	address private msgSenderOverride;
	
	mapping(bytes32 => TokenPermitEIP712Struct) closeOrderIdSwapToToken; //tokenAddress will be the target address, the permit needs to be for MPH and needs to be larger than the MPH amount to be closed otherwise it will fail.

	uint24 public constant poolFee = 3000;
	
	address public wMaticAddress;
	

	function _msgSender() internal view override returns (address) {
		if (msgSenderOverride != address(0)) {
			return msgSenderOverride;
		}

		return msg.sender;
	}

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
		CreateOrderStruct memory createOrderParams,
		TokenPermitEIP712Struct memory inputToken
	) public {
		if (createOrderParams._openMPHTokenAmount > 0) {
			permitTransferAndSwap(inputToken, createOrderParams._openMPHTokenAmount);
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

		createOrderFromToken(createOrderParams, inputToken);
		msgSenderOverride = address(0);
	}
	
	

    function permitTransferAndSwap(TokenPermitEIP712Struct memory inputToken, uint256 mphTokenAmount) internal {
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
			SafeERC20Upgradeable.safeTransferFrom(
				IERC20Upgradeable(inputToken.tokenAddress),
				inputToken.owner,
				address(this),
				inputToken.value
			);

			// Approve the router to spend the token.
			IERC20Upgradeable(inputToken.tokenAddress).approve(address(UNISWAP_ROUTER), inputToken.value);
			IERC20Upgradeable(state.morpherTokenAddress()).approve(address(UNISWAP_ROUTER), mphTokenAmount);

			bytes memory path;

			if(inputToken.tokenAddress != wMaticAddress) {
				path = abi.encodePacked( //reversed path for exactOutput! FU oz!
					state.morpherTokenAddress(),
					poolFee,
					wMaticAddress,
					poolFee,
					inputToken.tokenAddress
				);
			} else {
				path = abi.encodePacked( //reversed path for exactOutput! FU oz!
					state.morpherTokenAddress(),
					poolFee,
					wMaticAddress
				);
			}

			ISwapRouter swapRouter = ISwapRouter(UNISWAP_ROUTER);
			ISwapRouter.ExactOutputParams memory outputSwapParams = ISwapRouter.ExactOutputParams({
				path: path,
				recipient: _msgSender(),
				deadline: block.timestamp,
				amountOut: mphTokenAmount,
				amountInMaximum: inputToken.value //safeguarded by the permit functionality.
			});

			uint amountIn = swapRouter.exactOutput(outputSwapParams);

			//TransferBack the remainder
			IERC20Upgradeable(inputToken.tokenAddress).transfer(
				inputToken.owner,
				inputToken.value - amountIn
			);
			
			//reset the approved amounts
			IERC20Upgradeable(inputToken.tokenAddress).approve(address(UNISWAP_ROUTER), 0);
			IERC20Upgradeable(state.morpherTokenAddress()).approve(address(UNISWAP_ROUTER), 0);
			
    }

	function convertMphAndPayout(bytes32 orderId) internal {
		//convert the MPH paid out by the close order back to the
		if (closeOrderIdSwapToToken[orderId].tokenAddress != address(0)) {
			ISwapRouter swapRouter = ISwapRouter(UNISWAP_ROUTER);

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

			MorpherTradeEngine tradeEngine = MorpherTradeEngine(state.morpherTradeEngineAddress());
			(, , , , , , , , , , , MorpherTradeEngine.OrderModifier memory oldOrder) = tradeEngine.orders(orderId);
			uint mphTokenAmount = oldOrder.balanceUp;

			SafeERC20Upgradeable.safeApprove(IERC20Upgradeable(state.morpherTokenAddress()), address(swapRouter), mphTokenAmount);
			ISwapRouter.ExactInputParams memory backConvertParams =
			ISwapRouter.ExactInputParams({
			    path: abi.encodePacked(state.morpherTokenAddress(), poolFee, wMaticAddress, poolFee, inputToken.tokenAddress),
			    recipient: inputToken.owner,
			    deadline: block.timestamp,
			    amountIn: inputToken.value,
			    amountOutMinimum: inputToken.minOutValue
			});

			// swap the remaining token back
			swapRouter.exactInput(backConvertParams);
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

	function initiateCancelOrder(bytes32 _orderId) public {
		MorpherTradeEngine _tradeEngine = MorpherTradeEngine(state.morpherTradeEngineAddress());
		require(orderCancellationRequested[_orderId] == false, "MorpherOracle: Order was already canceled.");
		(address userId, , , , , , ) = _tradeEngine.getOrder(_orderId);
		require(userId == _msgSender(), "MorpherOracle: Only the user can request an order cancellation.");
		orderCancellationRequested[_orderId] = true;
		emit OrderCancellationRequestedEvent(_orderId, _msgSender());
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

	// ----------------------------------------------------------------------------------
	// adminCancelOrder(bytes32  _orderId)
	// Administrator can cancel before the _callback has been executed to provide an updateOrder functionality
	// ----------------------------------------------------------------------------------
	function adminCancelOrder(bytes32 _orderId) public onlyRole(ORACLEOPERATOR_ROLE) {
		MorpherTradeEngine _tradeEngine = MorpherTradeEngine(state.morpherTradeEngineAddress());
		(address userId, , , , , , ) = _tradeEngine.getOrder(_orderId);
		_tradeEngine.cancelOrder(_orderId, userId);
		clearOrderConditions(_orderId);
		emit AdminOrderCancelled(_orderId, userId, _msgSender());
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
		return createdPosition;
	}

	// ----------------------------------------------------------------------------------
	// delistMarket(bytes32 _marketId)
	// Administrator closes out all existing positions on _marketId market at current prices
	// ----------------------------------------------------------------------------------

	uint delistMarketFromIx;

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
	 * Deprecated function
	 */
	function getTradeEngineFromOrderId(uint orderId) public view returns (address) {
		orderId = orderId; //mute the warning
		return state.morpherTradeEngineAddress();
	}
}
