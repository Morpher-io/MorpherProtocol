// ------------------------------------------------------------------------
// MorpherSidechainToBaseMigration
// Handles the migration of positions and balances from the plasma sidechain to Base L2
// using Merkle proofs for verification.
// ------------------------------------------------------------------------
//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.15;

import "./MorpherState.sol";
import "./MorpherUserBlocking.sol"; // Use adapted v5 interface
import "./MorpherAccessControl.sol"; // Use adapted v5 interface
// --- V5 Imports ---
import {MerkleProof} from "../lib/openzeppelin-contracts-5/contracts/utils/cryptography/MerkleProof.sol"; // Use non-upgradeable MerkleProof
import {ECDSA} from "../lib/openzeppelin-contracts-5/contracts/utils/cryptography/ECDSA.sol"; // Use non-upgradeable ECDSA
import {MessageHashUtils} from "../lib/openzeppelin-contracts-5/contracts/utils/cryptography/MessageHashUtils.sol"; // Import MessageHashUtils
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ContextUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/utils/ContextUpgradeable.sol"; // Keep for _msgSender
import "./MorpherTradeEngine.sol"; // Use adapted v5 interface
import "./MorpherToken.sol"; // Use adapted v5 interface

contract MorpherSidechainToBaseMigration is UUPSUpgradeable, ContextUpgradeable { // Update inheritance
    
    MorpherState public state;
    
    // Migration state
    bool public migrationPaused;
    
    // Merkle roots
    bytes32 public plasmaStateRoot;
    bytes32 public finalBalanceMerkleRoot;
    
    // Track migrated positions and balances to prevent double-claiming
    mapping(bytes32 => bool) public migratedPositions;
    mapping(address => bool) public migratedBalances;

    // Migration statistics
    uint256 public totalPositionsMigrated;
    uint256 public totalBalancesMigrated;
    uint256 public totalUsersMigrated;
    
    // Migration incentives
    uint256 public migrationBonus; // in basis points (e.g., 100 = 1%)
    
    // Position migration tracking
    mapping(address => uint256) public lastMigratedPositionIndex;
    mapping(address => bytes32[]) public userPositionIds;


    uint256 public totalStakesMigrated; // Added
    mapping(address => bool) public migratedStakes; // Added
    
    // Role-based access control
    bytes32 public constant ADMINISTRATOR_ROLE = keccak256("ADMINISTRATOR_ROLE");
    bytes32 public constant MIGRATION_OPERATOR_ROLE = keccak256("MIGRATION_OPERATOR_ROLE");
    
    // Events
    event MigrationPaused(bool paused);
    event PlasmaStateRootUpdated(bytes32 newRoot);
    event FinalBalanceMerkleRootSet(bytes32 newRoot);
    
    event PositionMigrated(
        address indexed user, 
        bytes32 marketId, 
        uint256 longShares, 
        uint256 shortShares,
        bytes32 positionHash
    );
    
    event PositionsBatchMigrated(
        address indexed user,
        uint256 positionCount,
        bytes32[] positionHashes
    );
    
    event StakesBatchMigrated( // Added Event
        uint256 count
    );

    event BalanceMigrated(
        address indexed user,
        uint256 amount
    );
    
    event BalanceMigratedWithTimeLock(
        address indexed user,
        uint256 amount,
        uint256 lockedAmount,
        uint256 lockedUntil
    );
    
    event DelegateMigrationAuthorized(
        address indexed user,
        address indexed delegate,
        bool authorized
    );
    
    event MigrationInitiated(address indexed user);
        
    modifier onlyRole(bytes32 role) {
        require(MorpherAccessControl(state.morpherAccessControlAddress()).hasRole(role, _msgSender()), 
                "MorpherMigration: Permission denied.");
        _;
    }
    
    modifier migrationActive() {
        require(!migrationPaused, "MorpherMigration: Migration is paused");
        _;
    }
    
    // We'll use the same modifier for all migration phases
    modifier activeMigrationPhase() {
        require(!migrationPaused, "MorpherMigration: Migration is paused");
        _;
    }
    
    modifier postActiveMigrationPhase() {
        require(!migrationPaused, "MorpherMigration: Migration is paused");
        require(finalBalanceMerkleRoot != bytes32(0), "MorpherMigration: Final balance root not set");
        _;
    }
    
    modifier userNotBlocked {
        require(!MorpherUserBlocking(state.morpherUserBlockingAddress()).userIsBlocked(_msgSender()), 
                "MorpherMigration: User is blocked");
        _;
    }

    // --- Updated Initializer ---
    function initialize(
        address _stateAddress,
        bytes32 _plasmaStateRoot,
        uint256 _migrationBonusBps
    ) public initializer {
        __UUPSUpgradeable_init(); // Initialize UUPS
        __Context_init(); // Initialize Context
        state = MorpherState(_stateAddress);
        plasmaStateRoot = _plasmaStateRoot;
        migrationBonus = _migrationBonusBps;
        migrationPaused = false;
        
        emit PlasmaStateRootUpdated(_plasmaStateRoot);
    }

    // --- Implement _authorizeUpgrade ---
	function _authorizeUpgrade(address /** unused */)
		internal
        view
		override
	{
		address accessControlAddress = state.morpherAccessControlAddress();
		require(accessControlAddress != address(0), "MorpherMigration: AccessControl not set in State");
		// Check if the sender has the PROXYUPDATER_ROLE defined in MorpherAccessControl
		require(
			MorpherAccessControl(accessControlAddress).hasRole(
				MorpherAccessControl(accessControlAddress).PROXYUPDATER_ROLE(), // Get role hash from AC
				msg.sender // Use msg.sender directly
			),
			"MorpherMigration: Caller is not the proxy updater"
		);
	}
    
    // ------------------------------------------------------------------------
    // Administrative functions
    // ------------------------------------------------------------------------
    
    function setMorpherState(address _stateAddress) public onlyRole(ADMINISTRATOR_ROLE) {
        state = MorpherState(_stateAddress);
    }
    
    function updatePlasmaStateRoot(bytes32 _newRoot) public onlyRole(MIGRATION_OPERATOR_ROLE) {
        plasmaStateRoot = _newRoot;
        emit PlasmaStateRootUpdated(_newRoot);
    }
    
    function pauseMigration(bool _paused) public onlyRole(MIGRATION_OPERATOR_ROLE) {
        migrationPaused = _paused;
        emit MigrationPaused(_paused);
    }
    
    function setFinalBalanceMerkleRoot(bytes32 _root) public onlyRole(ADMINISTRATOR_ROLE) {
        finalBalanceMerkleRoot = _root;
        emit FinalBalanceMerkleRootSet(_root);
    }
    
    // ------------------------------------------------------------------------
    // Migration functions
    // ------------------------------------------------------------------------
    
    /**
     * Initiate full migration process
     */
    function initiateFullMigration(bytes memory _signature) public userNotBlocked activeMigrationPhase {
        // Verify user's signature
        bytes32 messageHash = keccak256(abi.encodePacked(
            "I authorize migration of all my positions from plasma chain to Base L2",
            _msgSender(),
            block.chainid
        ));
        
        address signer = ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(messageHash), _signature); // Use MessageHashUtils
        require(signer == _msgSender(), "MorpherMigration: Invalid signature");
        
        // Emit event for backend to start migration process
        emit MigrationInitiated(_msgSender());
    }
    
    
    
    /**
     * Migrate token balance from plasma chain to Base L2 with time lock and locked rewards
     * Uses the finalBalanceMerkleRoot which is set after the active migration period
     */
    function migrateBalanceSelfService(
        bytes32[] memory _proof,
        uint256 _balance,
        uint256 _lockedAmount,
        uint256 _lockDuration,
        uint256 _lockedRewardAmount
    ) public userNotBlocked {
        // Verify balance hasn't been migrated already
        require(!migratedBalances[_msgSender()], "MorpherMigration: Balance already migrated");
        require(finalBalanceMerkleRoot != bytes32(0), "MorpherMigration: Final balance root not set");
        require(_lockedAmount + _lockedRewardAmount <= _balance, "MorpherMigration: Locked amounts cannot exceed total balance");
        
        // Generate balance hash including lock information
        bytes32 balanceHash = keccak256(abi.encodePacked(_msgSender(), _balance, _lockedAmount, _lockDuration, _lockedRewardAmount));
        
        // Verify Merkle proof against final balance root
        require(
            MerkleProof.verify(_proof, finalBalanceMerkleRoot, balanceHash), // Use MerkleProof
            "MorpherMigration: Invalid Merkle proof"
        );
        
        // Mark balance as migrated
        migratedBalances[_msgSender()] = true;
        
        // No bonus for self-service migration
        uint256 amountToMint = _balance;
        
        // Mint tokens to user
        MorpherToken(state.morpherTokenAddress()).mint(_msgSender(), amountToMint);
        
        // Calculate unlock time
        uint256 lockedUntil = block.timestamp + _lockDuration;
        
        // If there are tokens to be locked, lock them
        if (_lockedAmount > 0 && _lockDuration > 0) {
            MorpherToken(state.morpherTokenAddress()).lockTokensForTime(_msgSender(), _lockedAmount, _lockDuration);
        }
        
        // If there are rewards to be locked, lock them
        if (_lockedRewardAmount > 0) {
            MorpherToken(state.morpherTokenAddress()).lockRewards(_msgSender(), _lockedRewardAmount);
        }
        
        // Update statistics
        totalBalancesMigrated++;
        totalUsersMigrated++;
        
        emit BalanceMigratedWithTimeLock(_msgSender(), amountToMint, _lockedAmount, lockedUntil);
    }
    
  
    
    // Position migration struct to avoid stack too deep errors
    struct PositionMigrationData {
        bytes32 marketId;
        uint256 timeStamp;
        uint256 longShares;
        uint256 shortShares;
        uint256 meanEntryPrice;
        uint256 meanEntrySpread;
        uint256 meanEntryLeverage;
        uint256 liquidationPrice;
    }
    
    /**
     * Delegate migration of positions in batch with user authorization signature
     */
    function delegateMigratePositionsBatch(
        address _user,
        bytes memory _userAuthSignature,
        PositionMigrationData[] memory _positions
    ) public onlyRole(MIGRATION_OPERATOR_ROLE) migrationActive {
        require(_positions.length > 0, "MorpherMigration: No positions to migrate");
        
        // Verify user authorization signature
        bytes32 messageHash = keccak256(abi.encodePacked(
            "I authorize migration of all my positions from plasma chain to Base L2",
            _user,
            block.chainid
        ));
        
        address signer = ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(messageHash), _userAuthSignature); // Use MessageHashUtils
        require(signer == _user, "MorpherMigration: Invalid user authorization signature");
        
        bytes32[] memory positionHashes = new bytes32[](_positions.length);
        
        for (uint i = 0; i < _positions.length; i++) {
            PositionMigrationData memory pos = _positions[i];
            
            // Generate position hash
            bytes32 positionHash = MorpherTradeEngine(state.morpherTradeEngineAddress()).getPositionHash(
                _user, 
                pos.marketId, 
                pos.timeStamp, 
                pos.longShares, 
                pos.shortShares, 
                pos.meanEntryPrice, 
                pos.meanEntrySpread, 
                pos.meanEntryLeverage, 
                pos.liquidationPrice
            );
            
            // Verify position hasn't been migrated already
            require(!migratedPositions[positionHash], "MorpherMigration: Position already migrated");
            
            // Check if user already has a position for this market
            MorpherTradeEngine.position memory existingPosition = MorpherTradeEngine(state.morpherTradeEngineAddress()).getPosition(_user, pos.marketId);
            require(existingPosition.longShares == 0 && existingPosition.shortShares == 0, 
                    "MorpherMigration: User already has a position for this market");
            
            // Mark position as migrated
            migratedPositions[positionHash] = true;
            
            // Store position ID for sequential migration
            userPositionIds[_user].push(positionHash);
            
            // Set position in trade engine
            MorpherTradeEngine(state.morpherTradeEngineAddress()).setPosition(
                _user,
                pos.marketId,
                pos.timeStamp,
                pos.longShares,
                pos.shortShares,
                pos.meanEntryPrice,
                pos.meanEntrySpread,
                pos.meanEntryLeverage,
                pos.liquidationPrice
            );
            
            positionHashes[i] = positionHash;
        }
        
        // Update statistics
        totalPositionsMigrated += _positions.length;
        
        
        emit PositionsBatchMigrated(
            _user,
            _positions.length,
            positionHashes
        );
    }
    
    /**
     * Delegate migration of token balance with time lock and locked rewards
     */
    function delegateMigrateBalance(
        address _user,
        bytes memory _userAuthSignature,
        uint256 _balance,
        uint256 _lockedAmount,
        uint256 _lockDuration,
        uint256 _lockedRewardAmount
    ) public onlyRole(MIGRATION_OPERATOR_ROLE) migrationActive {
        // Verify user authorization signature
        bytes32 messageHash = keccak256(abi.encodePacked(
            "I authorize migration of all my positions from plasma chain to Base L2",
            _user,
            block.chainid
        ));
        
        address signer = ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(messageHash), _userAuthSignature); // Use MessageHashUtils
        require(signer == _user, "MorpherMigration: Invalid user authorization signature");
        
        // Verify balance hasn't been migrated already
        require(!migratedBalances[_user], "MorpherMigration: Balance already migrated");
        require(_lockedAmount + _lockedRewardAmount <= _balance, "MorpherMigration: Locked amounts cannot exceed total balance");
        
        // Mark balance as migrated
        migratedBalances[_user] = true;
        
        // Apply migration bonus if configured
        uint256 amountToMint = _balance;
        if (migrationBonus > 0) {
            amountToMint += (_balance * migrationBonus) / 10000;
        }
        
        // Mint tokens to user
        MorpherToken(state.morpherTokenAddress()).mint(_user, amountToMint);
        
        // Calculate unlock time
        uint256 lockedUntil = block.timestamp + _lockDuration;
        
        // If there are tokens to be locked, lock them
        if (_lockedAmount > 0 && _lockDuration > 0) {
            MorpherToken(state.morpherTokenAddress()).lockTokensForTime(_user, _lockedAmount, _lockDuration);
        }
        
        // If there are rewards to be locked, lock them
        if (_lockedRewardAmount > 0) {
            MorpherToken(state.morpherTokenAddress()).lockRewards(_user, _lockedRewardAmount);
        }
        
        // Update statistics
        totalBalancesMigrated++;
        totalUsersMigrated++;
        
        
        if (_lockedAmount > 0 && _lockDuration > 0) {
            emit BalanceMigratedWithTimeLock(_user, amountToMint, _lockedAmount, lockedUntil);
        } else {
            emit BalanceMigrated(_user, amountToMint);
        }
    }
    
    /**
     * Verify if a balance is valid for self-service migration
     * This is a view function that can be used by frontends to verify balances before migration
     */
    function verifyBalanceSelfService(
        address _user,
        bytes32[] memory _proof,
        uint256 _balance,
        uint256 _lockedAmount,
        uint256 _lockDuration,
        uint256 _lockedRewardAmount
    ) public view returns (bool) {
        require(finalBalanceMerkleRoot != bytes32(0), "MorpherMigration: Final balance root not set");
        bytes32 balanceHash = keccak256(abi.encodePacked(_user, _balance, _lockedAmount, _lockDuration, _lockedRewardAmount));
        return MerkleProof.verify(_proof, finalBalanceMerkleRoot, balanceHash); // Use MerkleProof
    }
    
    
    /**
     * @notice Delegate migration of staking data (pool shares and lockup) in batch.
     * @dev Requires MIGRATION_OPERATOR_ROLE. Only runs when migration is active.
     * @param _users Array of user addresses.
     * @param _numPoolShares Array of pool share amounts corresponding to users.
     * @param _lockedUntil Array of lockup end timestamps corresponding to users.
     */
    function delegateMigrateStakeBatch(
        address[] memory _users,
        uint256[] memory _numPoolShares,
        uint256[] memory _lockedUntil
    ) public onlyRole(MIGRATION_OPERATOR_ROLE) migrationActive {
        require(_users.length > 0, "MorpherMigration: No stakes to migrate");
        require(
            _users.length == _numPoolShares.length && _users.length == _lockedUntil.length,
            "MorpherMigration: Input array length mismatch"
        );

        address stakingContractAddress = state.morpherStakingAddress();
        require(stakingContractAddress != address(0), "MorpherMigration: Staking address not set in State");
        MorpherStaking stakingContract = MorpherStaking(stakingContractAddress);

        uint256 migratedCount = 0;
        for (uint i = 0; i < _users.length; i++) {
            address user = _users[i];
            require(user != address(0), "MorpherMigration: User address cannot be zero");
            // Verify stake hasn't been migrated already for this user
            require(!migratedStakes[user], "MorpherMigration: Stake already migrated for user");

            // Mark stake as migrated for this user
            migratedStakes[user] = true;

            // Set stake data in MorpherStaking contract
            stakingContract.setMigratedStake(user, _numPoolShares[i], _lockedUntil[i]);

            migratedCount++;
        }

        // Update statistics
        totalStakesMigrated += migratedCount;

        emit StakesBatchMigrated(migratedCount);
    }
       
       
    /**
     * Get migration statistics
     */
    function getMigrationStats() public view returns (
        uint256 _totalStakesMigrated, // Added return value
        uint256 _totalPositionsMigrated,
        uint256 _totalBalancesMigrated,
        uint256 _totalUsersMigrated,
        bool _migrationActive,
        bool _finalBalanceRootSet
    ) {
        bool active = !migrationPaused;
        bool finalRootSet = finalBalanceMerkleRoot != bytes32(0);
        
        return (
            totalStakesMigrated, // Added
            totalPositionsMigrated,
            totalBalancesMigrated,
            totalUsersMigrated,
            active,
            finalRootSet
        );
    }
}
