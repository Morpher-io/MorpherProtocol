//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.20; // Update pragma if needed

// --- Updated Imports ---
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ContextUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/utils/ContextUpgradeable.sol"; // Add Context back
import "./MorpherToken.sol"; // Ensure this points to the adapted v5 version later
import "./MorpherTradeEngine.sol"; // Ensure this points to the adapted v5 version later
import "./MorpherAccessControl.sol"; // Use the adapted v5 interface/contract

contract MorpherState is UUPSUpgradeable, ContextUpgradeable { // --- Inherit UUPSUpgradeable and ContextUpgradeable ---

    // --- Remove __gap variable if present ---

    address public morpherAccessControlAddress;
    address public morpherAirdropAddress;
    address public morpherBridgeAddress;
    address public morpherFaucetAddress;
    address public morpherGovernanceAddress;
    address public morpherMintingLimiterAddress;
    address public morpherOracleAddress;
    address payable public morpherStakingAddress;
    address public morpherTokenAddress;
    address public morpherTradeEngineAddress;
    address public morpherUserBlockingAddress;

    /**
     * Roles known to State
     */
    bytes32 public constant ADMINISTRATOR_ROLE = keccak256("ADMINISTRATOR_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    bytes32 public constant PLATFORM_ROLE = keccak256("PLATFORM_ROLE");
    // No need to redefine ADMINISTRATOR_ROLE if only used for modifiers checking AccessControl

    address public morpherRewards;
    uint256 public maximumLeverage; // Leverage precision is 1e8, maximum leverage set to 10 initially
    uint256 public constant PRECISION = 10**8;
    uint256 public constant DECIMALS = 18;
    uint256 public constant REWARDPERIOD = 1 days;

    uint256 public rewardBasisPoints;
    uint256 public lastRewardTime;

    bytes32 public sideChainMerkleRoot;
    uint256 public sideChainMerkleRootWrittenAtTime;

    // Set initial withdraw limit from sidechain to 20m token or 2% of initial supply
    uint256 public mainChainWithdrawLimit24;

    mapping(bytes32 => bool) private marketActive;

    // ----------------------------------------------------------------------------
    // Sidechain spam protection
    // ----------------------------------------------------------------------------

    mapping(address => uint256) private lastRequestBlock;
    mapping(address => uint256) private numberOfRequests;
    uint256 public numberOfRequestsLimit;


    bool public mainChain; 
    
    // ----------------------------------------------------------------------------
    // New interest rate management
    // ----------------------------------------------------------------------------

    address public morpherInterestRateManagerAddress;
    
    address public morpherSidechainToBaseMigrationAddress; // Added


    // ----------------------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------------------
    event OperatingRewardMinted(address indexed recipient, uint256 amount);

    event RewardsChange(address indexed rewardsAddress, uint256 indexed rewardsBasisPoints);
    event LastRewardTime(uint256 indexed rewardsTime);

   
    event MaximumLeverageChange(uint256 maxLeverage);
    event MarketActivated(bytes32 indexed activateMarket);
    event MarketDeActivated(bytes32 indexed deActivateMarket);


    modifier onlyRole(bytes32 role) {
        require(MorpherAccessControl(morpherAccessControlAddress).hasRole(role, _msgSender()), "MorpherState: Permission denied.");
        _;
    }

    // --- Initializer ---
    function initialize(bool _mainChain, address _morpherAccessControlAddress) public initializer {
        // Call parent initializers
        __UUPSUpgradeable_init();
        __Context_init(); // Initialize Context

        morpherAccessControlAddress = _morpherAccessControlAddress;
        mainChain = _mainChain;

        maximumLeverage = 10*PRECISION; // Leverage precision is 1e8, maximum leverage set to 10 initially
    }

    // --- Implement _authorizeUpgrade ---
    function _authorizeUpgrade(address /** unused */)
        internal
        view
        override
    {
        // Check if the sender has the PROXYUPDATER_ROLE defined in MorpherAccessControl
        require(
            MorpherAccessControl(morpherAccessControlAddress).hasRole(
                MorpherAccessControl(morpherAccessControlAddress).PROXYUPDATER_ROLE(), // Get role hash from AC
                _msgSender()
            ),
            "MorpherState: Caller is not the proxy updater"
        );
    }

    // ----------------------------------------------------------------------------
    // Setter/Getter functions for platform roles
    // ----------------------------------------------------------------------------

    event SetMorpherAccessControlAddress(address _oldAddress, address _newAddress);
    function setMorpherAccessControl(address _morpherAccessControlAddress) public onlyRole(ADMINISTRATOR_ROLE) {
        emit SetMorpherAccessControlAddress(morpherAccessControlAddress, _morpherAccessControlAddress);
        morpherAccessControlAddress = _morpherAccessControlAddress;
    }

    event SetMorpherAirdropAddress(address _oldAddress, address _newAddress);
    function setMorpherAirdrop(address _morpherAirdropAddress) public onlyRole(ADMINISTRATOR_ROLE) {
        emit SetMorpherAirdropAddress(morpherAirdropAddress, _morpherAirdropAddress);
        morpherAirdropAddress = _morpherAirdropAddress;
    }

    event SetMorpherBridgeAddress(address _oldAddress, address _newAddress);
    function setMorpherBridge(address _morpherBridgeAddress) public onlyRole(ADMINISTRATOR_ROLE) {
        emit SetMorpherBridgeAddress(morpherBridgeAddress, _morpherBridgeAddress);
        morpherBridgeAddress = _morpherBridgeAddress;
    }

    event SetMorpherFaucetAddress(address _oldAddress, address _newAddress);
    function setMorpherFaucet(address _morpherFaucetAddress) public onlyRole(ADMINISTRATOR_ROLE) {
        emit SetMorpherFaucetAddress(morpherFaucetAddress, _morpherFaucetAddress);
        morpherFaucetAddress = _morpherFaucetAddress;
    }

    event SetMorpherGovernanceAddress(address _oldAddress, address _newAddress);
    function setMorpherGovernance(address _morpherGovernanceAddress) public onlyRole(ADMINISTRATOR_ROLE) {
        emit SetMorpherGovernanceAddress(morpherGovernanceAddress, _morpherGovernanceAddress);
        morpherGovernanceAddress = _morpherGovernanceAddress;
    }

    event SetMorpherMintingLimiterAddress(address _oldAddress, address _newAddress);
    function setMorpherMintingLimiter(address _morpherMintingLimiterAddress) public onlyRole(ADMINISTRATOR_ROLE) {
        emit SetMorpherMintingLimiterAddress(morpherMintingLimiterAddress, _morpherMintingLimiterAddress);
        morpherMintingLimiterAddress = _morpherMintingLimiterAddress;
    }
    event SetMorpherOracleAddress(address _oldAddress, address _newAddress);
    function setMorpherOracle(address _morpherOracleAddress) public onlyRole(ADMINISTRATOR_ROLE) {
        emit SetMorpherOracleAddress(morpherOracleAddress, _morpherOracleAddress);
        morpherOracleAddress = _morpherOracleAddress;
    }

    event SetMorpherStakingAddress(address _oldAddress, address _newAddress); // Note: Event param was already address
    function setMorpherStakingAddress(address _morpherStakingAddress) public onlyRole(ADMINISTRATOR_ROLE) { // Renamed and changed param type
        require(_morpherStakingAddress != address(0), "MorpherState: Address cannot be zero");
        emit SetMorpherStakingAddress(morpherStakingAddress, _morpherStakingAddress);
        morpherStakingAddress = payable(_morpherStakingAddress);
    }

    event SetMorpherTokenAddress(address _oldAddress, address _newAddress);
    function setMorpherToken(address _morpherTokenAddress) public onlyRole(ADMINISTRATOR_ROLE) {
        emit SetMorpherTokenAddress(morpherTokenAddress, _morpherTokenAddress);
        morpherTokenAddress = _morpherTokenAddress;
    }

    event SetMorpherTradeEngineAddress(address _oldAddress, address _newAddress);
    function setMorpherTradeEngine(address _morpherTradeEngineAddress) public onlyRole(ADMINISTRATOR_ROLE) {
        emit SetMorpherTradeEngineAddress(morpherTradeEngineAddress, _morpherTradeEngineAddress);
        morpherTradeEngineAddress = _morpherTradeEngineAddress;
    }

    event SetMorpherUserBlockingAddress(address _oldAddress, address _newAddress);
    function setMorpherUserBlocking(address _morpherUserBlockingAddress) public onlyRole(ADMINISTRATOR_ROLE) {
        emit SetMorpherUserBlockingAddress(morpherUserBlockingAddress, _morpherUserBlockingAddress);
        morpherUserBlockingAddress = _morpherUserBlockingAddress;
    }

    event SetMorpherInterestRateManagerAddress(address _oldAddress, address _newAddress);
    function setMorpherInterestRateManager(address _morpherInterestRateManagerAddress) public onlyRole(ADMINISTRATOR_ROLE) {
        emit SetMorpherInterestRateManagerAddress(morpherInterestRateManagerAddress, _morpherInterestRateManagerAddress);
        morpherInterestRateManagerAddress = _morpherInterestRateManagerAddress;
    }

    event SetMorpherSidechainToBaseMigrationAddress(address _oldAddress, address _newAddress); // Added Event
    function setMorpherSidechainToBaseMigrationAddress(address _morpherSidechainToBaseMigrationAddress) public onlyRole(ADMINISTRATOR_ROLE) { // Added Function
        require(_morpherSidechainToBaseMigrationAddress != address(0), "MorpherState: Address cannot be zero");
        emit SetMorpherSidechainToBaseMigrationAddress(morpherSidechainToBaseMigrationAddress, _morpherSidechainToBaseMigrationAddress);
        morpherSidechainToBaseMigrationAddress = _morpherSidechainToBaseMigrationAddress;
    }

    // ----------------------------------------------------------------------------
    // Setter/Getter functions for platform administration
    // ----------------------------------------------------------------------------

    function activateMarket(bytes32 _activateMarket) public onlyRole(ADMINISTRATOR_ROLE)  {
        marketActive[_activateMarket] = true;
        emit MarketActivated(_activateMarket);
    }

    /**
     * @notice Activates multiple markets.
     * @param _markets Array of market IDs (bytes32) to activate.
     */
    function activateMarket(bytes32[] calldata _markets) public onlyRole(ADMINISTRATOR_ROLE) {
        for (uint i = 0; i < _markets.length; i++) {
            if (_markets[i] != bytes32(0x0)) { // Skip empty slots if any
                marketActive[_markets[i]] = true;
                emit MarketActivated(_markets[i]);
            }
        }
    }

    function deActivateMarket(bytes32 _deActivateMarket) public onlyRole(ADMINISTRATOR_ROLE) {
        marketActive[_deActivateMarket] = false;
        emit MarketDeActivated(_deActivateMarket);
    }

    /**
     * @notice Deactivates multiple markets.
     * @param _markets Array of market IDs (bytes32) to deactivate.
     */
    function deActivateMarket(bytes32[] calldata _markets) public onlyRole(ADMINISTRATOR_ROLE) {
        for (uint i = 0; i < _markets.length; i++) {
            if (_markets[i] != bytes32(0x0)) { // Skip empty slots if any
                marketActive[_markets[i]] = false;
                emit MarketDeActivated(_markets[i]);
            }
        }
    }

    function getMarketActive(bytes32 _marketId) public view returns(bool _active) {
        return marketActive[_marketId];
    }

    function setMaximumLeverage(uint256 _newMaximumLeverage) public onlyRole(ADMINISTRATOR_ROLE)  {
        require(_newMaximumLeverage > PRECISION, "MorpherState: Leverage precision is 1e8");
        maximumLeverage = _newMaximumLeverage;
        emit MaximumLeverageChange(_newMaximumLeverage);
    }

    function getMaximumLeverage() public view returns(uint256 _maxLeverage) {
        return maximumLeverage;
    }

    /**
     * Backwards compatibility functions
     */
    function getLastUpdated(address _address, bytes32 _marketHash) public view returns(uint) {
        return MorpherTradeEngine(morpherTradeEngineAddress).getPosition(_address, _marketHash).lastUpdated; 
    }

    function totalToken() public view returns(uint) {
        return MorpherToken(morpherTokenAddress).totalSupply();
    }

    function getPosition(
        address _address,
        bytes32 _marketId
    ) public view returns (
        uint256 _longShares,
        uint256 _shortShares,
        uint256 _meanEntryPrice,
        uint256 _meanEntrySpread,
        uint256 _meanEntryLeverage,
        uint256 _liquidationPrice
    ) {
        MorpherTradeEngine.position memory position = MorpherTradeEngine(morpherTradeEngineAddress).getPosition(_address, _marketId);
        return (
            position.longShares,
            position.shortShares,
            position.meanEntryPrice,
            position.meanEntrySpread,
            position.meanEntryLeverage,
            position.liquidationPrice
        );
    }

    
}
