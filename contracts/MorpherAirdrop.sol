//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.20; // Update pragma if needed

// --- V5 Imports ---
// Remove OwnableUpgradeable
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ContextUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/utils/ContextUpgradeable.sol"; // Add Context for _msgSender
import "./MorpherToken.sol"; // Use adapted v5 interface
import "./MorpherAccessControl.sol"; // Import AccessControl
import "./MorpherState.sol"; // Import State to get AccessControl address

// ----------------------------------------------------------------------------------
// Holds the Airdrop Token balance on contract address
// AirdropAdmin can authorize addresses to receive airdrop.
// Users have to claim their airdrop actively or Admin initiates transfer.
// ----------------------------------------------------------------------------------

/// @custom:oz-upgrades-from contracts/prev/contracts/MorpherAirdrop.sol:MorpherAirdrop
contract MorpherAirdrop is
	UUPSUpgradeable,
	ContextUpgradeable // Remove OwnableUpgradeable, Add ContextUpgradeable
{
	// ----------------------------------------------------------------------------
	// Mappings for authorized / claimed airdrop
	// ----------------------------------------------------------------------------
	mapping(address => uint256) private airdropClaimed;
	mapping(address => uint256) private airdropAuthorized;

	uint256 public totalAirdropAuthorized;
	uint256 public totalAirdropClaimed;

	// address public airdropAdmin; // Removed - Replaced by role
	address public morpherToken;
	MorpherState public state; // Store state contract address

	// --- Define Roles (Keep AIRDROPADMIN_ROLE specific to this contract's logic) ---
	bytes32 public constant AIRDROPADMIN_ROLE = keccak256("AIRDROPADMIN_ROLE");
	// Roles below are fetched from AccessControl for consistency
	// bytes32 public constant ADMINISTRATOR_ROLE = keccak256("ADMINISTRATOR_ROLE");
	// bytes32 public constant PROXYUPDATER_ROLE = keccak256("PROXYUPDATER_ROLE");

	// ----------------------------------------------------------------------------
	// Events
	// ----------------------------------------------------------------------------
	event AirdropSent(
		address indexed _operator,
		address indexed _recipient,
		uint256 _amountClaimed,
		uint256 _amountAuthorized
	);
	event SetAirdropAuthorized(address indexed _recipient, uint256 _amountClaimed, uint256 _amountAuthorized);

	// --- Remove constructor ---
	// constructor() { ... }

	// --- Updated Initializer ---
	function initialize(
		address _stateAddress, // Add state address
		address _morpherTokenAddress
	)
		public
		// Remove _initialOwner
		initializer
	{
		__UUPSUpgradeable_init(); // Initialize UUPS
		__Context_init(); // Initialize Context
		// Remove __Ownable_init

		require(_stateAddress != address(0), "MorpherAirdrop: State address cannot be zero");
		require(_morpherTokenAddress != address(0), "MorpherAirdrop: Token address cannot be zero");

		state = MorpherState(_stateAddress); // Store state address
		morpherToken = _morpherTokenAddress; // Set directly
		// airdropAdmin role is granted in deployment script
	}

	modifier onlyRole(bytes32 role) {
		address accessControlAddress = state.morpherAccessControlAddress();
		require(accessControlAddress != address(0), "MorpherAirdrop: AccessControl not set in State");
		require(
			MorpherAccessControl(accessControlAddress).hasRole(role, _msgSender()), // Use _msgSender() from Context
			"MorpherAirdrop: Permission denied."
		);
		_;
	}

	modifier onlyAirdropAdmin() {
		// Keep specific modifier for clarity, but use the same underlying check logic
		address accessControlAddress = state.morpherAccessControlAddress();
		require(accessControlAddress != address(0), "MorpherAirdrop: AccessControl not set in State");
		require(
			MorpherAccessControl(accessControlAddress).hasRole(AIRDROPADMIN_ROLE, _msgSender()),
			"MorpherAirdrop: Caller is not an Airdrop Administrator."
		);
		_;
	}

	// --- Implement _authorizeUpgrade ---
	function _authorizeUpgrade(
		address /** newImplementation */ // Changed from internal override onlyRole(...) to internal view override
	) internal view override {
		address accessControlAddress = state.morpherAccessControlAddress();
		require(accessControlAddress != address(0), "MorpherAirdrop: AccessControl not set in State");
		// Fetch PROXYUPDATER_ROLE hash directly from the AccessControl contract
		bytes32 proxyUpdaterRole = MorpherAccessControl(accessControlAddress).PROXYUPDATER_ROLE();
		require(
			MorpherAccessControl(accessControlAddress).hasRole(proxyUpdaterRole, _msgSender()),
			"MorpherAirdrop: Caller is not the proxy updater"
		);
	}

	// ----------------------------------------------------------------------------
	// Administrative functions
	// ----------------------------------------------------------------------------
	// function setAirdropAdmin(address _address) public onlyOwner { // Removed - Roles managed externally
	//     airdropAdmin = _address;
	// }

	function setMorpherStateAddress(address _stateAddress) public onlyRole(keccak256("ADMINISTRATOR_ROLE")) {
		// Use ADMINISTRATOR_ROLE
		require(_stateAddress != address(0), "MorpherAirdrop: State address cannot be zero");
		state = MorpherState(_stateAddress);
		// Consider emitting an event
	}

	function setMorpherTokenAddress(address _address) public onlyRole(keccak256("ADMINISTRATOR_ROLE")) {
		// Use ADMINISTRATOR_ROLE
		require(_address != address(0), "MorpherAirdrop: Token address cannot be zero");
		morpherToken = _address;
		// Consider emitting an event
	}

	// ----------------------------------------------------------------------------
	// Get airdrop amount authorized for or claimed by address
	// ----------------------------------------------------------------------------
	function getAirdropClaimed(address _userAddress) public view returns (uint256 _amount) {
		return airdropClaimed[_userAddress];
	}

	function getAirdropAuthorized(address _userAddress) public view returns (uint256 _balance) {
		return airdropAuthorized[_userAddress];
	}

	function getAirdrop(address _userAddress) public view returns (uint256 _claimed, uint256 _authorized) {
		return (airdropClaimed[_userAddress], airdropAuthorized[_userAddress]);
	}

	// ----------------------------------------------------------------------------
	// Airdrop Administrator can authorize airdrop amount per address
	// ----------------------------------------------------------------------------
	function setAirdropAuthorized(address _userAddress, uint256 _authorized) public onlyAirdropAdmin {
		// Can only set authorized amount to be higher than claimed
		require(
			_authorized >= airdropClaimed[_userAddress],
			"MorpherAirdrop: airdrop authorized must be larger than claimed."
		);
		// Authorized amount can be higher or lower than previously authorized amount, adjust accordingly
		totalAirdropAuthorized = totalAirdropAuthorized - getAirdropAuthorized(_userAddress) + _authorized;
		airdropAuthorized[_userAddress] = _authorized;
		emit SetAirdropAuthorized(_userAddress, airdropClaimed[_userAddress], _authorized);
	}

	// ----------------------------------------------------------------------------
	// User claims their entire airdrop
	// ----------------------------------------------------------------------------
	function claimAirdrop() public {
		uint256 _amount = airdropAuthorized[msg.sender] - airdropClaimed[msg.sender];
		_sendAirdrop(msg.sender, _amount);
	}

	// ----------------------------------------------------------------------------
	// User claims part of their airdrop
	// ----------------------------------------------------------------------------
	function claimSomeAirdrop(uint256 _amount) public {
		_sendAirdrop(msg.sender, _amount);
	}

	// ----------------------------------------------------------------------------
	// Administrator sends user their entire airdrop
	// ----------------------------------------------------------------------------
	function adminSendAirdrop(address _recipient) public onlyAirdropAdmin {
		uint256 _amount = airdropAuthorized[_recipient] - airdropClaimed[_recipient];
		_sendAirdrop(_recipient, _amount);
	}

	// ----------------------------------------------------------------------------
	// Administrator sends user part of their airdrop
	// ----------------------------------------------------------------------------
	function adminSendSomeAirdrop(address _recipient, uint256 _amount) public onlyAirdropAdmin {
		_sendAirdrop(_recipient, _amount);
	}

	// ----------------------------------------------------------------------------
	// Administrator sends user entire airdrop
	// ----------------------------------------------------------------------------
	function _sendAirdrop(address _recipient, uint256 _amount) private {
		require(
			airdropAuthorized[_recipient] >= airdropClaimed[_recipient] + _amount,
			"MorpherAirdrop: amount exceeds authorized airdrop amount."
		);
		airdropClaimed[_recipient] = airdropClaimed[_recipient] + _amount;
		totalAirdropClaimed = totalAirdropClaimed + _amount;
		MorpherToken(morpherToken).transfer(_recipient, _amount);
		emit AirdropSent(msg.sender, _recipient, airdropClaimed[_recipient], airdropAuthorized[_recipient]);
	}

	// ----------------------------------------------------------------------------
	// Administrator sends user part of their airdrop
	// ----------------------------------------------------------------------------
	function adminAuthorizeAndSend(address _recipient, uint256 _amount) public onlyAirdropAdmin {
		setAirdropAuthorized(_recipient, getAirdropAuthorized(_recipient) + _amount);
		_sendAirdrop(_recipient, _amount);
	}

	/**
	 * @dev Sends tokens as locked rewards to a recipient
	 * @param _recipient Address to receive the rewards
	 * @param _amount Amount of tokens to send as rewards
	 */
	function adminSendLockedRewards(address _recipient, uint256 _amount) public onlyAirdropAdmin {
		require(_amount > 0, "MorpherAirdrop: amount must be greater than 0");

		// First transfer the tokens
		MorpherToken(morpherToken).transfer(_recipient, _amount);

		// Then lock them as rewards
		MorpherToken(morpherToken).lockRewards(_recipient, _amount);

		emit AirdropSent(msg.sender, _recipient, _amount, _amount);
	}

	// ------------------------------------------------------------------------
	// Don't accept ETH
	// ------------------------------------------------------------------------
	fallback() external payable {
		revert("MorpherAirdrop: you can't deposit Ether here");
	}
	receive() external payable {
		revert("MorpherAirdrop: you can't deposit Ether here");
	}
}
