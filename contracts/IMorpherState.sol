pragma solidity 0.5.16;

contract IMorpherState {
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
    ) public; 

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
    );

    function getLastUpdated(address _address, bytes32 _marketId) public view returns (uint256 _lastUpdated);

    function transfer(address _from, address _to, uint256 _token) public;
    
    function balanceOf(address _tokenOwner) public view returns (uint256 balance);

    function mint(address _address, uint256 _token) public;

    function burn(address _address, uint256 _token) public;

     function getSideChainOperator() public view returns (address _address);

    function inactivityPeriod() public view returns (uint256);

    function getSideChainMerkleRootWrittenAtTime() public view returns(uint256 _sideChainMerkleRoot);

    function fastTransfersEnabled() public view returns(bool);

    function mainChain() public view returns(bool);

    function setInactivityPeriod(uint256 _periodLength) public;

    function disableFastWithdraws() public;

    function setSideChainMerkleRoot(bytes32 _sideChainMerkleRoot) public;

    function resetLast24HoursAmountWithdrawn() public;

    function set24HourWithdrawLimit(uint256 _limit) public;

    function getTokenSentToLinkedChain(address _address) public view returns (uint256 _token);

    function getTokenClaimedOnThisChain(address _address) public view returns (uint256 _token);

    function getTokenSentToLinkedChainTime(address _address) public view returns (uint256 _timeStamp);

    function lastWithdrawLimitReductionTime() public view returns (uint256);

    function withdrawLimit24Hours() public view returns (uint256);

    function update24HoursWithdrawLimit(uint256 _amount) public;

    function last24HoursAmountWithdrawn() public view returns (uint256);

    function setTokenSentToLinkedChain(address _address, uint256 _token) public;

    function setTokenClaimedOnThisChain(address _address, uint256 _token) public;

    function add24HoursWithdrawn(uint256 _amount) public;

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
    ) public pure returns (bytes32 _hash);

    function getPositionClaimedOnMainChain(bytes32 _positionHash) public view returns (bool _alreadyClaimed);

    function setPositionClaimedOnMainChain(bytes32 _positionHash) public;

     function getBalanceHash(address _address, uint256 _balance) public pure returns (bytes32 _hash);

     function getSideChainMerkleRoot() public view returns(bytes32 _sideChainMerkleRoot);

     function getBridgeNonce() public returns (uint256 _nonce);
}