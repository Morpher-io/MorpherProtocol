// ------------------------------------------------------------------------
// MorpherSidechainToBaseMigration
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

contract MorpherSidechainToBaseMigration is Initializable, ContextUpgradeable {
    
    MorpherState state;
    
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
    
    // Position migration authorization
    mapping(address => bool) public userAuthorizedMigration;
    mapping(address => uint256) public lastMigratedPositionIndex;
    mapping(address => bytes32[]) public userPositionIds;
    
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
    
    event BalanceMigrated(
        address indexed user,
        uint256 amount
    );
    
    event DelegateMigrationAuthorized(
        address indexed user,
        address indexed delegate,
        bool authorized
    );
    
    event MigrationAuthorized(address indexed user);
    event MigrationInitiated(address indexed user);
    
    // Delegate migration authorization
    mapping(address => mapping(address => bool)) public delegateMigrationAuthorized;
    
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
    
    function initialize(
        address _stateAddress,
        bytes32 _plasmaStateRoot,
        uint256 _migrationBonusBps
    ) public initializer {
        state = MorpherState(_stateAddress);
        plasmaStateRoot = _plasmaStateRoot;
        migrationBonus = _migrationBonusBps;
        migrationPaused = false;
        
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
    
    function setFinalBalanceMerkleRoot(bytes32 _root) public onlyRole(ADMINISTRATOR_ROLE) {
        finalBalanceMerkleRoot = _root;
        emit FinalBalanceMerkleRootSet(_root);
    }
    
    // ------------------------------------------------------------------------
    // Migration functions
    // ------------------------------------------------------------------------
    
    /**
     * Authorize position migration with signature
     */
    function authorizePositionMigration(bytes memory _signature) public userNotBlocked activeMigrationPhase {
        // User signs a message authorizing migration of all their positions
        bytes32 messageHash = keccak256(abi.encodePacked(
            "I authorize migration of all my positions from plasma chain to Base L2",
            _msgSender(),
            block.chainid
        ));
        
        address signer = ECDSAUpgradeable.recover(ECDSAUpgradeable.toEthSignedMessageHash(messageHash), _signature);
        require(signer == _msgSender(), "MorpherMigration: Invalid signature");
        
        userAuthorizedMigration[_msgSender()] = true;
        emit MigrationAuthorized(_msgSender());
    }
    
    /**
     * Initiate full migration process
     */
    function initiateFullMigration(bytes memory _signature) public userNotBlocked activeMigrationPhase {
        // Authorize position migration
        authorizePositionMigration(_signature);
        
        // Emit event for backend to start migration process
        emit MigrationInitiated(_msgSender());
    }
    
    
    
    /**
     * Migrate token balance from plasma chain to Base L2 in self-service phase
     * Uses the finalBalanceMerkleRoot which is set after the active migration period
     */
    function migrateBalanceSelfService(
        bytes32[] memory _proof,
        uint256 _balance
    ) public userNotBlocked {
        // Verify balance hasn't been migrated already
        require(!migratedBalances[_msgSender()], "MorpherMigration: Balance already migrated");
        require(finalBalanceMerkleRoot != bytes32(0), "MorpherMigration: Final balance root not set");
        
        // Generate balance hash
        bytes32 balanceHash = keccak256(abi.encodePacked(_msgSender(), _balance));
        
        // Verify Merkle proof against final balance root
        require(
            MerkleProofUpgradeable.verify(_proof, finalBalanceMerkleRoot, balanceHash),
            "MorpherMigration: Invalid Merkle proof"
        );
        
        // Mark balance as migrated
        migratedBalances[_msgSender()] = true;
        
        // No bonus for self-service migration
        uint256 amountToMint = _balance;
        
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
        bytes32[] proof;
    }
    
    /**
     * Delegate migration of positions in batch with user authorization signature
     */
    function delegateMigratePositionsBatch(
        address _user,
        bytes memory _userAuthSignature,
        bytes32 _merkleRoot,
        PositionMigrationData[] memory _positions
    ) public onlyRole(MIGRATION_OPERATOR_ROLE) migrationActive {
        require(_positions.length > 0, "MorpherMigration: No positions to migrate");
        
        // Verify user authorization signature
        bytes32 messageHash = keccak256(abi.encodePacked(
            "I authorize migration of all my positions from plasma chain to Base L2",
            _user,
            block.chainid
        ));
        
        address signer = ECDSAUpgradeable.recover(ECDSAUpgradeable.toEthSignedMessageHash(messageHash), _userAuthSignature);
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
            
            // Verify Merkle proof against the provided merkle root
            require(
                MerkleProofUpgradeable.verify(pos.proof, _merkleRoot, positionHash),
                "MorpherMigration: Invalid Merkle proof"
            );
            
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
        
        // Mark user as having authorized migration (for future reference)
        userAuthorizedMigration[_user] = true;
        
        emit PositionsBatchMigrated(
            _user,
            _positions.length,
            positionHashes
        );
    }
    
    /**
     * Delegate migration of token balance with operator role and custom merkle root
     */
    function delegateMigrateBalance(
        address _user,
        bytes memory _userAuthSignature,
        bytes32 _merkleRoot,
        bytes32[] memory _proof,
        uint256 _balance
    ) public onlyRole(MIGRATION_OPERATOR_ROLE) migrationActive {
        // Verify user authorization signature
        bytes32 messageHash = keccak256(abi.encodePacked(
            "I authorize migration of all my positions from plasma chain to Base L2",
            _user,
            block.chainid
        ));
        
        address signer = ECDSAUpgradeable.recover(ECDSAUpgradeable.toEthSignedMessageHash(messageHash), _userAuthSignature);
        require(signer == _user, "MorpherMigration: Invalid user authorization signature");
        
        // Verify balance hasn't been migrated already
        require(!migratedBalances[_user], "MorpherMigration: Balance already migrated");
        
        // Generate balance hash
        bytes32 balanceHash = keccak256(abi.encodePacked(_user, _balance));
        
        // Verify Merkle proof against the provided merkle root
        require(
            MerkleProofUpgradeable.verify(_proof, _merkleRoot, balanceHash),
            "MorpherMigration: Invalid Merkle proof"
        );
        
        // Mark balance as migrated
        migratedBalances[_user] = true;
        
        // Apply migration bonus if configured
        uint256 amountToMint = _balance;
        if (migrationBonus > 0) {
            amountToMint += (_balance * migrationBonus) / 10000;
        }
        
        // Mint tokens to user
        MorpherToken(state.morpherTokenAddress()).mint(_user, amountToMint);
        
        // Update statistics
        totalBalancesMigrated++;
        totalUsersMigrated++;
        
        // Mark user as having authorized migration (for future reference)
        userAuthorizedMigration[_user] = true;
        
        emit BalanceMigrated(_user, amountToMint);
    }
    
    /**
     * Verify if a position is valid without migrating it
     * This is a view function that can be used by frontends to verify positions before migration
     */
    function verifyPosition(
        address _user,
        bytes32[] memory _proof,
        bytes32 _merkleRoot,
        PositionMigrationData memory _position
    ) public view returns (bool) {
        bytes32 positionHash = MorpherTradeEngine(state.morpherTradeEngineAddress()).getPositionHash(
            _user, 
            _position.marketId, 
            _position.timeStamp, 
            _position.longShares, 
            _position.shortShares, 
            _position.meanEntryPrice, 
            _position.meanEntrySpread, 
            _position.meanEntryLeverage, 
            _position.liquidationPrice
        );
        
        return MerkleProofUpgradeable.verify(_proof, _merkleRoot, positionHash);
    }
    
    /**
     * Verify if a balance is valid without migrating it
     * This is a view function that can be used by frontends to verify balances before migration
     */
    function verifyBalance(
        address _user,
        bytes32[] memory _proof,
        bytes32 _merkleRoot,
        uint256 _balance
    ) public pure returns (bool) {
        bytes32 balanceHash = keccak256(abi.encodePacked(_user, _balance));
        return MerkleProofUpgradeable.verify(_proof, _merkleRoot, balanceHash);
    }
    
    
       
    /**
     * Get migration statistics
     */
    function getMigrationStats() public view returns (
        uint256 _totalPositionsMigrated,
        uint256 _totalBalancesMigrated,
        uint256 _totalUsersMigrated,
        bool _migrationActive,
        bool _finalBalanceRootSet
    ) {
        bool active = !migrationPaused;
        bool finalRootSet = finalBalanceMerkleRoot != bytes32(0);
        
        return (
            totalPositionsMigrated,
            totalBalancesMigrated,
            totalUsersMigrated,
            active,
            finalRootSet
        );
    }
}
