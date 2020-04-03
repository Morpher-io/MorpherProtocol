pragma solidity 0.5.16;

//import "../node_modules/@openzeppelin/contracts/ownership/Ownable.sol";
//import "../node_modules/@openzeppelin/contracts/math/SafeMath.sol";

import "./Ownable.sol";
import "./SafeMath.sol";
import "./IMorpherToken.sol";
import "./IERC20.sol";

// ----------------------------------------------------------------------------------
// Data and token balance storage of the Morpher platform
// Writing access is only granted to platform contracts. The contract can be paused
// by an elected platform administrator (see MorpherGovernance) to perform protocol updates.
// ----------------------------------------------------------------------------------

contract MorpherState is Ownable {
    using SafeMath for uint256;

    uint256 public totalSupply;
    uint256 public totalCashSupply;
    uint256 public maxLeverage = 10;
    uint256 constant PRECISION = 10**8;
    uint256 constant DECIMALS = 18;
    bool public paused = false;

    address public morpherGovernance;
    address public morpherRewards;
    address public administrator;
    address public oracleContract;
    address public sideChainOperator;
    address public morpherBridge;
    address public morpherToken;

    uint256 public rewardBasisPoints;
    uint256 public lastRewardTime;

    bytes32 public sideChainMerkleRoot;
    uint256 public sideChainMerkleRootWrittenAtTime;

    uint256 public mainChainWithdrawLimit24;

    mapping(address => bool) stateAccess;
    mapping(address => bool) transferAllowed;
    
    mapping(address => uint256) balances;
    mapping(address => mapping(address => uint256)) allowed;

    mapping(bytes32 => bool) marketActive;

// ----------------------------------------------------------------------------
// Position struct records virtual futures
// ----------------------------------------------------------------------------
    struct position {
        uint256 lastUpdated;
        uint256 longShares;
        uint256 shortShares;
        uint256 meanEntryPrice;
        uint256 meanEntrySpread;
        uint256 meanEntryLeverage;
        uint256 liquidationPrice;
        bytes32 positionHash;
    }

// ----------------------------------------------------------------------------
// A portfolio is an address specific collection of postions
// ----------------------------------------------------------------------------
    mapping(address => mapping(bytes32 => position)) public portfolio;

// ----------------------------------------------------------------------------
// Record all addresses that hold a position of a market, needed for clean stock splits
// ----------------------------------------------------------------------------
    struct hasExposure {
        uint256 maxMappingIndex;
        mapping(address => uint256) index;
        mapping(uint256 => address) addy;
    }

    mapping(bytes32 => hasExposure) exposureByMarket;

// ----------------------------------------------------------------------------
// Sidechain spam protection
// ----------------------------------------------------------------------------
    mapping(address => uint256) lastRequestBlock;
    mapping(address => uint256) numberOfRequests;
    uint256 public numberOfRequestsLimit;

// ----------------------------------------------------------------------------
// Events
// ----------------------------------------------------------------------------
    event StateAccessGranted(address indexed whiteList, uint256 indexed blockNumber);
    event StateAccessDenied(address indexed blackList, uint256 indexed blockNumber);
    
    event TransfersEnabled(address indexed whiteList);
    event TransfersDisabled(address indexed blackList);

    event CreditAddress(address indexed recipient, uint256 indexed amount, uint256 totalCashSupply);
    event DebitAddress(address indexed payer, uint256 indexed amount, uint256 totalCashSupply);

    event Transfer(address indexed sender, address indexed recipient, uint256 amount, uint256 totalCashSupply);
    event Mint(address indexed recipient, uint256 amount, uint256 totalCashSupply);
    event Burn(address indexed recipient, uint256 amount, uint256 totalCashSupply);

    event RewardsChange(address indexed rewardsAddress, uint256 indexed rewardsBasisPoints);
    event LastRewardTime(uint256 indexed rewardsTime);
    event GovernanceChange(address indexed governanceAddress);
    event TokenChange(address indexed tokenAddress);
    event AdministratorChange(address indexed administratorAddress);
    event OracleChange(address indexed oracleContract);
    event MaxLeverageChange(uint256 maxLeverage);
    event MarketActivated(bytes32 indexed activateMarket);
    event MarketDeActivated(bytes32 indexed deActivateMarket);
    event NewBridge(address _bridgeAddress);
    event SideChainMerkleRootUpdate(bytes32 indexed sideChainMerkleRoot, uint256 updateTime);
    event NewSideChainOperator(address indexed sideChainOperator);
    event MainChainWithdrawLimitUpdate(uint256 indexed mainChainWithdrawLimit24);

    event NewTotalSupply(uint256 newTotalSupply);
    event NewTotalCashSupply(uint256 newTotalCashSupply);
    event StatePaused(address administrator);
    event StateUnPaused(address administrator);
    
    event SetAllowance(address indexed sender, address indexed spender, uint256 tokens);
    event SetPosition(bytes32 indexed positionHash, address indexed sender, bytes32 indexed marketId, uint256 timeStamp, uint256 longShares, uint256 shortShares, uint256 meanEntryPrice, uint256 meanEntrySpread, uint256 meanEntryLeverage, uint256 liquidationPrice);
    
    constructor() public {
        setRewardAddress(owner());
        setLastRewardTime(now);
        balances[owner()] = 1000000000 * 10**(DECIMALS);
        totalSupply = 1000000000 * 10**(DECIMALS);
        emit Mint(owner(), balanceOf(owner()), totalSupply);
        grantAccess(owner());
        setRewardBasisPoints(15000); // 15000 / PRECISION = 0.00015
        setNumberOfRequestsLimit(3);
        setMainChainWithdrawLimit(totalSupply / 50);
        denyAccess(owner());
    }

    modifier notPaused {
        require(paused == false, "MorpherState: Contract paused, aborting");
        _;
    }

    modifier onlyPlatform {
        require(stateAccess[msg.sender] == true, "MorpherState: Only Platform is allowed to execute operation.");
        _;
    }

    modifier onlyGovernance {
        require(msg.sender == getGovernance(), "MorpherState: Calling contract not the Governance Contract. Aborting.");
        _;
    }

    modifier onlyAdministrator {
        require(msg.sender == getAdministrator(), "MorpherState: Caller is not the Administrator. Aborting.");
        _;
    }

    modifier canTransfer {
        require(getCanTransfer(msg.sender), "MorpherState: Caller may not transfer token. Aborting.");
        _;
    }

    modifier onlyBridge {
        require(msg.sender == getMorpherBridge(), "MorpherState: Caller is not the Bridge. Aborting.");
        _;
    }

// ----------------------------------------------------------------------------
// Setter/Getter functions for market wise exposure
// ----------------------------------------------------------------------------

    function getMaxMappingIndex(bytes32 _marketId) public view returns(uint256 _maxMappingIndex) {
        return exposureByMarket[_marketId].maxMappingIndex;
    }

    function getExposureMappingIndex(bytes32 _marketId, address _address) public view returns(uint256 _mappingIndex) {
        return exposureByMarket[_marketId].index[_address];
    }

    function getExposureMappingAddress(bytes32 _marketId, uint256 _mappingIndex) public view returns(address _address) {
        return exposureByMarket[_marketId].addy[_mappingIndex];
    }

    function setMaxMappingIndex(bytes32 _marketId, uint256 _maxMappingIndex) public onlyPlatform {
        exposureByMarket[_marketId].maxMappingIndex = _maxMappingIndex;
    }

    function setExposureMapping(bytes32 _marketId, address _address, uint256 _index) public onlyPlatform  {
        setExposureMappingIndex(_marketId, _address, _index);
        setExposureMappingAddress(_marketId, _address, _index);
    }

    function setExposureMappingIndex(bytes32 _marketId, address _address, uint256 _index) public onlyPlatform {
        exposureByMarket[_marketId].index[_address] = _index;
    }

    function setExposureMappingAddress(bytes32 _marketId, address _address, uint256 _index) public onlyPlatform {
        exposureByMarket[_marketId].addy[_index] = _address;
    }

// ----------------------------------------------------------------------------
// Setter/Getter functions for spam protection
// ----------------------------------------------------------------------------

    function setLastRequestBlock(address _address) public onlyPlatform {
        lastRequestBlock[_address] = block.number;
    }

    function getLastRequestBlock(address _address) public view returns(uint256 _lastRequestBlock) {
        return lastRequestBlock[_address];
    }

    function setNumberOfRequests(address _address, uint256 _numberOfRequests) public onlyPlatform {
        numberOfRequests[_address] = _numberOfRequests;
    }

    function increaseNumberOfRequests(address _address) public onlyPlatform{
        numberOfRequests[_address]++;
    }

    function getNumberOfRequests(address _address) public view returns(uint256 _numberOfRequests) {
        return numberOfRequests[_address];
    }

    function setNumberOfRequestsLimit(uint256 _numberOfRequestsLimit) public onlyPlatform {
        numberOfRequestsLimit = _numberOfRequestsLimit;
    }

    function getNumberOfRequestsLimit() public view returns (uint256 _numberOfRequestsLimit) {
        return numberOfRequestsLimit;
    }

    function setMainChainWithdrawLimit(uint256 _mainChainWithdrawLimit24) public onlyOwner {
        mainChainWithdrawLimit24 = _mainChainWithdrawLimit24;
        emit MainChainWithdrawLimitUpdate(_mainChainWithdrawLimit24);
    }

    function getMainChainWithdrawLimit() public view returns (uint256 _mainChainWithdrawLimit24) {
        return mainChainWithdrawLimit24;
    }

// ----------------------------------------------------------------------------
// Setter/Getter functions for state access
// ----------------------------------------------------------------------------

    function grantAccess(address _address) public onlyOwner {
        stateAccess[_address] = true;
        emit StateAccessGranted(_address, block.number);
    }

    function denyAccess(address _address) public onlyOwner {
        stateAccess[_address] = false;
        emit StateAccessDenied(_address, block.number);
    }
    
    function getStateAccess(address _address) public view returns(bool _hasAccess) {
        return stateAccess[_address];
    }

// ----------------------------------------------------------------------------
// Setter/Getter functions for addresses that can transfer tokens (sidechain only)
// ----------------------------------------------------------------------------

    function enableTransfers(address _address) public onlyOwner {
        transferAllowed[_address] = true;
        emit TransfersEnabled(_address);
    }

    function disableTransfers(address _address) public onlyOwner {
        transferAllowed[_address] = false;
        emit TransfersDisabled(_address);
    }
    
    function getCanTransfer(address _address) public view returns(bool _hasAccess) {
        return transferAllowed[_address];
    }

// ----------------------------------------------------------------------------
// Minting/burning/transfer of token
// ----------------------------------------------------------------------------

    function transfer(address _from, address _to, uint256 _token) public onlyPlatform notPaused {
        require(balances[_from] >= _token, "MorpherState: Not enough token.");
        balances[_from] = balances[_from].sub(_token);
        balances[_to] = balances[_to].add(_token);
        IMorpherToken(morpherToken).emitTransfer(_from, _to, _token);
        emit Transfer(_from, _to, _token, totalSupply);
    }

    function mint(address _address, uint256 _token) public onlyPlatform notPaused {
        balances[_address] = balances[_address].add(_token);
        totalSupply.add(_token);
        IMorpherToken(morpherToken).emitTransfer(address(0), _address, _token);
        emit Mint(_address, _token, totalCashSupply);
    }

    function burn(address _address, uint256 _token) public onlyPlatform notPaused {
        require(balances[_address] >= _token, "MorpherState: Not enough token.");
        balances[_address] = balances[_address].sub(_token);
        totalSupply.sub(_token);
        IMorpherToken(morpherToken).emitTransfer(_address, address(0), _token);
        emit Burn(_address, _token, totalCashSupply);
    }

// ----------------------------------------------------------------------------
// Setter/Getter functions for balance and token functions (ERC20)
// ----------------------------------------------------------------------------
    function setTotalSupply(uint256 _newTotalSupply) public onlyAdministrator {
        totalSupply = _newTotalSupply;
        emit NewTotalSupply(_newTotalSupply);
     }

    function updateTotalSupply(uint256 _newTotalSupply) private {
        totalSupply = _newTotalSupply;
        emit NewTotalSupply(_newTotalSupply);
     }

    function setTotalCashSupply(uint256 _newTotalCashSupply) public onlyAdministrator {
        totalCashSupply = _newTotalCashSupply;
        emit NewTotalSupply(_newTotalCashSupply);
     }

    function balanceOf(address _tokenOwner) public view returns (uint256 balance) {
        return balances[_tokenOwner];
    }

    function setAllowance(address _from, address _spender, uint256 _tokens) public onlyPlatform {
        allowed[_from][_spender] = _tokens;
        emit SetAllowance(_from, _spender, _tokens);
    }

    function getAllowance(address _tokenOwner, address spender) public view returns (uint256 remaining) {
        return allowed[_tokenOwner][spender];
    }

// ----------------------------------------------------------------------------
// Setter/Getter functions for platform roles
// ----------------------------------------------------------------------------

    function setGovernanceContract(address _newGovernanceContractAddress) public onlyOwner {
        morpherGovernance = _newGovernanceContractAddress;
        emit GovernanceChange(_newGovernanceContractAddress);
    }

    function getGovernance() public view returns (address _governanceContract) {
        return morpherGovernance;
    }

    function setMorpherBridge(address _newBridge) public onlyOwner {
        morpherBridge = _newBridge;
        emit NewBridge(_newBridge);
    }

    function getMorpherBridge() public view returns (address _currentBridge) {
        return morpherBridge;
    }

    function setOracleContract(address _newOracleContract) public onlyGovernance {
        oracleContract = _newOracleContract;
        emit OracleChange(_newOracleContract);
    }

    function getOracleContract() public view returns(address) {
        return oracleContract;
    }

    function setTokenContract(address _newTokenContract) public onlyOwner {
        morpherToken = _newTokenContract;
        emit TokenChange(_newTokenContract);
    }

    function getTokenContract() public view returns(address) {
        return morpherToken;
    }

    function setAdministrator(address _newAdministrator) public onlyGovernance {
        administrator = _newAdministrator;
        emit AdministratorChange(_newAdministrator);
    }

    function getAdministrator() public view returns(address) {
        return administrator;
    }

// ----------------------------------------------------------------------------
// Setter/Getter functions for platform operating rewards
// ----------------------------------------------------------------------------

    function setRewardAddress(address _newRewardsAddress) public onlyOwner {
        morpherRewards = _newRewardsAddress;
        emit RewardsChange(_newRewardsAddress, rewardBasisPoints);
    }

    function setRewardBasisPoints(uint256 _newRewardBasisPoints) public onlyOwner {
        require(_newRewardBasisPoints <= 15000, "MorpherState: Reward basis points need to be less or equal to 15000.");
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

    function activateMarket(bytes32 _activateMarket) public onlyAdministrator {
        marketActive[_activateMarket] = true;
        emit MarketActivated(_activateMarket);
    }

    function deActivateMarket(bytes32 _deActivateMarket) public onlyAdministrator {
        marketActive[_deActivateMarket] = false;
        emit MarketDeActivated(_deActivateMarket);
    }

    function getMarketActive(bytes32 _marketId) public view returns(bool _active) {
        return marketActive[_marketId];
    }

    function setMaxLeverage(uint256 _newMaxLeverage) public onlyAdministrator {
        maxLeverage = _newMaxLeverage;
        emit MaxLeverageChange(_newMaxLeverage);
    }

    function getMaxLeverage() public view returns(uint256 _maxLeverage) {
        return maxLeverage;
    }

    function pauseState() public onlyAdministrator {
        paused = true;
        emit StatePaused(msg.sender);
    }

    function unPauseState() public onlyAdministrator {
        paused = false;
        emit StateUnPaused(msg.sender);
    }

// ----------------------------------------------------------------------------
// Setter/Getter for side chain state
// ----------------------------------------------------------------------------

    function setSideChainMerkleRoot(bytes32 _sideChainMerkleRoot) public onlyBridge {
        sideChainMerkleRoot = _sideChainMerkleRoot;
        sideChainMerkleRootWrittenAtTime = now;
        payOperatingReward;
        emit SideChainMerkleRootUpdate(_sideChainMerkleRoot, sideChainMerkleRootWrittenAtTime);
    }

    function getSideChainMerkleRoot() public view returns(bytes32 _sideChainMerkleRoot) {
        return sideChainMerkleRoot;
    }

    function setSideChainOperator(address _address) public onlyOwner {
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

    function setPosition(
        address _address,
        bytes32 _marketId,
        uint256 _timeStamp,
        uint256 _longShares,
        uint256 _shortShares,
        uint256 _meanEntryPrice,
        uint256 _meanEntrySpread,
        uint256 _meanEntryLeverage,
        uint256 _liquidationPrice
        ) public onlyPlatform {
        portfolio[_address][_marketId].lastUpdated = _timeStamp;
        portfolio[_address][_marketId].longShares = _longShares;
        portfolio[_address][_marketId].shortShares = _shortShares;
        portfolio[_address][_marketId].meanEntryPrice = _meanEntryPrice;
        portfolio[_address][_marketId].meanEntrySpread = _meanEntrySpread;
        portfolio[_address][_marketId].meanEntryLeverage = _meanEntryLeverage;
        portfolio[_address][_marketId].liquidationPrice = _liquidationPrice;
        portfolio[_address][_marketId].positionHash = getPositionHash(
            _address,
            _marketId,
            _timeStamp,
            _longShares,
            _shortShares,
            _meanEntryPrice,
            _meanEntrySpread,
            _meanEntryLeverage,
            _liquidationPrice
            );
        if (_longShares > 0 || _shortShares > 0) {
            addExposureByMarket(_marketId, _address);
        } else {
            deleteExposureByMarket(_marketId, _address);
        }
        emit SetPosition(portfolio[_address][_marketId].positionHash, _address, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice);
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
        return(
            portfolio[_address][_marketId].longShares,
            portfolio[_address][_marketId].shortShares,
            portfolio[_address][_marketId].meanEntryPrice,
            portfolio[_address][_marketId].meanEntrySpread,
            portfolio[_address][_marketId].meanEntryLeverage,
            portfolio[_address][_marketId].liquidationPrice
        );
    }

    function getPositionHash(
        address _address,
        bytes32 _marketId,
        uint256 _timeStamp,
        uint256 _longShares,
        uint256 _shortShares,
        uint256 _meanEntryPrice,
        uint256 _meanEntrySpread,
        uint256 _meanEntryLeverage,
        uint256 _liquidationPrice
        ) public pure returns (bytes32 _hash) {
        return keccak256(
            abi.encodePacked(
                _address,
                _marketId,
                _timeStamp,
                _longShares,
                _shortShares,
                _meanEntryPrice,
                _meanEntrySpread,
                _meanEntryLeverage,
                _liquidationPrice
                )
            );
    }

    function getBalanceHash(address _address, uint256 _balance) public pure returns (bytes32 _hash) {
        return keccak256(abi.encodePacked(_address, _balance));
    }

    function getLastUpdated(address _address, bytes32 _marketId) public view returns (uint256 _lastUpdated) {
        return(portfolio[_address][_marketId].lastUpdated);
    }

    function getLongShares(address _address, bytes32 _marketId) public view returns (uint256 _longShares) {
        return(portfolio[_address][_marketId].longShares);
    }

    function getShortShares(address _address, bytes32 _marketId) public view returns (uint256 _shortShares) {
        return(portfolio[_address][_marketId].shortShares);
    }

    function getMeanEntryPrice(address _address, bytes32 _marketId) public view returns (uint256 _meanEntryPrice) {
        return(portfolio[_address][_marketId].meanEntryPrice);
    }

    function getMeanEntrySpread(address _address, bytes32 _marketId) public view returns (uint256 _meanEntrySpread) {
        return(portfolio[_address][_marketId].meanEntrySpread);
    }

    function getMeanEntryLeverage(address _address, bytes32 _marketId) public view returns (uint256 _meanEntryLeverage) {
        return(portfolio[_address][_marketId].meanEntryLeverage);
    }

    function getLiquidationPrice(address _address, bytes32 _marketId) public view returns (uint256 _liquidationPrice) {
        return(portfolio[_address][_marketId].liquidationPrice);
    }

// ----------------------------------------------------------------------------
// Record positions by market by address. Needed for exposure aggregations
// and spits and dividends.
// ----------------------------------------------------------------------------
    function addExposureByMarket(bytes32 _symbol, address _address) private {
        // Address must not be already recored
        uint256 _myExposureIndex = getExposureMappingIndex(_symbol, _address);
        if (_myExposureIndex == 0) {
            uint256 _maxMappingIndex = getMaxMappingIndex(_symbol).add(1);
            setMaxMappingIndex(_symbol, _maxMappingIndex);
            setExposureMapping(_symbol, _address, _maxMappingIndex);
        }
    }

    function deleteExposureByMarket(bytes32 _symbol, address _address) private {
        // Get my index in mapping
        uint256 _myExposureIndex = getExposureMappingIndex(_symbol, _address);
        // Get last element of mapping
        uint256 _lastIndex = getMaxMappingIndex(_symbol);
        address _lastAddress = getExposureMappingAddress(_symbol, _lastIndex);
        // If _myExposureIndex is greater than 0 (i.e. there is an exposure of that address on that market) delete it
        if (_myExposureIndex > 0) {
        // If _myExposureIndex is less than _lastIndex overwrite element at _myExposureIndex with element at _lastIndex in
        // deleted elements position. 
            if (_myExposureIndex < _lastIndex) {
                setExposureMappingAddress(_symbol, _lastAddress, _myExposureIndex);
                setExposureMappingIndex(_symbol, _lastAddress, _myExposureIndex);
            } 
            // Delete _lastIndex and _lastAddress element and reduce maxExposureIndex
            setExposureMappingAddress(_symbol, address(0), _lastIndex);
            setExposureMappingIndex(_symbol, _address, 0);
            // Shouldn't happen, but check that not empty
            if (_lastIndex > 0) {
                setMaxMappingIndex(_symbol, _lastIndex.sub(1));
            }
        }
    }

// ----------------------------------------------------------------------------
// Calculate and send operating reward
// Every 24 hours the protocol mints rewardBasisPoints/(10**8) percent of the total 
// supply as reward for the protocol operator. The amount can not exceed 0.015% per
// day.
// ----------------------------------------------------------------------------

    function payOperatingReward() public returns(uint256 _reward) {
        if (now > lastRewardTime + 1 days) {
            _reward = totalSupply.div(PRECISION).mul(rewardBasisPoints);
            setLastRewardTime(lastRewardTime.add(1 days));
            mint(morpherRewards, _reward);
            updateTotalSupply(totalSupply.add(_reward));
        }
        return _reward;
    }
}
