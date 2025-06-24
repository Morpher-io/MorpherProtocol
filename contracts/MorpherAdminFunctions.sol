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
*
*  Join the trading revolution today! Open your first position at https://www.morpher.com
*  
**/

// import "./MorpherTradeEngine.sol"; // Replaced with interface
// import "./MorpherState.sol";       // Replaced with interface
import "./interfaces/IMorpherState.sol"; // New interface
import "./interfaces/IMorpherTradeEngine.sol"; // New interface
import "./MorpherAccessControl.sol"; // Use adapted v5 interface

// --- V5 Imports ---
// import "../lib/openzeppelin-contracts-upgradeable-5/contracts/utils/cryptography/MerkleProofUpgradeable.sol"; // MerkleProof not used? Remove if unused.
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ContextUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/utils/ContextUpgradeable.sol"; // Keep for _msgSender override


// ----------------------------------------------------------------------------------
// Morpher Oracle contract v 2.0
// The oracle initates a new trade by calling trade engine and requesting a new orderId.
// An event is fired by the contract notifying the oracle operator to query a price/liquidation unchecked
// for a market/user and return the information via the callback function. Since calling
// the callback function requires gas, the user must send a fixed amount of Ether when
// creating their order.
// ----------------------------------------------------------------------------------

contract MorpherAdminFunctions is UUPSUpgradeable, ContextUpgradeable { // Update inheritance
	IMorpherState public state; // read only, Oracle doesn't need writing access to state

	
	/**
	 * ROLES KNOWN TO ORACLE
	 */
	bytes32 public constant ADMINISTRATOR_ROLE = keccak256("ADMINISTRATOR_ROLE");
	bytes32 public constant ORACLEOPERATOR_ROLE = keccak256("ORACLEOPERATOR_ROLE"); //used for callbacks from API
	bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE"); //can pause oracle

	uint delistMarketFromIx;

	

	event AdminOrderCancelled(bytes32 indexed _orderId, address indexed _sender, address indexed _oracleAddress);


	event LinkMorpherState(address _address);


	event AdminLiquidationOrderCreated(
		bytes32 indexed _orderId,
		address indexed _address,
		bytes32 indexed _marketId,
		uint256 _closeSharesAmount,
		uint256 _openMPHTokenAmount,
		bool _tradeDirection,
		uint256 _orderLeverage
	);


	event DelistMarketIncomplete(bytes32 _marketId, uint256 _processedUntilIndex);
	event DelistMarketComplete(bytes32 _marketId);
	event AddressPositionMigrationComplete(address _owner, bytes32 _oldMarketId, bytes32 _newMarketId);
	event AllPositionMigrationsComplete(bytes32 _oldMarketId, bytes32 _newMarketId);
	event AllPositionMigrationIncomplete(bytes32 _oldMarketId, bytes32 _newMarketId, uint _maxIx);
	

	modifier onlyRole(bytes32 role) {
		require( // Keep using _msgSender()
			MorpherAccessControl(state.morpherAccessControlAddress()).hasRole(role, _msgSender()),
			"MorpherOracle: Permission denied."
		);
		_;
	}

	// --- Updated Initializer ---
	function initialize(
		address _morpherState
	) public initializer {
		__UUPSUpgradeable_init();
		__Context_init(); // Initialize Context

		state = IMorpherState(_morpherState);
	}

	// --- Implement _authorizeUpgrade ---
	function _authorizeUpgrade(address /** unused */)
		internal
		view
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
		state = IMorpherState(_address);
		emit LinkMorpherState(_address);
	}

	

	// contract size too large, will move to an admin contract.
	// // ----------------------------------------------------------------------------------
	// // delistMarket(bytes32 _marketId)
	// // Administrator closes out all existing positions on _marketId market at current prices
	// // ----------------------------------------------------------------------------------

	function delistMarket(bytes32 _marketId, bool _startFromScratch) public onlyRole(ADMINISTRATOR_ROLE) {
		require(state.getMarketActive(_marketId) == true, "Market must be active to process position liquidations.");
		// If no _fromIx and _toIx specified, do entire _list
		if (_startFromScratch) {
			delistMarketFromIx = 0;
		}

		uint _toIx = IMorpherTradeEngine(state.morpherTradeEngineAddress()).getMaxMappingIndex(_marketId);

		address _address;
		for (uint256 i = delistMarketFromIx; i <= _toIx; i++) {
			if (gasleft() < 250000 && i != _toIx) {
				//stop if there's not enough gas to write the next transaction
				delistMarketFromIx = i;
				emit DelistMarketIncomplete(_marketId, _toIx);
				return;
			}

			_address = IMorpherTradeEngine(state.morpherTradeEngineAddress()).getExposureMappingAddress(_marketId, i);
			adminLiquidationOrder(_address, _marketId);
		}
		emit DelistMarketComplete(_marketId);
	}

	// // ----------------------------------------------------------------------------------
	// // adminLiquidationOrder(address _address, bytes32 _marketId)
	// // Administrator closes out an existing position of _address on _marketId market at current price
	// // ----------------------------------------------------------------------------------
	function adminLiquidationOrder(
		address _address,
		bytes32 _marketId
	) public onlyRole(ADMINISTRATOR_ROLE) returns (bytes32 _orderId) {
		IMorpherTradeEngine.position memory position = IMorpherTradeEngine(state.morpherTradeEngineAddress()).getPosition(
			_address,
			_marketId
		);

		if (position.longShares > 0) {
			_orderId = IMorpherTradeEngine(state.morpherTradeEngineAddress()).requestOrderId(
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
			_orderId = IMorpherTradeEngine(state.morpherTradeEngineAddress()).requestOrderId(
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



	// ----------------------------------------------------------------------------------
	// migratePositionsToNewMarket(bytes32 _oldMarketId, bytes32 _newMarketId)
	// Administrator migrates all positions from an old (deactivated) market to a new one.
	// ----------------------------------------------------------------------------------
	function migratePositionsToNewMarket(bytes32 _oldMarketId, bytes32 _newMarketId) public onlyRole(ADMINISTRATOR_ROLE) {
		require(state.getMarketActive(_oldMarketId) == false, "MorpherOracle: Old market must be deactivated for migration.");
		require(state.getMarketActive(_newMarketId) == false, "MorpherOracle: New market must be deactivated for migration.");

		IMorpherTradeEngine tradeEngine = IMorpherTradeEngine(state.morpherTradeEngineAddress());
		uint256 maxMarketAddressIndex = tradeEngine.getMaxMappingIndex(_oldMarketId);

		// Create a temporary array to store addresses to avoid issues with index changes during deletion
		address[] memory addressesToMigrate = new address[](maxMarketAddressIndex);
		uint validAddressCount = 0;
		for (uint256 i = 1; i <= maxMarketAddressIndex; i++) {
			address addr = tradeEngine.getExposureMappingAddress(_oldMarketId, i);
			if (addr != address(0)) { // Check if address is valid
				addressesToMigrate[validAddressCount] = addr;
				validAddressCount++;
			}
		}

		// Iterate through the collected valid addresses
		for (uint256 i = 0; i < validAddressCount; i++) {
			address _address = addressesToMigrate[i];
			IMorpherTradeEngine.position memory position = tradeEngine.getPosition(_address, _oldMarketId);

			if (position.longShares > 0 || position.shortShares > 0) {
				// Create a new position for the new market with the same parameters
				tradeEngine.setPosition(
					_address,
					_newMarketId,
					block.timestamp, // Use current timestamp for the new position
					position.longShares,
					position.shortShares,
					position.meanEntryPrice,
					position.meanEntrySpread,
					position.meanEntryLeverage,
					position.liquidationPrice
				);
				// Delete the old position by setting shares to zero
				tradeEngine.setPosition(_address, _oldMarketId, block.timestamp, 0, 0, 0, 0, 0, 0);
				emit AddressPositionMigrationComplete(_address, _oldMarketId, _newMarketId);
			}

			// Check gas before potentially starting the next iteration's complex operations
			if (gasleft() < 500000 && (i + 1) < validAddressCount) {
				//stop if there's not enough gas to write the next transaction
				emit AllPositionMigrationIncomplete(_oldMarketId, _newMarketId, i); // Emit index processed so far
				return; // Exit early
			}
		}

		emit AllPositionMigrationsComplete(_oldMarketId, _newMarketId);
	}
}
