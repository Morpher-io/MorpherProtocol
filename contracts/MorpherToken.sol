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
	bytes32 public constant UNRESTRICTEDTRANSFER_ROLE = keccak256("UNRESTRICTEDTRANSFER_ROLE");

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
	event MonthlyMintedTransferLimitUpdated(uint256 oldLimit, uint256 newLimit);
	event YearlyMintedTransferLimitUpdated(uint256 oldLimit, uint256 newLimit);
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

	// Total amount of time-locked tokens across all users (Removed but left here for proxy updates)
	uint256 private _totalTimeLocked;

	// Mapping to track monthly transfers of net minted tokens
	mapping(address => mapping(uint256 => uint256)) private _monthlyMintedTransfers;
	// Monthly transfer limit for net minted tokens
	uint256 private _monthlyMintedTransferLimit;

	// Mapping to track yearly transfers of net minted tokens
	mapping(address => mapping(uint256 => uint256)) private _yearlyMintedTransfers;
	// Yearly transfer limit for net minted tokens
	uint256 private _yearlyMintedTransferLimit;


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
	function _authorizeUpgrade(address /** unused */)
		internal
		view
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
		require(morpherAccessControl.hasRole(role, _msgSender()), "MorpherToken: Missing required role.");
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


	function setRestrictTransfers(bool restrictTransfers) public onlyRole(ADMINISTRATOR_ROLE) {
		emit SetRestrictTransfers(_restrictTransfers, restrictTransfers);
		_restrictTransfers = restrictTransfers;
	}

	function getRestrictTransfers() public view returns (bool) {
		return _restrictTransfers;
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
		return super.totalSupply() + _totalTokensInPositions;
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
		if((timeLockedAmount + _lockedRewards[account]) > super.balanceOf(account)) {
			return 0; //fix underflow error
		}
		return super.balanceOf(account) - _lockedRewards[account] - timeLockedAmount;
	}

	// function deposit(address user, bytes calldata depositData) external onlyRole(POLYGONMINTER_ROLE) {
	// 	uint256 amount = abi.decode(depositData, (uint256));
	// 	_mint(user, amount);
	// }

	// function withdraw(uint256 amount) external onlyRole(POLYGONMINTER_ROLE) {
	// 	_burn(msg.sender, amount);
	// }

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
		
		// Track tokens as transferred in if not from MintingLimiter, TradeEngine, MigrationContract, or StakingContract
		if (_msgSender() != morpherState.morpherMintingLimiterAddress() &&
		    _msgSender() != morpherState.morpherTradeEngineAddress() &&
			_msgSender() != morpherState.morpherSidechainToBaseMigrationAddress() &&
			_msgSender() != morpherState.morpherStakingAddress()) {
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
	 * @dev Destroys `amount` tokens from the caller.
	 *
	 * See {ERC20-_burn}.
	 *
	 * Requirements:
	 *
	 * - the caller must have the `BURNER_ROLE`.
	 */
	function burn(uint256 amount) public virtual {
		// require(morpherAccessControl.hasRole(BURNER_ROLE, _msgSender()), "MorpherToken: must have burner role to burn");
		_burn(_msgSender(), amount);
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

	// Removed getTotalTimeLocked function

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
	function lockTokensForTime(address account, uint256 amount, uint256 lockDuration) public onlyRole(AIRDROPADMIN_ROLE) {
		// require(balanceOf(account) >= amount, "MorpherToken: insufficient balance for locking"); //we should be able to set the timelock 
		
		uint256 unlockTime = block.timestamp + lockDuration;
		
		// If tokens are already locked and the lock is still active, add to it
		if (_timeLocks[account].amount > 0 && block.timestamp < _timeLocks[account].lockedUntil) {
			require(unlockTime >= _timeLocks[account].lockedUntil, "MorpherToken: cannot reduce existing lock time");
			
			// Add to existing lock
			_timeLocks[account].amount += amount;
			_timeLocks[account].lockedUntil = unlockTime;
		} else {
			// Create a new lock (this will also overwrite an expired lock)
			_timeLocks[account] = TokenLock(amount, unlockTime);
		}

		// _totalTimeLocked += amount; // Removed update


		emit TokensLocked(account, amount, unlockTime);

	}

	// Removed unlockExpiredTokens function

	/**
	 * @dev Sets the daily transfer limit for minted tokens
	 * @param limit New daily transfer limit
	 */
	function setDailyMintedTransferLimit(uint256 limit) public onlyRole(ADMINISTRATOR_ROLE) {
		emit DailyMintedTransferLimitUpdated(_dailyMintedTransferLimit, limit);
		_dailyMintedTransferLimit = limit;
	}

	/**
	 * @dev Sets the monthly transfer limit for minted tokens
	 * @param limit New monthly transfer limit
	 */
	function setMonthlyMintedTransferLimit(uint256 limit) public onlyRole(ADMINISTRATOR_ROLE) {
		emit MonthlyMintedTransferLimitUpdated(_monthlyMintedTransferLimit, limit);
		_monthlyMintedTransferLimit = limit;
	}

	/**
	 * @dev Sets the yearly transfer limit for minted tokens
	 * @param limit New yearly transfer limit
	 */
	function setYearlyMintedTransferLimit(uint256 limit) public onlyRole(ADMINISTRATOR_ROLE) {
		emit YearlyMintedTransferLimitUpdated(_yearlyMintedTransferLimit, limit);
		_yearlyMintedTransferLimit = limit;
	}
	
	/**
	 * @dev Returns the daily transfer limit for minted tokens
	 */
	function getDailyMintedTransferLimit() public view returns (uint256) {
		return _dailyMintedTransferLimit;
	}

	/**
	 * @dev Returns the monthly transfer limit for minted tokens
	 */
	function getMonthlyMintedTransferLimit() public view returns (uint256) {
		return _monthlyMintedTransferLimit;
	}

	/**
	 * @dev Returns the yearly transfer limit for minted tokens
	 */
	function getYearlyMintedTransferLimit() public view returns (uint256) {
		return _yearlyMintedTransferLimit;
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

	/**
	 * @dev Returns the amount of minted tokens transferred this month for an account
	 */
	function getMonthlyMintedTransfers(address account) public view returns (uint256) {
		return _monthlyMintedTransfers[account][block.timestamp / 30 days];
	}

	/**
	 * @dev Returns the amount of minted tokens transferred this year for an account
	 */
	function getYearlyMintedTransfers(address account) public view returns (uint256) {
		return _yearlyMintedTransfers[account][block.timestamp / 365 days];
	}

	/**
	 * @dev Calculates the total amount of tokens an account can transfer out *today*.
	 * This considers the available balance (excluding locked rewards/time-locks),
	 * the freely transferable 'transferred-in' tokens, and the daily limit
	 * applied to the remaining 'minted' tokens.
	 * @param account The address of the account to query.
	 * @return The total amount of tokens transferable today.
	 */
	function getTransferableBalanceToday(address account) public view returns (uint256) {
		// 1. Get available balance (already excludes locked rewards and time-locks)
		uint256 availableBalance = balanceOf(account);

		// 2. Get freely transferable 'transferred-in' tokens
		uint256 transferredIn = _transferredInTokens[account];

		// 3. Calculate remaining daily limit for minted tokens
		uint256 transferredToday = _dailyMintedTransfers[account][block.timestamp / 1 days];
		uint256 remainingDailyLimit = 0;
		if (_dailyMintedTransferLimit > transferredToday) {
			remainingDailyLimit = _dailyMintedTransferLimit - transferredToday;
		}

		uint256 transferredThisMonth = _monthlyMintedTransfers[account][block.timestamp / 30 days];
		uint256 remainingMonthlyLimit = 0;
		if (_monthlyMintedTransferLimit > transferredThisMonth) {
			remainingMonthlyLimit = _monthlyMintedTransferLimit - transferredThisMonth;
		}

		uint256 transferredThisYear = _yearlyMintedTransfers[account][block.timestamp / 365 days];
		uint256 remainingYearlyLimit = 0;
		if (_yearlyMintedTransferLimit > transferredThisYear) {
			remainingYearlyLimit = _yearlyMintedTransferLimit - transferredThisYear;
		}

		// 4. Calculate the portion of available balance that is 'minted'
		uint256 availableMinted = 0;
		if (availableBalance > transferredIn) {
			availableMinted = availableBalance - transferredIn;
		}

		// 5. Determine the amount transferable from the 'minted' bucket today
		// It's the minimum of what's available in the minted bucket and the remaining daily, monthly, and yearly limits
		uint256 transferableMintedToday = availableMinted;
		transferableMintedToday = transferableMintedToday < remainingDailyLimit ? transferableMintedToday : remainingDailyLimit;
		transferableMintedToday = transferableMintedToday < remainingMonthlyLimit ? transferableMintedToday : remainingMonthlyLimit;
		transferableMintedToday = transferableMintedToday < remainingYearlyLimit ? transferableMintedToday : remainingYearlyLimit;


		// 6. Determine the amount transferable from the 'transferred-in' bucket
		// It's the minimum of what's available in the bucket and the overall available balance
		uint256 transferableFromTransferredIn = availableBalance < transferredIn ? availableBalance : transferredIn; // Equivalent to min(availableBalance, transferredIn)

		// 7. Total transferable is the sum of transferable amounts from both buckets
		return transferableFromTransferredIn + transferableMintedToday;
	}


	// --- Override _update instead of _beforeTokenTransfer ---
	function _update(address from, address to, uint256 amount)
		internal
		virtual
		override(ERC20Upgradeable, ERC20PausableUpgradeable) // Override both parents
	{
		// --- Custom Logic Start ---
		// This logic runs *before* the balance update and pause check from super._update

		bool isActualTransfer = from != address(0) && to != address(0);
		// A user-initiated burn is when 'to' is address(0), 'from' is not address(0),
		// and the initiator (_msgSender()) is not the MorpherTradeEngine.
		bool isUserInitiatedBurn = to == address(0) && from != address(0) && _msgSender() != morpherState.morpherTradeEngineAddress();

		// Apply custom logic for actual transfers OR for user-initiated burns.
		if (isActualTransfer || isUserInitiatedBurn) {
			// Generic transfer/operation restriction checks
			require(
				!_restrictTransfers ||
					morpherAccessControl.hasRole(TRANSFER_ROLE, _msgSender()) ||
					morpherAccessControl.hasRole(MINTER_ROLE, _msgSender()) ||
					morpherAccessControl.hasRole(BURNER_ROLE, _msgSender()) ||
					morpherAccessControl.hasRole(TRANSFER_ROLE, from),
				"MorpherToken: Operation denied by restriction" // Generalized message
			);

			require(
				!morpherAccessControl.hasRole(TRANSFERBLOCKED_ROLE, from), // Check sender block
				"MorpherToken: Operation for sender is blocked." // Generalized message
			);

			if (isActualTransfer) { // Receiver block check only applies to actual transfers
				require(
					!morpherAccessControl.hasRole(TRANSFERBLOCKED_ROLE, to), // Check receiver block
					"MorpherToken: Transfer for receiver is blocked."
				);
			}

			// Check locked rewards and time locks against the *full* balance before the operation
			(uint256 timeLockedAmount, ) = getTimeLock(from);
			require(
				super.balanceOf(from) >= _lockedRewards[from] + timeLockedAmount + amount,
				"MorpherToken: operation amount exceeds available balance (locked)" // Generalized message
			);

			// Daily limit logic (applies if not called by TradeEngine for transfers, and for user-initiated burns)
			// The isUserInitiatedBurn flag already ensures _msgSender() != morpherState.morpherTradeEngineAddress() for burns.
			// For actual transfers, the _msgSender() check exempts the TradeEngine.
			if (_msgSender() != morpherState.morpherTradeEngineAddress()) {
				// If it's an actual transfer, track tokens transferred in for the receiver
				if (isActualTransfer) {
					_transferredInTokens[to] += amount;
					emit TokensTransferredIn(to, amount);
				}

				// Apply transfer limit logic to the sender (applies to 'from' for both transfers and user-initiated burns)
				uint256 amountSubjectToLimits = amount;

				// Use transferred-in tokens first (not subject to limits)
				if (_transferredInTokens[from] > 0) {
					uint256 useFromTransferredIn = amountSubjectToLimits > _transferredInTokens[from]
						? _transferredInTokens[from]
						: amountSubjectToLimits;
					_transferredInTokens[from] -= useFromTransferredIn;
					amountSubjectToLimits -= useFromTransferredIn;
				}

				// Any remaining amount comes from minted balance and is subject to daily, monthly, and yearly limits
				if (amountSubjectToLimits > 0) {
					uint256 today = block.timestamp / 1 days;
					uint256 currentMonth = block.timestamp / 30 days;
					uint256 currentYear = block.timestamp / 365 days;

					bool isAdminOrUnrestricted = morpherAccessControl.hasRole(ADMINISTRATOR_ROLE, _msgSender()) ||
												 morpherAccessControl.hasRole(UNRESTRICTEDTRANSFER_ROLE, _msgSender());

					// Check if this operation exceeds any of the limits for minted tokens
					if (_dailyMintedTransferLimit > 0) {
						require(
							_dailyMintedTransfers[from][today] + amountSubjectToLimits <= _dailyMintedTransferLimit || isAdminOrUnrestricted,
							"MorpherToken: daily minted token operation limit exceeded"
						);
					}
					if (_monthlyMintedTransferLimit > 0) {
						require(
							_monthlyMintedTransfers[from][currentMonth] + amountSubjectToLimits <= _monthlyMintedTransferLimit || isAdminOrUnrestricted,
							"MorpherToken: monthly minted token operation limit exceeded"
						);
					}
					if (_yearlyMintedTransferLimit > 0) {
						require(
							_yearlyMintedTransfers[from][currentYear] + amountSubjectToLimits <= _yearlyMintedTransferLimit || isAdminOrUnrestricted,
							"MorpherToken: yearly minted token operation limit exceeded"
						);
					}

					// Update the transfer/operation amounts from minted supply
					_dailyMintedTransfers[from][today] += amountSubjectToLimits;
					_monthlyMintedTransfers[from][currentMonth] += amountSubjectToLimits;
					_yearlyMintedTransfers[from][currentYear] += amountSubjectToLimits;
					
					// For burns, 'to' will be address(0). This event logs the portion of the operation
					// that came from the "minted" bucket and was subject to the limits.
					emit MintedTokensTransferred(from, to, amountSubjectToLimits);
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
