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
*  Website: https://morpher.com
*  Morpher Token: MPH
*  
*  
*  Trade hundreds of markets: Stocks, Crypto, Commodities, Forex and some really unique markets. 
*  Join our community of 200k+ happy traders today!
*
**/

// --- V5 Imports ---
import {ERC20Upgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PausableUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {ERC20PermitUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol"; // Use standard Permit
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/proxy/utils/UUPSUpgradeable.sol";
// Remove draft EIP712, ECDSA, Counters if only used for permit
// import {ECDSAUpgradeable} from "../lib/openzeppelin-contracts-upgradeable-5/contracts/utils/cryptography/ECDSAUpgradeable.sol";
// import {CountersUpgradeable} from "../lib/openzeppelin-contracts-upgradeable-5/contracts/utils/CountersUpgradeable.sol";
import "./MorpherAccessControl.sol"; // Use adapted v5 interface
import "./MorpherState.sol"; // Use adapted v5 interface


/// @custom:oz-upgrades-from contracts/prev/contracts/MorpherToken.sol:MorpherToken
contract MorpherToken is ERC20Upgradeable, ERC20PausableUpgradeable, ERC20PermitUpgradeable, UUPSUpgradeable { // Inherit new modules
	MorpherAccessControl public morpherAccessControl;

	bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
	bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
	bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
	bytes32 public constant ADMINISTRATOR_ROLE = keccak256("ADMINISTRATOR_ROLE");
	bytes32 public constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");
	bytes32 public constant TRANSFERBLOCKED_ROLE = keccak256("TRANSFERBLOCKED_ROLE");
	bytes32 public constant POLYGONMINTER_ROLE = keccak256("POLYGONMINTER_ROLE");
	bytes32 public constant TOKENUPDATER_ROLE = keccak256("TOKENUPDATER_ROLE");
	bytes32 public constant AIRDROPADMIN_ROLE = keccak256("AIRDROPADMIN_ROLE");

	uint256 private _totalTokensOnOtherChain;
	uint256 private _totalTokensInPositions;
	bool private _restrictTransfers;
	
	// Mapping to track locked rewards balances
	mapping(address => uint256) private _lockedRewards;
	uint256 private _totalLockedRewards;
	
	// Structure to track time-locked tokens
	struct TokenLock {
		uint256 amount;      // Amount of tokens locked
		uint256 lockedUntil; // Timestamp until which tokens are locked
	}

	
	
	event RewardsLocked(address indexed account, uint256 amount);
	event RewardsUnlocked(address indexed account, uint256 amount);
	event TokensLocked(address indexed account, uint256 amount, uint256 lockedUntil);
	event TokensUnlocked(address indexed account, uint256 amount);
	event MigrationTokensLocked(address indexed account, uint256 amount, uint256 lockedUntil);
	event DailyMintedTransferLimitUpdated(uint256 oldLimit, uint256 newLimit);
	event MintedTokensTransferred(address indexed from, address indexed to, uint256 amount);
	event TokensTransferredIn(address indexed to, uint256 amount);

	// --- Remove manual EIP712 Permit state variables ---
	// bytes32 private _HASHED_NAME;
	// bytes32 private _HASHED_VERSION;
	// bytes32 private constant _TYPE_HASH = ...;
	// using CountersUpgradeable for CountersUpgradeable.Counter; // Keep if used elsewhere
	// mapping(address => CountersUpgradeable.Counter) private _nonces; // Replaced by ERC20Permit's nonces
	// bytes32 private constant _PERMIT_TYPEHASH = ...;
	// bytes32 private _PERMIT_TYPEHASH_DEPRECATED_SLOT;

	MorpherState public morpherState;

	// Mapping to track transferred in tokens per user (tokens received from other users)
	mapping(address => uint256) private _transferredInTokens;
	
	// Mapping to track daily transfers of net minted tokens
	mapping(address => mapping(uint256 => uint256)) private _dailyMintedTransfers;
	
	// Daily transfer limit for net minted tokens
	uint256 private _dailyMintedTransferLimit;

	// Mapping to track locked tokens per user
	mapping(address => TokenLock) private _timeLocks;

	// Total amount of time-locked tokens across all users
	uint256 private _totalTimeLocked;


	event SetTotalTokensOnOtherChain(uint256 _oldValue, uint256 _newValue);
	event SetTotalTokensInPositions(uint256 _oldValue, uint256 _newValue);
	event SetRestrictTransfers(bool _oldValue, bool _newValue);

	// --- Updated Initializer ---
	function initialize(
		address _morpherAccessControlAddress,
		address _morpherStateAddress,
		string memory _permitName // Name for EIP712 Domain Separator used by ERC20Permit
	) public initializer {
		__ERC20_init("Morpher", "MPH");
		__ERC20Pausable_init();
		__UUPSUpgradeable_init();
		__ERC20Permit_init(_permitName); // Initialize ERC20Permit

		morpherAccessControl = MorpherAccessControl(_morpherAccessControlAddress);
		morpherState = MorpherState(_morpherStateAddress);
		// Remove manual hash initializations
		// _HASHED_NAME = keccak256(bytes("MorpherToken")); // Handled by ERC20Permit
		// _HASHED_VERSION = keccak256(bytes("1")); // Handled by ERC20Permit
	}

	// --- Implement _authorizeUpgrade ---
	function _authorizeUpgrade(address newImplementation)
		internal
		override
	{
		address accessControlAddress = address(morpherAccessControl);
		require(accessControlAddress != address(0), "MorpherToken: AccessControl not set");
		// Check if the sender has the PROXYUPDATER_ROLE defined in MorpherAccessControl
		require(
			MorpherAccessControl(accessControlAddress).hasRole(
				MorpherAccessControl(accessControlAddress).PROXYUPDATER_ROLE(), // Get role hash from AC
				_msgSender()
			),
			"MorpherToken: Caller is not the proxy updater"
		);
	}

	modifier onlyRole(bytes32 role) {
		require(morpherAccessControl.hasRole(role, _msgSender()), 
			string(abi.encodePacked("MorpherToken: Missing required role ", _bytes32ToString(role))));
		_;
	}
	
	/**
	 * @dev Helper function to convert bytes32 to string for error messages
	 */
	function _bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
		bytes memory bytesArray = new bytes(32);
		for (uint256 i; i < 32; i++) {
			bytesArray[i] = _bytes32[i];
		}
		return string(bytesArray);
	}

    // --- Remove manual EIP712 setters ---
    // function setHashedName(string memory _name) public onlyRole(ADMINISTRATOR_ROLE) { ... }
    // function setHashedVersion(string memory _version) public onlyRole(ADMINISTRATOR_ROLE) { ... }

	function setMorpherStateAddress(address _morpherState) public onlyRole(ADMINISTRATOR_ROLE) {
		morpherState = MorpherState(_morpherState);
	}

	// function getMorpherAccessControl() public view returns(address) {
	//     return address(morpherAccessControl);
	// }

	function setRestrictTransfers(bool restrictTransfers) public onlyRole(ADMINISTRATOR_ROLE) {
		emit SetRestrictTransfers(_restrictTransfers, restrictTransfers);
		_restrictTransfers = restrictTransfers;
	}

	function getRestrictTransfers() public view returns (bool) {
		return _restrictTransfers;
	}

	function setTotalTokensOnOtherChain(uint256 totalOnOtherChain) public onlyRole(TOKENUPDATER_ROLE) {
		emit SetTotalTokensOnOtherChain(_totalTokensInPositions, totalOnOtherChain);
		_totalTokensOnOtherChain = totalOnOtherChain;
	}

	function getTotalTokensOnOtherChain() public view returns (uint256) {
		return _totalTokensOnOtherChain;
	}

	function setTotalInPositions(uint256 totalTokensInPositions) public onlyRole(TOKENUPDATER_ROLE) {
		emit SetTotalTokensInPositions(_totalTokensInPositions, totalTokensInPositions);
		_totalTokensInPositions = totalTokensInPositions;
	}

	function getTotalTokensInPositions() public view returns (uint256) {
		return _totalTokensInPositions;
	}

	/**
	 * @dev See {IERC20-totalSupply}.
	 */
	function totalSupply() public view virtual override returns (uint256) {
		return super.totalSupply() + _totalTokensOnOtherChain + _totalTokensInPositions;
	}

	/**
	 * @dev Returns the full balance including locked rewards and time-locked tokens, used for trading
	 */
	function getTradeableBalanceOf(address account) public view returns (uint256) {
		return super.balanceOf(account);
	}

	/**
	 * @dev Override balanceOf to subtract locked rewards and time-locked tokens
	 */
	function balanceOf(address account) public view virtual override returns (uint256) {
		(uint256 timeLockedAmount, ) = getTimeLock(account);
		return super.balanceOf(account) - _lockedRewards[account] - timeLockedAmount;
	}

	function deposit(address user, bytes calldata depositData) external onlyRole(POLYGONMINTER_ROLE) {
		uint256 amount = abi.decode(depositData, (uint256));
		_mint(user, amount);
	}

	function withdraw(uint256 amount) external onlyRole(POLYGONMINTER_ROLE) {
		_burn(msg.sender, amount);
	}

	/**
	 * @dev Creates `amount` new tokens for `to`.
	 *
	 * See {ERC20-_mint}.
	 *
	 * Requirements:
	 *
	 * - the caller must have the `MINTER_ROLE`.
	 */
	function mint(address to, uint256 amount) public virtual {
		require(morpherAccessControl.hasRole(MINTER_ROLE, _msgSender()), "MorpherToken: must have minter role to mint");
		
		// Track tokens as transferred in if not from MintingLimiter or TradeEngine
		if (_msgSender() != morpherState.morpherMintingLimiterAddress() && 
		    _msgSender() != morpherState.morpherTradeEngineAddress()) {
			_transferredInTokens[to] += amount;
			emit TokensTransferredIn(to, amount);
		}
		
		_mint(to, amount);
	}

	/**
	 * @dev Burns `amount` of tokens for `from`.
	 *
	 * See {ERC20-_burn}.
	 *
	 * Requirements:
	 *
	 * - the caller must have the `BURNER_ROLE`.
	 */
	function burn(address from, uint256 amount) public virtual {
		require(morpherAccessControl.hasRole(BURNER_ROLE, _msgSender()), "MorpherToken: must have burner role to burn");
		_burn(from, amount);
	}

	/**
	 * @dev Pauses all token transfers.
	 *
	 * See {ERC20Pausable} and {Pausable-_pause}.
	 *
	 * Requirements:
	 *
	 * - the caller must have the `PAUSER_ROLE`.
	 */
	function pause() public virtual {
		require(
			morpherAccessControl.hasRole(PAUSER_ROLE, _msgSender()),
			"MorpherToken: must have pauser role to pause"
		);
		_pause();
	}

	/**
	 * @dev Unpauses all token transfers.
	 *
	 * See {ERC20Pausable} and {Pausable-_unpause}.
	 *
	 * Requirements:
	 *
	 * - the caller must have the `PAUSER_ROLE`.
	 */
	function unpause() public virtual {
		require(
			morpherAccessControl.hasRole(PAUSER_ROLE, _msgSender()),
			"MorpherToken: must have pauser role to unpause"
		);
		_unpause();
	}

	/**
	 * @dev Returns the amount of tokens that are locked as rewards for an account
	 */
	function getLockedRewards(address account) public view returns (uint256) {
		return _lockedRewards[account];
	}

	/**
	 * @dev Returns the total amount of tokens that are locked as rewards
	 */
	function getTotalLockedRewards() public view returns (uint256) {
		return _totalLockedRewards;
	}
	
	/**
	 * @dev Returns the amount of time-locked tokens for an account
	 * @param account Address to check
	 * @return amount Amount of locked tokens
	 * @return lockedUntil Timestamp until which tokens are locked
	 */
	function getTimeLock(address account) public view returns (uint256 amount, uint256 lockedUntil) {
		TokenLock memory lock = _timeLocks[account];
		
		// If lock has expired, return zeros
		if (lock.amount > 0 && block.timestamp >= lock.lockedUntil) {
			return (0, 0);
		}
		
		return (lock.amount, lock.lockedUntil);
	}

	/**
	 * @dev Returns the total amount of time-locked tokens across all users
	 */
	function getTotalTimeLocked() public view returns (uint256) {
		return _totalTimeLocked;
	}

	/**
	 * @dev Locks tokens as rewards for an account
	 * @param account Address to lock rewards for
	 * @param amount Amount of tokens to lock
	 */
	function lockRewards(address account, uint256 amount) public onlyRole(AIRDROPADMIN_ROLE) {
		require(balanceOf(account) >= _lockedRewards[account] + amount, "MorpherToken: insufficient balance for locking");
		
		_lockedRewards[account] += amount;
		_totalLockedRewards += amount;
		
		emit RewardsLocked(account, amount);
	}

	/**
	 * @dev Unlocks previously locked reward tokens for an account
	 * @param account Address to unlock rewards for
	 * @param amount Amount of tokens to unlock
	 */
	function unlockRewards(address account, uint256 amount) public onlyRole(ADMINISTRATOR_ROLE) {
		require(_lockedRewards[account] >= amount, "MorpherToken: insufficient locked rewards");
		
		_lockedRewards[account] -= amount;
		_totalLockedRewards -= amount;
		
		emit RewardsUnlocked(account, amount);
	}
	
	/**
	 * @dev Locks tokens for a specific time period
	 * @param account Address to lock tokens for
	 * @param amount Amount of tokens to lock
	 * @param lockDuration Duration in seconds for which tokens will be locked
	 */
	function lockTokensForTime(address account, uint256 amount, uint256 lockDuration) public onlyRole(ADMINISTRATOR_ROLE) {
		require(balanceOf(account) >= amount, "MorpherToken: insufficient balance for locking");
		
		uint256 unlockTime = block.timestamp + lockDuration;
		
		// If tokens are already locked, ensure we're not reducing the lock time
		if (_timeLocks[account].amount > 0) {
			require(unlockTime >= _timeLocks[account].lockedUntil, "MorpherToken: cannot reduce existing lock time");
			
			// Add to existing lock
			_timeLocks[account].amount += amount;
			_timeLocks[account].lockedUntil = unlockTime;
		} else {
			// Create new lock
			_timeLocks[account] = TokenLock(amount, unlockTime);
		}
		
		_totalTimeLocked += amount;
		
		
		emit TokensLocked(account, amount, unlockTime);
		
	}

	/**
	 * @dev Manually unlocks tokens if the lock period has expired
	 * @param account Address to unlock tokens for
	 */
	function unlockExpiredTokens(address account) public {
		TokenLock storage lock = _timeLocks[account];
		
		if (lock.amount > 0 && block.timestamp >= lock.lockedUntil) {
			uint256 amountToUnlock = lock.amount;
			_totalTimeLocked -= amountToUnlock;
			
			// Clear the lock
			lock.amount = 0;
			lock.lockedUntil = 0;
			
			emit TokensUnlocked(account, amountToUnlock);
		}
	}
	
	/**
	 * @dev Sets the daily transfer limit for minted tokens
	 * @param limit New daily transfer limit
	 */
	function setDailyMintedTransferLimit(uint256 limit) public onlyRole(ADMINISTRATOR_ROLE) {
		emit DailyMintedTransferLimitUpdated(_dailyMintedTransferLimit, limit);
		_dailyMintedTransferLimit = limit;
	}
	
	/**
	 * @dev Returns the daily transfer limit for minted tokens
	 */
	function getDailyMintedTransferLimit() public view returns (uint256) {
		return _dailyMintedTransferLimit;
	}
	
	/**
	 * @dev Returns the amount of tokens transferred in for an account
	 */
	function getTransferredInTokens(address account) public view returns (uint256) {
		return _transferredInTokens[account];
	}
	
	/**
	 * @dev Returns the amount of minted tokens transferred today for an account
	 */
	function getDailyMintedTransfers(address account) public view returns (uint256) {
		return _dailyMintedTransfers[account][block.timestamp / 1 days];
	}

	// --- Override _update instead of _beforeTokenTransfer ---
	function _update(address from, address to, uint256 amount)
		internal
		virtual
		override(ERC20Upgradeable, ERC20PausableUpgradeable) // Override both parents
	{
		// --- Custom Logic Start ---
		// This logic runs *before* the balance update and pause check from super._update

		// Transfer restriction checks (only for actual transfers, not mint/burn)
		if (from != address(0) && to != address(0)) {
			require(
				!_restrictTransfers ||
					morpherAccessControl.hasRole(TRANSFER_ROLE, _msgSender()) ||
					morpherAccessControl.hasRole(MINTER_ROLE, _msgSender()) || // Allow minters/burners? Check if needed
					morpherAccessControl.hasRole(BURNER_ROLE, _msgSender()) ||
					morpherAccessControl.hasRole(TRANSFER_ROLE, from), // Allow sender if they have TRANSFER_ROLE
				"MorpherToken: Transfer denied by restriction"
			);

			require(
				!morpherAccessControl.hasRole(TRANSFERBLOCKED_ROLE, from), // Check sender block
				"MorpherToken: Transfer for sender is blocked."
			);
			require(
				!morpherAccessControl.hasRole(TRANSFERBLOCKED_ROLE, to), // Check receiver block
				"MorpherToken: Transfer for receiver is blocked."
			);

			// Check locked rewards and time locks against the *full* balance before transfer
			(uint256 timeLockedAmount, ) = getTimeLock(from);
			require(
				super.balanceOf(from) >= _lockedRewards[from] + timeLockedAmount + amount,
				"MorpherToken: transfer amount exceeds available balance (locked)"
			);

			// Daily limit logic (only if not called by TradeEngine)
			if (_msgSender() != morpherState.morpherTradeEngineAddress()) {
				// Track tokens transferred in for the receiver
				_transferredInTokens[to] += amount;
				emit TokensTransferredIn(to, amount);

				// Apply daily limit logic to the sender
				uint256 transferAmountFromMinted = amount;

				// Use transferred-in tokens first (not subject to daily limit)
				if (_transferredInTokens[from] > 0) {
					uint256 useFromTransferredIn = transferAmountFromMinted > _transferredInTokens[from]
						? _transferredInTokens[from]
						: transferAmountFromMinted;
					_transferredInTokens[from] -= useFromTransferredIn;
					transferAmountFromMinted -= useFromTransferredIn;
				}

				// Any remaining amount comes from minted balance and is subject to daily limit
				if (transferAmountFromMinted > 0 && _dailyMintedTransferLimit > 0) {
					uint256 today = block.timestamp / 1 days;
					uint256 transferredToday = _dailyMintedTransfers[from][today];

					// Check if this transfer exceeds the daily limit
					require(
						transferredToday + transferAmountFromMinted <= _dailyMintedTransferLimit ||
							morpherAccessControl.hasRole(ADMINISTRATOR_ROLE, _msgSender()), // Admins bypass limit
						"MorpherToken: daily minted token transfer limit exceeded"
					);

					// Update the daily transfer amount
					_dailyMintedTransfers[from][today] += transferAmountFromMinted;
					emit MintedTokensTransferred(from, to, transferAmountFromMinted);
				}
			}
		}
		// --- Custom Logic End ---

		// Call the parent _update function which handles the actual balance update and pause check
		super._update(from, to, amount);
	}

	// --- Remove manual EIP712 Permit functions ---
	// function _domainSeparatorV4() ...
	// function _buildDomainSeparator(...) ...
	// function _hashTypedDataV4(...) ...
	// function _EIP712NameHash() ...
	// function _EIP712VersionHash() ...
	// function permit(...) ...
	// function nonces(...) ... // Use ERC20Permit's nonces()
	// function DOMAIN_SEPARATOR() ... // Use ERC20Permit's DOMAIN_SEPARATOR()
	// function _useNonce(...) ... // Use ERC20Permit's _useNonce()
}
