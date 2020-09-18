pragma solidity 0.5.16;

interface IMorpherState {
    function getPosition(address _address, bytes32 _marketId)
        external
        view
        returns (
            uint256 _longShares,
            uint256 _shortShares,
            uint256 _meanEntryPrice,
            uint256 _meanEntrySpread,
            uint256 _meanEntryLeverage,
            uint256 _liquidationPrice
        );

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
    ) external;
}
