//SPDX-License-Identifier: GPLv3
pragma solidity 0.8.11;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "./MorpherToken.sol";

// ----------------------------------------------------------------------------------
// Data and token balance storage of the Morpher platform
// Writing access is only granted to platform contracts. The contract can be paused
// by an elected platform administrator (see MorpherGovernance) to perform protocol updates.
// ----------------------------------------------------------------------------------

contract MorpherState is Initializable, ContextUpgradeable  {

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
 

    address public morpherRewards;
    address public sideChainOperator;
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
    // Bridge Variables
    // ----------------------------------------------------------------------------
    mapping (address => uint256) private tokenClaimedOnThisChain;
    mapping (address => uint256) private tokenSentToLinkedChain;
    mapping (address => uint256) private tokenSentToLinkedChainTime;
    mapping (bytes32 => bool) private positionClaimedOnMainChain;

    uint256 public lastWithdrawLimitReductionTime;
    uint256 public last24HoursAmountWithdrawn;
    uint256 public withdrawLimit24Hours;
    uint256 public inactivityPeriod;
    uint256 public transferNonce;
    bool public fastTransfersEnabled;

    // ----------------------------------------------------------------------------
    // Sidechain spam protection
    // ----------------------------------------------------------------------------

    mapping(address => uint256) private lastRequestBlock;
    mapping(address => uint256) private numberOfRequests;
    uint256 public numberOfRequestsLimit;

    // ----------------------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------------------
    event OperatingRewardMinted(address indexed recipient, uint256 amount);

    event RewardsChange(address indexed rewardsAddress, uint256 indexed rewardsBasisPoints);
    event LastRewardTime(uint256 indexed rewardsTime);
    event GovernanceChange(address indexed governanceAddress);
    event TokenChange(address indexed tokenAddress);
   
    event MaximumLeverageChange(uint256 maxLeverage);
    event MarketActivated(bytes32 indexed activateMarket);
    event MarketDeActivated(bytes32 indexed deActivateMarket);
    event BridgeChange(address _bridgeAddress);
    event SideChainMerkleRootUpdate(bytes32 indexed sideChainMerkleRoot);
    event NewSideChainOperator(address indexed sideChainOperator);
    event NumberOfRequestsLimitUpdate(uint256 _numberOfRequests);

    event MainChainWithdrawLimitUpdate(uint256 indexed mainChainWithdrawLimit24);
    event TokenSentToLinkedChain(address _address, uint256 _token, uint256 _totalTokenSent, bytes32 indexed _tokenSentToLinkedChainHash);
    event TransferredTokenClaimed(address _address, uint256 _token);
    event LastWithdrawAt();
    event RollingWithdrawnAmountUpdated(uint256 _last24HoursAmountWithdrawn, uint256 _lastWithdrawLimitReductionTime);
    event WithdrawLimitUpdated(uint256 _amount);
    event InactivityPeriodUpdated(uint256 _periodLength);
    event FastWithdrawsDisabled();
    event NewBridgeNonce(uint256 _transferNonce);
    event Last24HoursAmountWithdrawnReset();

    event StatePaused(address administrator, bool _paused);

    event SetAllowance(address indexed sender, address indexed spender, uint256 tokens);
    
    event SetBalance(address indexed account, uint256 balance, bytes32 indexed balanceHash);
    event TokenTransferredToOtherChain(address indexed account, uint256 tokenTransferredToOtherChain, bytes32 indexed transferHash);

    // modifier onlyPlatform {
    //     require(stateAccess[msg.sender] == true, "MorpherState: Only Platform is allowed to execute operation.");
    //     _;
    // }

    modifier onlyRole(bytes32 role) {
        require(MorpherAccessControl(morpherAccessControlAddress).hasRole(role, _msgSender()), "MorpherTradeEngine: Permission denied.");
        _;
    }

    // modifier onlyGovernance {
    //     require(msg.sender == getGovernance(), "MorpherState: Calling contract not the Governance Contract. Aborting.");
    //     _;
    // }


    // // modifier canTransfer {
    // //     require(getCanTransfer(msg.sender), "MorpherState: Caller may not transfer token. Aborting.");
    // //     _;
    // // }

    modifier onlyBridge {
        require(msg.sender == morpherBridgeAddress, "MorpherState: Caller is not the Bridge. Aborting.");
        _;
    }

    modifier onlyMainChain {
        require(mainChain == true, "MorpherState: Can only be called on mainchain.");
        _;
    }

    // modifier onlySideChain {
    //     require(mainChain == false, "MorpherState: Can only be called on mainchain.");
    //     _;
    // }

    bool mainChain;

    function initialize(bool _mainChain, address _sideChainOperator, address _morpherTreasury, address _morpherAccessControlAddress) public initializer {
        ContextUpgradeable.__Context_init();
        
        morpherAccessControlAddress = _morpherAccessControlAddress;
        mainChain = _mainChain;
        
        setLastRewardTime(block.timestamp);
       
        setSideChainOperator(_msgSender());
        if (mainChain == false) { // Create token only on sidechain
            setRewardBasisPoints(0); // Reward is minted on mainchain
            setRewardAddress(address(0));
        } else {
            setRewardBasisPoints(PRECISION); // 15000 / PRECISION = 0.00015
            setRewardAddress(_morpherTreasury);
        }
        fastTransfersEnabled = true;
        //setMainChainWithdrawLimit(totalSupply / 50); @todo: transfer to Token
        setSideChainOperator(_sideChainOperator);

        maximumLeverage = 10*PRECISION; // Leverage precision is 1e8, maximum leverage set to 10 initially
        mainChainWithdrawLimit24 = 2 * 10**25;   
        inactivityPeriod = 3 days;
    }

    // ----------------------------------------------------------------------------
    // Setter/Getter functions for market wise exposure
    // ----------------------------------------------------------------------------

    // ----------------------------------------------------------------------------
    // Setter/Getter functions for bridge variables
    // ----------------------------------------------------------------------------
    function setTokenClaimedOnThisChain(address _address, uint256 _token) public onlyBridge {
        tokenClaimedOnThisChain[_address] = _token;
        emit TransferredTokenClaimed(_address, _token);
    }

    function getTokenClaimedOnThisChain(address _address) public view returns (uint256 _token) {
        return tokenClaimedOnThisChain[_address];
    }

    function setTokenSentToLinkedChain(address _address, uint256 _token) public onlyBridge {
        tokenSentToLinkedChain[_address] = _token;
        tokenSentToLinkedChainTime[_address] = block.timestamp;
        emit TokenSentToLinkedChain(_address, _token, tokenSentToLinkedChain[_address], getBalanceHash(_address, tokenSentToLinkedChain[_address]));
    }

    function getTokenSentToLinkedChain(address _address) public view returns (uint256 _token) {
        return tokenSentToLinkedChain[_address];
    }

    function getTokenSentToLinkedChainTime(address _address) public view returns (uint256 _timeStamp) {
        return tokenSentToLinkedChainTime[_address];
    }

    function add24HoursWithdrawn(uint256 _amount) public onlyBridge {
        last24HoursAmountWithdrawn = last24HoursAmountWithdrawn + (_amount);
        emit RollingWithdrawnAmountUpdated(last24HoursAmountWithdrawn, lastWithdrawLimitReductionTime);
    }

    function update24HoursWithdrawLimit(uint256 _amount) public onlyBridge {
        if (last24HoursAmountWithdrawn > _amount) {
            last24HoursAmountWithdrawn = last24HoursAmountWithdrawn - (_amount);
        } else {
            last24HoursAmountWithdrawn = 0;
        }
        lastWithdrawLimitReductionTime = block.timestamp;
        emit RollingWithdrawnAmountUpdated(last24HoursAmountWithdrawn, lastWithdrawLimitReductionTime);
    }

    function set24HourWithdrawLimit(uint256 _limit) public onlyBridge {
        withdrawLimit24Hours = _limit;
        emit WithdrawLimitUpdated(_limit);
    }

    function resetLast24HoursAmountWithdrawn() public onlyBridge {
        last24HoursAmountWithdrawn = 0;
        emit Last24HoursAmountWithdrawnReset();
    }

    function setInactivityPeriod(uint256 _periodLength) public onlyBridge {
        inactivityPeriod = _periodLength;
        emit InactivityPeriodUpdated(_periodLength);
    }

    function getBridgeNonce() public onlyBridge returns (uint256 _nonce) {
        transferNonce++;
        emit NewBridgeNonce(transferNonce);
        return transferNonce;
    }

    function disableFastWithdraws() public onlyBridge {
        fastTransfersEnabled = false;
        emit FastWithdrawsDisabled();
    }

    function setPositionClaimedOnMainChain(bytes32 _positionHash) public onlyBridge {
        positionClaimedOnMainChain[_positionHash] = true;
    }

    function getPositionClaimedOnMainChain(bytes32 _positionHash) public view returns (bool _alreadyClaimed) {
        return positionClaimedOnMainChain[_positionHash];
    }
    
    function getBalanceHash(address _address, uint256 _balance) public pure returns (bytes32 _hash) {
        return keccak256(abi.encodePacked(_address, _balance));
    }

    // ----------------------------------------------------------------------------
    // Setter/Getter functions for spam protection
    // ----------------------------------------------------------------------------


    function setMainChainWithdrawLimit(uint256 _mainChainWithdrawLimit24) public onlyRole(GOVERNANCE_ROLE)  {
        mainChainWithdrawLimit24 = _mainChainWithdrawLimit24;
        emit MainChainWithdrawLimitUpdate(_mainChainWithdrawLimit24);
    }

    function getMainChainWithdrawLimit() public view returns (uint256 _mainChainWithdrawLimit24) {
        return mainChainWithdrawLimit24;
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

    event SetMorpherStakingAddress(address _oldAddress, address _newAddress);
    function setMorpherStaking(address payable _morpherStakingAddress) public onlyRole(ADMINISTRATOR_ROLE) {
        emit SetMorpherStakingAddress(morpherStakingAddress, _morpherStakingAddress);
        morpherStakingAddress = _morpherStakingAddress;
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

    // ----------------------------------------------------------------------------
    // Setter/Getter functions for platform operating rewards
    // ----------------------------------------------------------------------------

    function setRewardAddress(address _newRewardsAddress) public onlyRole(GOVERNANCE_ROLE) {
        morpherRewards = _newRewardsAddress;
        emit RewardsChange(_newRewardsAddress, rewardBasisPoints);
    }

    function setRewardBasisPoints(uint256 _newRewardBasisPoints) public onlyRole(GOVERNANCE_ROLE) {
        if (mainChain == true) {
            require(_newRewardBasisPoints <= 15000, "MorpherState: Reward basis points need to be less or equal to 15000.");
        } else {
            require(_newRewardBasisPoints == 0, "MorpherState: Reward basis points can only be set on Ethereum.");
        }
        rewardBasisPoints = _newRewardBasisPoints;
        emit RewardsChange(morpherRewards, _newRewardBasisPoints);
    }

    function setLastRewardTime(uint256 _lastRewardTime) private {
        lastRewardTime = _lastRewardTime;
        emit LastRewardTime(_lastRewardTime);
    }

    // ----------------------------------------------------------------------------
    // Setter/Getter functions for platform administration
    // ----------------------------------------------------------------------------

    function activateMarket(bytes32 _activateMarket) public onlyRole(ADMINISTRATOR_ROLE)  {
        marketActive[_activateMarket] = true;
        emit MarketActivated(_activateMarket);
    }

    function deActivateMarket(bytes32 _deActivateMarket) public onlyRole(ADMINISTRATOR_ROLE)  {
        marketActive[_deActivateMarket] = false;
        emit MarketDeActivated(_deActivateMarket);
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

    // ----------------------------------------------------------------------------
    // Setter/Getter for side chain state
    // ----------------------------------------------------------------------------

    function setSideChainMerkleRoot(bytes32 _sideChainMerkleRoot) public onlyBridge {
        sideChainMerkleRoot = _sideChainMerkleRoot;
        sideChainMerkleRootWrittenAtTime = block.timestamp;
        payOperatingReward();
        emit SideChainMerkleRootUpdate(_sideChainMerkleRoot);
    }

    function getSideChainMerkleRoot() public view returns(bytes32 _sideChainMerkleRoot) {
        return sideChainMerkleRoot;
    }

    function setSideChainOperator(address _address) public onlyRole(ADMINISTRATOR_ROLE)  {
        sideChainOperator = _address;
        emit NewSideChainOperator(_address);
    }

    function getSideChainOperator() public view returns (address _address) {
        return sideChainOperator;
    }

    function getSideChainMerkleRootWrittenAtTime() public view returns(uint256 _sideChainMerkleRoot) {
        return sideChainMerkleRootWrittenAtTime;
    }

    // ----------------------------------------------------------------------------
    // Setter/Getter functions for portfolio
    // ----------------------------------------------------------------------------

   
    // ----------------------------------------------------------------------------
    // Record positions by market by address. Needed for exposure aggregations
    // and spits and dividends.
    // ----------------------------------------------------------------------------
    
    // ----------------------------------------------------------------------------
    // Calculate and send operating reward
    // Every 24 hours the protocol mints rewardBasisPoints/(PRECISION) percent of the total
    // supply as reward for the protocol operator. The amount can not exceed 0.015% per
    // day.
    // ----------------------------------------------------------------------------

    function payOperatingReward() public onlyMainChain {
        if (block.timestamp > lastRewardTime + (REWARDPERIOD)) {
            uint256 _reward = MorpherToken(morpherTokenAddress).totalSupply() * (rewardBasisPoints) / (PRECISION);
            setLastRewardTime(lastRewardTime + (REWARDPERIOD));
            MorpherToken(morpherTokenAddress).mint(morpherRewards, _reward);
            emit OperatingRewardMinted(morpherRewards, _reward);
        }
    }
}
