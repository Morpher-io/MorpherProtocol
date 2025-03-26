// ------------------------------------------------------------------------
// MorpherMigration
// Handles the migration of positions and balances from the plasma sidechain to Base L2
// using Merkle proofs for verification.
// ------------------------------------------------------------------------
//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.15;

import "./MorpherState.sol";
import "./MorpherUserBlocking.sol";
import "./MorpherAccessControl.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/MerkleProofUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import "./MorpherTradeEngine.sol";

contract MorpherMigration is Initializable, ContextUpgradeable {
    
    MorpherState state;
    
    // Migration window parameters
    uint256 public migrationStartTime;
    uint256 public migrationEndTime;
    bool public migrationPaused;
    
    // Merkle root of the final state of the plasma chain
    bytes32 public plasmaStateRoot;
    
    // Track migrated positions and balances to prevent double-claiming
    mapping(bytes32 => bool) public migratedPositions;
    mapping(address => bool) public migratedBalances;
    
    // Migration statistics
    uint256 public totalPositionsMigrated;
    uint256 public totalBalancesMigrated;
    uint256 public totalUsersMigrated;
    
    // Early migration incentives
    uint256 public earlyMigrationEndTime;
    uint256 public earlyMigrationBonus; // in basis points (e.g., 100 = 1%)
    
    // Role-based access control
    bytes32 public constant ADMINISTRATOR_ROLE = keccak256("ADMINISTRATOR_ROLE");
    bytes32 public constant MIGRATION_OPERATOR_ROLE = keccak256("MIGRATION_OPERATOR_ROLE");
    
    // Events
    event MigrationStarted(uint256 startTime, uint256 endTime);
    event MigrationPaused(bool paused);
    event MigrationWindowExtended(uint256 newEndTime);
    event PlasmaStateRootUpdated(bytes32 newRoot);
    
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
    
    event BalanceMigrated(
        address indexed user,
        uint256 amount
    );
    
    event DelegateMigrationAuthorized(
        address indexed user,
        address indexed delegate,
        bool authorized
    );
    
    // Delegate migration authorization
    mapping(address => mapping(address => bool)) public delegateMigrationAuthorized;
    
    modifier onlyRole(bytes32 role) {
        require(MorpherAccessControl(state.morpherAccessControlAddress()).hasRole(role, _msgSender()), 
                "MorpherMigration: Permission denied.");
        _;
    }
    
    modifier migrationActive() {
        require(block.timestamp >= migrationStartTime, "MorpherMigration: Migration has not started yet");
        require(block.timestamp <= migrationEndTime, "MorpherMigration: Migration period has ended");
        require(!migrationPaused, "MorpherMigration: Migration is paused");
        _;
    }
    
    modifier userNotBlocked {
        require(!MorpherUserBlocking(state.morpherUserBlockingAddress()).userIsBlocked(_msgSender()), 
                "MorpherMigration: User is blocked");
        _;
    }
    
    function initialize(
        address _stateAddress,
        bytes32 _plasmaStateRoot,
        uint256 _migrationDurationDays,
        uint256 _earlyMigrationDurationDays,
        uint256 _earlyMigrationBonusBps
    ) public initializer {
        state = MorpherState(_stateAddress);
        plasmaStateRoot = _plasmaStateRoot;
        
        migrationStartTime = block.timestamp;
        migrationEndTime = block.timestamp + (_migrationDurationDays * 1 days);
        earlyMigrationEndTime = block.timestamp + (_earlyMigrationDurationDays * 1 days);
        earlyMigrationBonus = _earlyMigrationBonusBps;
        migrationPaused = false;
        
        emit MigrationStarted(migrationStartTime, migrationEndTime);
        emit PlasmaStateRootUpdated(_plasmaStateRoot);
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
    
    function extendMigrationWindow(uint256 _additionalDays) public onlyRole(ADMINISTRATOR_ROLE) {
        migrationEndTime += _additionalDays * 1 days;
        emit MigrationWindowExtended(migrationEndTime);
    }
    
    // ------------------------------------------------------------------------
    // Migration functions
    // ------------------------------------------------------------------------
    
    /**
     * Migrate a single position from plasma chain to Base L2
     */
    function migratePosition(
        bytes32[] memory _proof,
        bytes32 _marketId,
        uint256 _timeStamp,
        uint256 _longShares,
        uint256 _shortShares,
        uint256 _meanEntryPrice,
        uint256 _meanEntrySpread,
        uint256 _meanEntryLeverage,
        uint256 _liquidationPrice
    ) public migrationActive userNotBlocked {
        // Generate position hash
        bytes32 positionHash = MorpherTradeEngine(state.morpherTradeEngineAddress()).getPositionHash(
            _msgSender(), 
            _marketId, 
            _timeStamp, 
            _longShares, 
            _shortShares, 
            _meanEntryPrice, 
            _meanEntrySpread, 
            _meanEntryLeverage, 
            _liquidationPrice
        );
        
        // Verify position hasn't been migrated already
        require(!migratedPositions[positionHash], "MorpherMigration: Position already migrated");
        
        // Verify Merkle proof
        require(
            MerkleProofUpgradeable.verify(_proof, plasmaStateRoot, positionHash),
            "MorpherMigration: Invalid Merkle proof"
        );
        
        // Mark position as migrated
        migratedPositions[positionHash] = true;
        
        // Set position in trade engine
        MorpherTradeEngine(state.morpherTradeEngineAddress()).setPosition(
            _msgSender(),
            _marketId,
            _timeStamp,
            _longShares,
            _shortShares,
            _meanEntryPrice,
            _meanEntrySpread,
            _meanEntryLeverage,
            _liquidationPrice
        );
        
        // Update statistics
        totalPositionsMigrated++;
        
        emit PositionMigrated(
            _msgSender(),
            _marketId,
            _longShares,
            _shortShares,
            positionHash
        );
    }
    
    /**
     * Migrate multiple positions in a single transaction
     */
    function migratePositionsBatch(
        bytes32[][] memory _proofs,
        bytes32[] memory _marketIds,
        uint256[] memory _timeStamps,
        uint256[] memory _longShares,
        uint256[] memory _shortShares,
        uint256[] memory _meanEntryPrices,
        uint256[] memory _meanEntrySpreads,
        uint256[] memory _meanEntryLeverages,
        uint256[] memory _liquidationPrices
    ) public migrationActive userNotBlocked {
        require(
            _marketIds.length == _timeStamps.length &&
            _timeStamps.length == _longShares.length &&
            _longShares.length == _shortShares.length &&
            _shortShares.length == _meanEntryPrices.length &&
            _meanEntryPrices.length == _meanEntrySpreads.length &&
            _meanEntrySpreads.length == _meanEntryLeverages.length &&
            _meanEntryLeverages.length == _liquidationPrices.length &&
            _liquidationPrices.length == _proofs.length,
            "MorpherMigration: Array length mismatch"
        );
        
        bytes32[] memory positionHashes = new bytes32[](_marketIds.length);
        
        for (uint i = 0; i < _marketIds.length; i++) {
            // Generate position hash
            bytes32 positionHash = MorpherTradeEngine(state.morpherTradeEngineAddress()).getPositionHash(
                _msgSender(), 
                _marketIds[i], 
                _timeStamps[i], 
                _longShares[i], 
                _shortShares[i], 
                _meanEntryPrices[i], 
                _meanEntrySpreads[i], 
                _meanEntryLeverages[i], 
                _liquidationPrices[i]
            );
            
            // Verify position hasn't been migrated already
            require(!migratedPositions[positionHash], "MorpherMigration: Position already migrated");
            
            // Verify Merkle proof
            require(
                MerkleProofUpgradeable.verify(_proofs[i], plasmaStateRoot, positionHash),
                "MorpherMigration: Invalid Merkle proof"
            );
            
            // Mark position as migrated
            migratedPositions[positionHash] = true;
            
            // Set position in trade engine
            MorpherTradeEngine(state.morpherTradeEngineAddress()).setPosition(
                _msgSender(),
                _marketIds[i],
                _timeStamps[i],
                _longShares[i],
                _shortShares[i],
                _meanEntryPrices[i],
                _meanEntrySpreads[i],
                _meanEntryLeverages[i],
                _liquidationPrices[i]
            );
            
            positionHashes[i] = positionHash;
        }
        
        // Update statistics
        totalPositionsMigrated += _marketIds.length;
        
        emit PositionsBatchMigrated(
            _msgSender(),
            _marketIds.length,
            positionHashes
        );
    }
    
    /**
     * Migrate token balance from plasma chain to Base L2
     */
    function migrateBalance(
        bytes32[] memory _proof,
        uint256 _balance
    ) public migrationActive userNotBlocked {
        // Verify balance hasn't been migrated already
        require(!migratedBalances[_msgSender()], "MorpherMigration: Balance already migrated");
        
        // Generate balance hash
        bytes32 balanceHash = keccak256(abi.encodePacked(_msgSender(), _balance));
        
        // Verify Merkle proof
        require(
            MerkleProofUpgradeable.verify(_proof, plasmaStateRoot, balanceHash),
            "MorpherMigration: Invalid Merkle proof"
        );
        
        // Mark balance as migrated
        migratedBalances[_msgSender()] = true;
        
        // Calculate bonus for early migration if applicable
        uint256 amountToMint = _balance;
        if (block.timestamp <= earlyMigrationEndTime && earlyMigrationBonus > 0) {
            amountToMint += (_balance * earlyMigrationBonus) / 10000;
        }
        
        // Mint tokens to user
        MorpherToken(state.morpherTokenAddress()).mint(_msgSender(), amountToMint);
        
        // Update statistics
        totalBalancesMigrated++;
        totalUsersMigrated++;
        
        emit BalanceMigrated(_msgSender(), amountToMint);
    }
    
    /**
     * Authorize a delegate to migrate on behalf of the user
     */
    function authorizeDelegateMigration(address _delegate, bool _authorized) public userNotBlocked {
        delegateMigrationAuthorized[_msgSender()][_delegate] = _authorized;
        emit DelegateMigrationAuthorized(_msgSender(), _delegate, _authorized);
    }
    
    /**
     * Delegate migration of a position
     */
    function delegateMigratePosition(
        address _user,
        bytes32[] memory _proof,
        bytes32 _marketId,
        uint256 _timeStamp,
        uint256 _longShares,
        uint256 _shortShares,
        uint256 _meanEntryPrice,
        uint256 _meanEntrySpread,
        uint256 _meanEntryLeverage,
        uint256 _liquidationPrice
    ) public migrationActive {
        require(
            delegateMigrationAuthorized[_user][_msgSender()],
            "MorpherMigration: Not authorized as delegate"
        );
        
        // Generate position hash
        bytes32 positionHash = MorpherTradeEngine(state.morpherTradeEngineAddress()).getPositionHash(
            _user, 
            _marketId, 
            _timeStamp, 
            _longShares, 
            _shortShares, 
            _meanEntryPrice, 
            _meanEntrySpread, 
            _meanEntryLeverage, 
            _liquidationPrice
        );
        
        // Verify position hasn't been migrated already
        require(!migratedPositions[positionHash], "MorpherMigration: Position already migrated");
        
        // Verify Merkle proof
        require(
            MerkleProofUpgradeable.verify(_proof, plasmaStateRoot, positionHash),
            "MorpherMigration: Invalid Merkle proof"
        );
        
        // Mark position as migrated
        migratedPositions[positionHash] = true;
        
        // Set position in trade engine
        MorpherTradeEngine(state.morpherTradeEngineAddress()).setPosition(
            _user,
            _marketId,
            _timeStamp,
            _longShares,
            _shortShares,
            _meanEntryPrice,
            _meanEntrySpread,
            _meanEntryLeverage,
            _liquidationPrice
        );
        
        // Update statistics
        totalPositionsMigrated++;
        
        emit PositionMigrated(
            _user,
            _marketId,
            _longShares,
            _shortShares,
            positionHash
        );
    }
    
    /**
     * Delegate migration of token balance
     */
    function delegateMigrateBalance(
        address _user,
        bytes32[] memory _proof,
        uint256 _balance
    ) public migrationActive {
        require(
            delegateMigrationAuthorized[_user][_msgSender()],
            "MorpherMigration: Not authorized as delegate"
        );
        
        // Verify balance hasn't been migrated already
        require(!migratedBalances[_user], "MorpherMigration: Balance already migrated");
        
        // Generate balance hash
        bytes32 balanceHash = keccak256(abi.encodePacked(_user, _balance));
        
        // Verify Merkle proof
        require(
            MerkleProofUpgradeable.verify(_proof, plasmaStateRoot, balanceHash),
            "MorpherMigration: Invalid Merkle proof"
        );
        
        // Mark balance as migrated
        migratedBalances[_user] = true;
        
        // Calculate bonus for early migration if applicable
        uint256 amountToMint = _balance;
        if (block.timestamp <= earlyMigrationEndTime && earlyMigrationBonus > 0) {
            amountToMint += (_balance * earlyMigrationBonus) / 10000;
        }
        
        // Mint tokens to user
        MorpherToken(state.morpherTokenAddress()).mint(_user, amountToMint);
        
        // Update statistics
        totalBalancesMigrated++;
        totalUsersMigrated++;
        
        emit BalanceMigrated(_user, amountToMint);
    }
    
    /**
     * Verify if a position is valid without migrating it
     * This is a view function that can be used by frontends to verify positions before migration
     */
    function verifyPosition(
        address _user,
        bytes32[] memory _proof,
        bytes32 _marketId,
        uint256 _timeStamp,
        uint256 _longShares,
        uint256 _shortShares,
        uint256 _meanEntryPrice,
        uint256 _meanEntrySpread,
        uint256 _meanEntryLeverage,
        uint256 _liquidationPrice
    ) public view returns (bool) {
        bytes32 positionHash = MorpherTradeEngine(state.morpherTradeEngineAddress()).getPositionHash(
            _user, 
            _marketId, 
            _timeStamp, 
            _longShares, 
            _shortShares, 
            _meanEntryPrice, 
            _meanEntrySpread, 
            _meanEntryLeverage, 
            _liquidationPrice
        );
        
        return MerkleProofUpgradeable.verify(_proof, plasmaStateRoot, positionHash);
    }
    
    /**
     * Verify if a balance is valid without migrating it
     * This is a view function that can be used by frontends to verify balances before migration
     */
    function verifyBalance(
        address _user,
        bytes32[] memory _proof,
        uint256 _balance
    ) public view returns (bool) {
        bytes32 balanceHash = keccak256(abi.encodePacked(_user, _balance));
        return MerkleProofUpgradeable.verify(_proof, plasmaStateRoot, balanceHash);
    }
    
    /**
     * Get migration statistics
     */
    function getMigrationStats() public view returns (
        uint256 _totalPositionsMigrated,
        uint256 _totalBalancesMigrated,
        uint256 _totalUsersMigrated,
        uint256 _migrationTimeRemaining,
        bool _migrationActive
    ) {
        uint256 timeRemaining = 0;
        if (block.timestamp < migrationEndTime) {
            timeRemaining = migrationEndTime - block.timestamp;
        }
        
        bool active = block.timestamp >= migrationStartTime && 
                     block.timestamp <= migrationEndTime && 
                     !migrationPaused;
        
        return (
            totalPositionsMigrated,
            totalBalancesMigrated,
            totalUsersMigrated,
            timeRemaining,
            active
        );
    }
}
