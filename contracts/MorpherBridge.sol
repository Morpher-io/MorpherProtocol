// ------------------------------------------------------------------------
// MorpherBridge
// Handles deposit to and withdraws from the side chain, writing of the merkle
// root to the main chain by the side chain operator, and enforces a rolling 24 hours
// token withdraw limit from side chain to main chain.
// If side chain operator doesn't write a merkle root hash to main chain for more than
// 72 hours positions and balaces from side chain can be transferred to main chain.
// ------------------------------------------------------------------------
//SPDX-License-Identifier: GPLv3
pragma solidity 0.8.11;

import "./MorpherState.sol";
import "./MorpherUserBlocking.sol";
import "./MorpherAccessControl.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "./MorpherTradeEngine.sol";

contract MorpherBridge is Initializable, ContextUpgradeable {

    MorpherState state;
    MorpherBridge previousBridge;

    mapping(address => mapping(uint256 => uint256)) public withdrawalPerDay; //[address][day] = withdrawalAmount
    mapping(address => mapping(uint256 => uint256)) public withdrawalPerMonth; //[address][month] = withdrawalAmount
    mapping(address => mapping(uint256 => uint256)) public withdrawalPerYear; //[address][year] = withdrawalAmount

    uint256 public withdrawalLimitDaily = 200000 * (10**18); //200k MPH per day
    uint256 public withdrawalLimitMonthly = 1000000 * (10 ** 18); //1M MPH per month
    uint256 public withdrawalLimitYearly = 5000000 * (10 ** 18); //5M MPH per year

    bytes32 public constant ADMINISTRATOR_ROLE = keccak256("ADMINISTRATOR_ROLE");
    bytes32 public constant SIDECHAINOPERATOR_ROLE = keccak256("SIDECHAINOPERATOR_ROLE");


    bool public recoveryEnabled;

    event TransferToLinkedChain(
        address indexed from,
        uint256 tokens,
        uint256 totalTokenSent,
        uint256 timeStamp,
        uint256 transferNonce,
        bytes32 indexed transferHash
    );
    event TrustlessWithdrawFromSideChain(address indexed from, uint256 tokens);
    event OperatorChainTransfer(address indexed from, uint256 tokens, bytes32 sidechainTransactionHash);
    event ClaimFailedTransferToSidechain(address indexed from, uint256 tokens);
    event PositionRecoveryFromSideChain(address indexed from, bytes32 positionHash);
    event TokenRecoveryFromSideChain(address indexed from, bytes32 positionHash);
    event SideChainMerkleRootUpdated(bytes32 _rootHash);
    event WithdrawLimitReset();
    event WithdrawLimitChanged(uint256 _withdrawLimit);
    event WithdrawLimitDailyChanged(uint256 _oldLimit, uint256 _newLimit);
    event WithdrawLimitMonthlyChanged(uint256 _oldLimit, uint256 _newLimit);
    event WithdrawLimitYearlyChanged(uint256 _oldLimit, uint256 _newLimit);
    event LinkState(address _address);
    event LinkMorpherUserBlocking(address _address);

    function initialize(address _stateAddress, bool _recoveryEnabled) public initializer {
        state = MorpherState(_stateAddress);
        recoveryEnabled = _recoveryEnabled;

    }

    modifier onlySideChainOperator {
        require(_msgSender() == state.getSideChainOperator(), "MorpherBridge: Function can only be called by Sidechain Operator.");
        _;
    }

    modifier sideChainInactive {
        require(block.timestamp - state.inactivityPeriod() > state.getSideChainMerkleRootWrittenAtTime(), "MorpherBridge: Function can only be called if sidechain is inactive.");
        _;
    }
    
    modifier fastTransfers {
        require(state.fastTransfersEnabled() == true, "MorpherBridge: Fast transfers have been disabled permanently.");
        _;
    }

    modifier onlyRecoveryEnabled() {
        require(recoveryEnabled, "MorpherBridge: Recovery functions are not enabled");
        _;
    }

    modifier userNotBlocked {
        require(!MorpherUserBlocking(state.morpherUserBlockingAddress()).userIsBlocked(_msgSender()), "MorpherBridge: User is blocked");
        _;
    }

    modifier onlyRole(bytes32 role) {
        require(MorpherAccessControl(state.morpherAccessControlAddress()).hasRole(role, _msgSender()), "MorpherTradeEngine: Permission denied.");
        _;
    }
    
    // ------------------------------------------------------------------------
    // Links Token Contract with State
    // ------------------------------------------------------------------------
    function setMorpherState(address _stateAddress) public onlyRole(ADMINISTRATOR_ROLE) {
        state = MorpherState(_stateAddress);
        emit LinkState(_stateAddress);
    }


    function setInactivityPeriod(uint256 _periodInSeconds) private {
        state.setInactivityPeriod(_periodInSeconds);
    }

    function disableFastTransfers() public onlyRole(ADMINISTRATOR_ROLE)  {
        state.disableFastWithdraws();
    }

    function updateSideChainMerkleRoot(bytes32 _rootHash) public onlyRole(SIDECHAINOPERATOR_ROLE) {
        state.setSideChainMerkleRoot(_rootHash);
        emit SideChainMerkleRootUpdated(_rootHash);
    }

    function resetLast24HoursAmountWithdrawn() public onlyRole(SIDECHAINOPERATOR_ROLE) {
        state.resetLast24HoursAmountWithdrawn();
        emit WithdrawLimitReset();
    }

    function set24HourWithdrawLimit(uint256 _withdrawLimit) public onlyRole(SIDECHAINOPERATOR_ROLE) {
        state.set24HourWithdrawLimit(_withdrawLimit);
        emit WithdrawLimitChanged(_withdrawLimit);
    }

    function updateWithdrawLimitDaily(uint256 _withdrawLimit) public onlyRole(SIDECHAINOPERATOR_ROLE) {
        emit WithdrawLimitDailyChanged(withdrawalLimitDaily, _withdrawLimit);
        withdrawalLimitDaily = _withdrawLimit;
    }

    function updateWithdrawLimitMonthly(uint256 _withdrawLimit) public onlyRole(SIDECHAINOPERATOR_ROLE) {
        emit WithdrawLimitMonthlyChanged(withdrawalLimitMonthly, _withdrawLimit);
        withdrawalLimitMonthly = _withdrawLimit;
    }
    function updateWithdrawLimitYearly(uint256 _withdrawLimit) public onlyRole(SIDECHAINOPERATOR_ROLE) {
        emit WithdrawLimitYearlyChanged(withdrawalLimitYearly, _withdrawLimit);
        withdrawalLimitYearly = _withdrawLimit;
    }

    function getTokenSentToLinkedChain(address _address) public view returns (uint256 _token) {
        return state.getTokenSentToLinkedChain(_address);
    }

    function getTokenClaimedOnThisChain(address _address) public view returns (uint256 _token)  {
        return state.getTokenClaimedOnThisChain(_address);
    }

    function getTokenSentToLinkedChainTime(address _address) public view returns (uint256 _time)  {
        return state.getTokenSentToLinkedChainTime(_address);
    }

    // ------------------------------------------------------------------------
    // verifyWithdrawOk(uint256 _amount)
    // Checks if creating _amount token on main chain does not violate the 24 hour transfer limit
    // ------------------------------------------------------------------------
    function verifyWithdrawOk(uint256 _amount) public returns (bool _authorized) {
        uint256 _lastWithdrawLimitReductionTime = state.lastWithdrawLimitReductionTime();
        uint256 _withdrawLimit24Hours = state.withdrawLimit24Hours();
        
        if (block.timestamp > _lastWithdrawLimitReductionTime) {
            uint256 _timePassed = block.timestamp - _lastWithdrawLimitReductionTime;
            state.update24HoursWithdrawLimit(_timePassed * _withdrawLimit24Hours / 1 days);
        }
        
        if (state.last24HoursAmountWithdrawn() + _amount <= _withdrawLimit24Hours) {
            return true;
        } else {
            return false;
        }
    }

    function isNotDailyLimitExceeding(uint256 _amount) public view returns(bool) {
        return (getWithdrawalPerDay(_msgSender()) + _amount <= withdrawalLimitDaily);
    }
    function isNotMonthlyLimitExceeding(uint256 _amount) public view returns(bool) {
        return (getWithdrawalPerMonth(_msgSender()) + _amount <= withdrawalLimitMonthly);
    }
    function isNotYearlyLimitExceeding(uint256 _amount) public view returns(bool) {
        return (getWithdrawalPerYear(_msgSender()) + _amount <= withdrawalLimitYearly);
    }

    function verifyUpdateDailyLimit(uint256 _amount) public {
        require(isNotDailyLimitExceeding(_amount), "MorpherBridge: Withdrawal Amount exceeds daily limit");
        withdrawalPerDay[_msgSender()][block.timestamp / 1 days] = getWithdrawalPerDay(_msgSender()) + _amount;
    }

    function verifyUpdateMonthlyLimit(uint256 _amount) public {
        require(isNotMonthlyLimitExceeding(_amount), "MorpherBridge: Withdrawal Amount exceeds monthly limit");
        withdrawalPerMonth[_msgSender()][block.timestamp / 30 days] = getWithdrawalPerMonth(_msgSender()) + _amount;
    }

    function verifyUpdateYearlyLimit(uint256 _amount) public {
        require(isNotYearlyLimitExceeding(_amount), "MorpherBridge: Withdrawal Amount exceeds yearly limit");
        withdrawalPerYear[_msgSender()][block.timestamp / 365 days] = getWithdrawalPerYear(_msgSender()) + _amount;
    }

    function getWithdrawalPerDay(address _user) public view returns(uint) {
         if(address(previousBridge) != address(0) && withdrawalPerDay[_user][block.timestamp / 1 days] == 0) {
           return previousBridge.withdrawalPerDay(_user, block.timestamp / 1 days); //if bridge is re-deployed this needs to change to previousBridge.getWithdrawalPerDay
        }
        return withdrawalPerDay[_user][block.timestamp / 1 days];
    }
    function getWithdrawalPerMonth(address _user) public view returns(uint) {
         if(address(previousBridge) != address(0) && withdrawalPerMonth[_user][block.timestamp / 30 days] == 0) {
            return previousBridge.withdrawalPerMonth(_user, block.timestamp / 30 days); //if bridge is re-deployed this needs to change to previousBridge.getWithdrawalPerDay
        }
        return withdrawalPerMonth[_user][block.timestamp / 30 days];
    }
    function getWithdrawalPerYear(address _user) public view returns(uint) {
         if(address(previousBridge) != address(0) && withdrawalPerYear[_user][block.timestamp / 365 days] == 0) {
            return previousBridge.withdrawalPerYear(_user, block.timestamp / 365 days); //if bridge is re-deployed this needs to change to previousBridge.getWithdrawalPerDay
        }
        return withdrawalPerYear[_user][block.timestamp / 365 days];
    }

    // ------------------------------------------------------------------------
    // transferToSideChain(uint256 _tokens)
    // Transfer token to Morpher's side chain to trade without fees and near instant
    // settlement.
    // - Owner's account must have sufficient balance to transfer
    // - 0 value transfers are not supported
    // Token are burned on the main chain and are created and credited to msg.sender
    //  on the side chain
    // ------------------------------------------------------------------------
    function transferToSideChain(uint256 _tokens) public userNotBlocked {
        require(_tokens >= 0, "MorpherBridge: Amount of tokens must be positive.");
        require(MorpherToken(state.morpherTokenAddress()).balanceOf(_msgSender()) >= _tokens, "MorpherBridge: Insufficient balance.");
        verifyUpdateDailyLimit(_tokens);
        verifyUpdateMonthlyLimit(_tokens);
        verifyUpdateYearlyLimit(_tokens);
        MorpherToken(state.morpherTokenAddress()).burn(_msgSender(), _tokens);
        uint256 _newTokenSentToLinkedChain = getTokenSentToLinkedChain(_msgSender()) + _tokens;
        uint256 _transferNonce = state.getBridgeNonce();
        uint256 _timeStamp = block.timestamp;
        bytes32 _transferHash = keccak256(
            abi.encodePacked(
                _msgSender(),
                _tokens,
                _newTokenSentToLinkedChain,
                _timeStamp,
                _transferNonce
            )
        );
        state.setTokenSentToLinkedChain(_msgSender(), _newTokenSentToLinkedChain);
        emit TransferToLinkedChain(_msgSender(), _tokens, _newTokenSentToLinkedChain, _timeStamp, _transferNonce, _transferHash);
    }

    // ------------------------------------------------------------------------
    // fastTransferFromSideChain(uint256 _numOfToken, uint256 _tokenBurnedOnLinkedChain, bytes32[] memory _proof)
    // The sidechain operator can credit users with token they burend on the sidechain. Transfers
    // happen immediately. To be removed after Beta.
    // ------------------------------------------------------------------------
    function fastTransferFromSideChain(address _address, uint256 _numOfToken, uint256 _tokenBurnedOnLinkedChain, bytes32 _sidechainTransactionHash) public onlyRole(SIDECHAINOPERATOR_ROLE) fastTransfers {
        uint256 _tokenClaimed = state.getTokenClaimedOnThisChain(_address);
        require(verifyWithdrawOk(_numOfToken), "MorpherBridge: Withdraw amount exceeds permitted 24 hour limit. Please try again in a few hours.");
        require(_tokenClaimed + _numOfToken <= _tokenBurnedOnLinkedChain, "MorpherBridge: Token amount exceeds token deleted on linked chain.");
        _chainTransfer(_address, _tokenClaimed, _numOfToken);
        emit OperatorChainTransfer(_address, _numOfToken, _sidechainTransactionHash);
    }
    
    // ------------------------------------------------------------------------
    // trustlessTransferFromSideChain(uint256 _numOfToken, uint256 _claimLimit, bytes32[] memory _proof)
    // Performs a merkle proof on the number of token that have been burned by the user on the side chain.
    // If the number of token claimed on the main chain is less than the number of burned token on the side chain
    // the difference (or less) can be claimed on the main chain.
    // ------------------------------------------------------------------------
    function trustlessTransferFromLinkedChain(uint256 _numOfToken, uint256 _claimLimit, bytes32[] memory _proof) public userNotBlocked {
        bytes32 leaf = keccak256(abi.encodePacked(_msgSender(), _claimLimit));
        uint256 _tokenClaimed = state.getTokenClaimedOnThisChain(_msgSender());        
        require(mProof(_proof, leaf), "MorpherBridge: Merkle Proof failed. Please make sure you entered the correct claim limit.");
        require(verifyWithdrawOk(_numOfToken), "MorpherBridge: Withdraw amount exceeds permitted 24 hour limit. Please try again in a few hours.");
        verifyUpdateDailyLimit(_numOfToken);
        verifyUpdateMonthlyLimit(_numOfToken);
        verifyUpdateYearlyLimit(_numOfToken);
        require(_tokenClaimed + _numOfToken <= _claimLimit, "MorpherBridge: Token amount exceeds token deleted on linked chain.");     
        _chainTransfer(_msgSender(), _tokenClaimed, _numOfToken);   
        emit TrustlessWithdrawFromSideChain(_msgSender(), _numOfToken);
    }
    
    // ------------------------------------------------------------------------
    // _chainTransfer(address _address, uint256 _tokenClaimed, uint256 _numOfToken)
    // Creates token on the chain for the user after proving their distruction on the 
    // linked chain has been proven before 
    // ------------------------------------------------------------------------
    function _chainTransfer(address _address, uint256 _tokenClaimed, uint256 _numOfToken) private {
        state.setTokenClaimedOnThisChain(_address, _tokenClaimed + _numOfToken);
        state.add24HoursWithdrawn(_numOfToken);
        MorpherToken(state.morpherTokenAddress()).mint(_address, _numOfToken);
    }
        
    // ------------------------------------------------------------------------
    // claimFailedTransferToSidechain(uint256 _wrongSideChainBalance, bytes32[] memory _proof)
    // If token sent to side chain were not credited to the user on the side chain within inactivityPeriod
    // they can reclaim the token on the main chain by submitting the proof that their
    // side chain balance is less than the number of token sent from main chain.
    // ------------------------------------------------------------------------
    function claimFailedTransferToSidechain(uint256 _wrongSideChainBalance, bytes32[] memory _proof) public userNotBlocked {
        bytes32 leaf = keccak256(abi.encodePacked(_msgSender(), _wrongSideChainBalance));
        uint256 _tokenSentToLinkedChain = getTokenSentToLinkedChain(_msgSender());
        uint256 _tokenSentToLinkedChainTime = getTokenSentToLinkedChainTime(_msgSender());
        uint256 _inactivityPeriod = state.inactivityPeriod();
        
        require(block.timestamp > _tokenSentToLinkedChainTime + _inactivityPeriod, "MorpherBridge: Failed deposits can only be claimed after inactivity period.");
        require(_wrongSideChainBalance < _tokenSentToLinkedChain, "MorpherBridge: Other chain credit is greater equal to wrongSideChainBalance.");
        require(verifyWithdrawOk(_tokenSentToLinkedChain - _wrongSideChainBalance), "MorpherBridge: Claim amount exceeds permitted 24 hour limit.");
        require(mProof(_proof, leaf), "MorpherBridge: Merkle Proof failed. Enter total amount of deposits on side chain.");
        
        uint256 _claimAmount = _tokenSentToLinkedChain - _wrongSideChainBalance;
        state.setTokenSentToLinkedChain(_msgSender(), _tokenSentToLinkedChain - _claimAmount);
        state.add24HoursWithdrawn(_claimAmount);
        MorpherToken(state.morpherTokenAddress()).mint(_msgSender(), _claimAmount);
        emit ClaimFailedTransferToSidechain(_msgSender(), _claimAmount);
    }

    // ------------------------------------------------------------------------
    // recoverPositionFromSideChain(bytes32[] memory _proof, bytes32 _leaf, bytes32 _marketId, uint256 _timeStamp, uint256 _longShares, uint256 _shortShares, uint256 _meanEntryPrice, uint256 _meanEntrySpread, uint256 _meanEntryLeverage)
    // Failsafe against side chain operator becoming inactive or withholding Times (Time withhold attack).
    // After 72 hours of no update of the side chain merkle root users can withdraw their last recorded
    // positions from side chain to main chain. Overwrites eventually existing position on main chain.
    // ------------------------------------------------------------------------
    function recoverPositionFromSideChain(
        bytes32[] memory _proof,
        bytes32 _leaf,
        bytes32 _marketId,
        uint256 _timeStamp,
        uint256 _longShares,
        uint256 _shortShares,
        uint256 _meanEntryPrice,
        uint256 _meanEntrySpread,
        uint256 _meanEntryLeverage,
        uint256 _liquidationPrice
        ) public sideChainInactive userNotBlocked onlyRecoveryEnabled {
        require(_leaf == MorpherTradeEngine(state.morpherTradeEngineAddress()).getPositionHash(_msgSender(), _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice), "MorpherBridge: leaf does not equal position hash.");
        require(state.getPositionClaimedOnMainChain(_leaf) == false, "MorpherBridge: Position already transferred.");
        require(mProof(_proof,_leaf) == true, "MorpherBridge: Merkle proof failed.");
        state.setPositionClaimedOnMainChain(_leaf);
        MorpherTradeEngine(state.morpherTradeEngineAddress()).setPosition(_msgSender(), _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice);
        emit PositionRecoveryFromSideChain(_msgSender(), _leaf);
        // Remark: After resuming operations side chain operator has 72 hours to sync and eliminate transferred positions on side chain to avoid double spend
    }

    // ------------------------------------------------------------------------
    // recoverTokenFromSideChain(bytes32[] memory _proof, bytes32 _leaf, bytes32 _marketId, uint256 _timeStamp, uint256 _longShares, uint256 _shortShares, uint256 _meanEntryPrice, uint256 _meanEntrySpread, uint256 _meanEntryLeverage)
    // Failsafe against side chain operator becoming inactive or withholding times (time withhold attack).
    // After 72 hours of no update of the side chain merkle root users can withdraw their last recorded
    // token balance from side chain to main chain.
    // ------------------------------------------------------------------------
    function recoverTokenFromSideChain(bytes32[] memory _proof, bytes32 _leaf, uint256 _balance) public sideChainInactive userNotBlocked onlyRecoveryEnabled {
        // Require side chain root hash not set on Mainchain for more than 72 hours (=3 days)
        require(_leaf == state.getBalanceHash(_msgSender(), _balance), "MorpherBridge: Wrong balance.");
        require(state.getPositionClaimedOnMainChain(_leaf) == false, "MorpherBridge: Token already transferred.");
        require(mProof(_proof,_leaf) == true, "MorpherBridge: Merkle proof failed.");
        require(verifyWithdrawOk(_balance), "MorpherBridge: Withdraw amount exceeds permitted 24 hour limit.");
        state.setPositionClaimedOnMainChain(_leaf);
        _chainTransfer(_msgSender(), state.getTokenClaimedOnThisChain(_msgSender()), _balance);
        emit TokenRecoveryFromSideChain(_msgSender(), _leaf);
        // Remark: Side chain operator must adjust side chain balances for token recoveries before restarting operations to avoid double spend
    }

    // ------------------------------------------------------------------------
    // mProof(bytes32[] memory _proof, bytes32 _leaf)
    // Computes merkle proof against the root hash of the sidechain stored in Morpher state
    // ------------------------------------------------------------------------
    function mProof(bytes32[] memory _proof, bytes32 _leaf) public view returns(bool _isTrue) {
        return MerkleProofUpgradeable.verify(_proof, state.getSideChainMerkleRoot(), _leaf);
    }
}
