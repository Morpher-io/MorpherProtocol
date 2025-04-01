//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.20; // Update pragma if needed

// --- V5 Imports ---
import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/proxy/utils/UUPSUpgradeable.sol";
// Remove Initializable
import "./MorpherToken.sol"; // Use adapted v5 interface

// ----------------------------------------------------------------------------------
// Holds the Airdrop Token balance on contract address
// AirdropAdmin can authorize addresses to receive airdrop.
// Users have to claim their airdrop actively or Admin initiates transfer.
// ----------------------------------------------------------------------------------

/// @custom:oz-upgrades-from contracts/prev/contracts/MorpherAirdrop.sol:MorpherAirdrop
contract MorpherAirdrop is UUPSUpgradeable, OwnableUpgradeable { // Update inheritance


// ----------------------------------------------------------------------------
// Mappings for authorized / claimed airdrop
// ----------------------------------------------------------------------------
    mapping(address => uint256) private airdropClaimed;
    mapping(address => uint256) private airdropAuthorized;

    uint256 public totalAirdropAuthorized;
    uint256 public totalAirdropClaimed;

    address public airdropAdmin;
    address public morpherToken;

// ----------------------------------------------------------------------------
// Events
// ----------------------------------------------------------------------------
    event AirdropSent(address indexed _operator, address indexed _recipient, uint256 _amountClaimed, uint256 _amountAuthorized);
    event SetAirdropAuthorized(address indexed _recipient, uint256 _amountClaimed, uint256 _amountAuthorized);

    // --- Remove constructor ---
    // constructor() { ... }

    // --- Updated Initializer ---
    function initialize(
        address _airdropAdminAddress,
        address _morpherTokenAddress,
        address _initialOwner // The address that will own this contract initially
    ) public initializer {
        __UUPSUpgradeable_init(); // Initialize UUPS
        __Ownable_init(_initialOwner); // Initialize Ownable with the initial owner

        airdropAdmin = _airdropAdminAddress; // Set directly
        morpherToken = _morpherTokenAddress; // Set directly
        // transferOwnership is handled by __Ownable_init
    }

    modifier onlyAirdropAdmin {
        require(msg.sender == airdropAdmin, "MorpherAirdrop: can only be called by Airdrop Administrator.");
        _;
    }

    // --- Implement _authorizeUpgrade ---
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner // Only the owner (cold storage) can upgrade
    {}

// ----------------------------------------------------------------------------
// Administrative functions
// ----------------------------------------------------------------------------
    function setAirdropAdmin(address _address) public onlyOwner {
        airdropAdmin = _address;
    }

    function setMorpherTokenAddress(address _address) public onlyOwner {
        morpherToken = _address;
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

    function getAirdrop(address _userAddress) public view returns(uint256 _claimed, uint256 _authorized) {
        return (airdropClaimed[_userAddress], airdropAuthorized[_userAddress]);
    }

// ----------------------------------------------------------------------------
// Airdrop Administrator can authorize airdrop amount per address
// ----------------------------------------------------------------------------
    function setAirdropAuthorized(address _userAddress, uint256 _authorized) public onlyAirdropAdmin {
        // Can only set authorized amount to be higher than claimed
        require(_authorized >= airdropClaimed[_userAddress], "MorpherAirdrop: airdrop authorized must be larger than claimed.");
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
        require(airdropAuthorized[_recipient] >= airdropClaimed[_recipient] + _amount, "MorpherAirdrop: amount exceeds authorized airdrop amount.");
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
