// ------------------------------------------------------------------------
// MorpherBridge
// Handles deposit to and withdraws from the side chain, writing of the merkle
// root to the main chain by the side chain operator, and enforces a rolling 24 hours
// token withdraw limit from side chain to main chain.
// If side chain operator doesn't write a merkle root hash to main chain for more than
// 72 hours positions and balaces from side chain can be transferred to main chain.
// ------------------------------------------------------------------------

pragma solidity 0.5.16;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./MorpherState.sol";
import "./MerkleProof.sol";

contract MorpherBridge is Ownable {

    MorpherState state;
    using SafeMath for uint256;
    uint256 public constant DECIMALS = 18;

    event TransferToLinkedChain(address indexed from, uint256 tokens, uint256 totalTokenSent, uint256 indexed timestamp, uint256 _transferNonce, bytes32 indexed _transferHash);
    event TrustlessWithdrawFromSideChain(address indexed from, uint256 tokens, uint256 indexed timestamp);
    event FastWithdrawFromSideChain(address indexed from, uint256 tokens, bytes32 sidechainTransactionHash, uint256 indexed timestamp);
    event ClaimFailedTransferToSidechain(address indexed from, uint256 tokens, uint256 indexed timestamp);
    event PositionRecoveryFromSideChain(address indexed from, bytes32 positionHash, uint256 indexed timestamp);
    event TokenRecoveryFromSideChain(address indexed from, bytes32 positionHash, uint256 indexed timestamp);
    event SideChainMerkleRootUpdated(bytes32 _rootHash, uint256 indexed timestamp);
    event WithdrawLimitReset(uint256 indexed timestamp);
    event WithdrawLimitChanged(uint256 _withdrawLimit, uint256 indexed timestamp);

    constructor(address _stateAddress) public {
        setMorpherState(_stateAddress);
        if (state.mainChain() == false) {
            // Set initial withdraw limit from sidechain to 20m token or 2% of initial supply            
            set24HourWithdrawLimit(20000000 * 10**DECIMALS);
        } else {
            // Set initial withdraw limit from mainchain to 100m token or 10% of initial supply
            set24HourWithdrawLimit(100000000 * 10**DECIMALS);
        }
        state.setInactivityPeriod(3 days);
    }

    modifier onlySideChainOperator {
        require(msg.sender == state.getSideChainOperator(), "MorpherBridge: Function can only be called by Sidechain Operator.");
        _;
    }

    modifier sideChainInactive {
        require(now - state.inactivityPeriod() > state.getSideChainMerkleRootWrittenAtTime(), "MorpherBridge: Function can only be called if sidechain is inactive.");
        _;
    }
    
    modifier fastTransfers {
        require(state.fastTransfersEnabled() == true, "MorpherBridge: Fast transfers have been disabled permanently.");
        _;
    }
    
    modifier onlySidechain {
        require(state.mainChain() == false, "MorpherBridge: Function can only be executed on sidechain." );
        _;
    }
    
    modifier onlyMainchain {
        require(state.mainChain() == true, "MorpherBridge: Function can only be executed on Ethereum." );
        _;
    }
    
    function setMorpherState(address _stateAddress) public onlyOwner {
        state = MorpherState(_stateAddress);
    }

    function setInactivityPeriod(uint256 _periodInSeconds) public onlyOwner {
        state.setInactivityPeriod(_periodInSeconds);
    }

    function disableFastTranfers() public onlyOwner  {
        state.disableFastWithdraws();
    }

    // ------------------------------------------------------------------------
    // checkWithdrawOk(uint256 _amount)
    // Checks if creating _amount token on main chain does not violate the 24 hour transfer limit
    // ------------------------------------------------------------------------
    function checkWithdrawOk(uint256 _amount) public returns (bool _authorized) {
        uint256 _lastWithdrawLimitReductionTime = state.lastWithdrawLimitReductionTime();
        uint256 _withdrawLimit24Hours = state.withdrawLimit24Hours();
        
        if (now > _lastWithdrawLimitReductionTime) {
            uint256 _timePassed = now.sub(_lastWithdrawLimitReductionTime);
            state.update24HoursWithdrawLimit(_timePassed.mul(_withdrawLimit24Hours).div(1 days));
        }
        
        if (state.last24HoursAmountWithdrawn().add(_amount) <= _withdrawLimit24Hours) {
            return true;
        } else {
            return false;
        }
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
    function transferToSideChain(uint256 _tokens) public {
        require(_tokens >= 0, "MorpherBridge: Amount of tokens must be positive.");
        require(state.balanceOf(msg.sender) >= _tokens, "MorpherBridge: Insufficient balance.");
        state.burn(msg.sender, _tokens);
        uint256 _newTokenSentToLinkedChain = state.getTokenSentToLinkedChain(msg.sender).add(_tokens);
        uint256 _transferNonce = state.getBridgeNonce();
        bytes32 _transferHash = keccak256(
            abi.encodePacked(
                msg.sender,
                _tokens,
                _newTokenSentToLinkedChain,
                now,
                _transferNonce
            )
        );
        state.setTokenSentToLinkedChain(msg.sender, _newTokenSentToLinkedChain);
        emit TransferToLinkedChain(msg.sender, _tokens, _newTokenSentToLinkedChain, now, _transferNonce, _transferHash);
    }

    // ------------------------------------------------------------------------
    // claimFailedTransferToSidechain(uint256 _wrongSideChainBalance, bytes32[] memory _proof)
    // If token sent to side chain were not credited to the user on the side chain within inactivityPeriod
    // they can reclaim the token on the main chain by submitting the proof that their
    // side chain balance is less than the number of token sent from main chain.
    // ------------------------------------------------------------------------
    function claimFailedTransferToSidechain(uint256 _wrongSideChainBalance, bytes32[] memory _proof) public {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, _wrongSideChainBalance));
        uint256 _tokenSentToLinkedChain = state.getTokenSentToLinkedChain(msg.sender);
        uint256 _tokenSentToLinkedChainTime = state.getTokenSentToLinkedChainTime(msg.sender);
        uint256 _inactivityPeriod = state.inactivityPeriod();
        
        require(now > _tokenSentToLinkedChainTime.add(_inactivityPeriod), "MorpherBridge: Failed deposits can only be claimed after inactivity period.");
        require(_wrongSideChainBalance < _tokenSentToLinkedChain, "MorpherBridge: Other chain credit is greater equal to wrongSideChainBalance.");
        require(checkWithdrawOk(_tokenSentToLinkedChain.sub(_wrongSideChainBalance)), "MorpherBridge: Claim amount exceeds permitted 24 hour limit.");
        require(mProof(_proof, leaf), "MorpherBridge: Merkle Proof failed. Enter total amount of deposits on side chain.");
        
        uint256 _claimAmount = _tokenSentToLinkedChain.sub(_wrongSideChainBalance);
        state.setTokenSentToLinkedChain(msg.sender, _tokenSentToLinkedChain.sub(_claimAmount));
        state.add24HoursWithdrawn(_claimAmount);
        state.mint(msg.sender, _claimAmount);
        emit ClaimFailedTransferToSidechain(msg.sender, _claimAmount, now);
    }

    // ------------------------------------------------------------------------
    // trustlessTransferFromSideChain(uint256 _numOfToken, uint256 _claimLimit, bytes32[] memory _proof)
    // Performs a merkle proof on the number of token that have been burned by the user on the side chain.
    // If the number of token claimed on the main chain is less than the number of burned token on the side chain
    // the difference (or less) can be claimed on the main chain.
    // ------------------------------------------------------------------------
    function trustlessTransferFromSideChain(uint256 _numOfToken, uint256 _claimLimit, bytes32[] memory _proof) public {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, _claimLimit));
        uint256 _tokenClaimed = state.getTokenClaimedOnThisChain(msg.sender);        
        require(mProof(_proof, leaf), "MorpherBridge: Merkle Proof failed. Please make sure you entered the correct claim limit.");
        require(checkWithdrawOk(_numOfToken), "MorpherBridge: Withdraw amount exceeds permitted 24 hour limit. Please try again in a few hours.");
        require(_tokenClaimed.add(_numOfToken) <= _claimLimit, "MorpherBridge: Token amount exceeds token deleted on linked chain.");     
        _transfer(msg.sender, _tokenClaimed, _numOfToken);   
        emit TrustlessWithdrawFromSideChain(msg.sender, _numOfToken, now);
    }
    
    // ------------------------------------------------------------------------
    // fastTransferFromSideChain(uint256 _numOfToken, uint256 _claimLimit, bytes32[] memory _proof)
    // The sidechain operator can credit users with token they burend on the sidechain. Transfers
    // happen immediately. To be removed after Beta.
    // ------------------------------------------------------------------------
    function fastTransferFromSideChain(address _address, uint256 _numOfToken, uint256 _claimLimit, bytes32 _sidechainTransactionHash) public onlySideChainOperator fastTransfers {
        uint256 _tokenClaimed = state.getTokenClaimedOnThisChain(msg.sender);
        require(checkWithdrawOk(_numOfToken), "MorpherBridge: Withdraw amount exceeds permitted 24 hour limit. Please try again in a few hours.");
        require(_tokenClaimed.add(_numOfToken) <= _claimLimit, "MorpherBridge: Token amount exceeds token deleted on linked chain.");
        _transfer(msg.sender, _tokenClaimed, _numOfToken);
        emit FastWithdrawFromSideChain(_address, _numOfToken, _sidechainTransactionHash, now);
    }
    
    function _transfer(address _address, uint256 _tokenClaimed, uint256 _numOfToken) private {
        state.setTokenClaimedOnThisChain(_address, _tokenClaimed.add(_numOfToken));
        state.add24HoursWithdrawn(_numOfToken);
        state.mint(_address, _numOfToken);
    }
        
    function totalTokenSentToLinkedChain(address _address) public view returns (uint256 _numOfToken) {
        return state.getTokenSentToLinkedChainTime(_address);
    }

    function totalTokenClaimedOnThisChain(address _address) public view returns (uint256 _numOfToken) {
        return state.getTokenClaimedOnThisChain(_address);
    }

    function updateSideChainMerkleRoot(bytes32 _rootHash) public onlyOwner {
        state.setSideChainMerkleRoot(_rootHash);
        emit SideChainMerkleRootUpdated(_rootHash, now);
    }

    function resetLast24HoursAmountWithdrawn() public onlyOwner {
        state.resetLast24HoursAmountWithdrawn();
        emit WithdrawLimitReset(now);
    }

    function set24HourWithdrawLimit(uint256 _withdrawLimit) public onlyOwner {
        state.setWithdrawLimit(_withdrawLimit);
        emit WithdrawLimitChanged(_withdrawLimit, now);
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
        ) public sideChainInactive onlyMainchain {
        require(_leaf == state.getPositionHash(msg.sender, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice));
        require(state.getPositionClaimedOnMainChain(_leaf) == false, "MorpherBridge: Position already transferred.");
        require(mProof(_proof,_leaf) == true, "MorpherBridge: Merkle proof failed.");
        state.setPositionClaimedOnMainChain(_leaf);
        state.setPosition(msg.sender, _marketId, _timeStamp, _longShares, _shortShares, _meanEntryPrice, _meanEntrySpread, _meanEntryLeverage, _liquidationPrice);
        emit PositionRecoveryFromSideChain(msg.sender, _leaf, now);
        // Remark: After resuming operations side chain operator has 72 hours to sync and eliminate transferred positions on side chain to avoid double spend
    }

    // ------------------------------------------------------------------------
    // recoverTokenFromSideChain(bytes32[] memory _proof, bytes32 _leaf, bytes32 _marketId, uint256 _timeStamp, uint256 _longShares, uint256 _shortShares, uint256 _meanEntryPrice, uint256 _meanEntrySpread, uint256 _meanEntryLeverage)
    // Failsafe against side chain operator becoming inactive or withholding times (time withhold attack).
    // After 72 hours of no update of the side chain merkle root users can withdraw their last recorded
    // token balance from side chain to main chain.
    // ------------------------------------------------------------------------
    function recoverTokenFromSideChain(bytes32[] memory _proof, bytes32 _leaf, uint256 _balance) public sideChainInactive onlyMainchain {
        // Require side chain root hash not set on Mainchain for more than 72 hours (=3 days)
        require(_leaf == state.getBalanceHash(msg.sender, _balance), "MorpherBridge: Wrong balance.");
        require(state.getPositionClaimedOnMainChain(_leaf) == false, "MorpherBridge: Token already transferred.");
        require(mProof(_proof,_leaf) == true, "MorpherBridge: Merkle proof failed.");
        require(checkWithdrawOk(_balance), "MorpherBridge: Withdraw amount exceeds permitted 24 hour limit.");
        state.setPositionClaimedOnMainChain(_leaf);
        _transfer(msg.sender, state.getTokenClaimedOnThisChain(msg.sender), _balance);
        emit TokenRecoveryFromSideChain(msg.sender, _leaf, now);
        // Remark: Side chain operator must adjust side chain balances for token recoveries before restarting operations to avoid double spend
    }

    // ------------------------------------------------------------------------
    // mProof(bytes32[] memory _proof, bytes32 _leaf)
    // Computes merkle proof against the root hash of the sidechain stored in Morpher state
    // ------------------------------------------------------------------------
    function mProof(bytes32[] memory _proof, bytes32 _leaf) public view returns(bool _isTrue) {
        _isTrue = MerkleProof.verify(_proof, state.getSideChainMerkleRoot(), _leaf);
        return _isTrue;
    }
}
