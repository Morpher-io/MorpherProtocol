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

}
