pragma solidity 0.5.16;
contract IMorpherStaking {
    
    function lastReward() public view returns (uint256);

    function totalShares() public view returns (uint256);

    function interestRate() public view returns (uint256);

    function lockupPeriod() public view returns (uint256);
    
    function minimumStake() public view returns (uint256);

    function stakingAdmin() public view returns (address);

    function updatePoolShareValue() public returns (uint256 _newPoolShareValue) ;

    function stake(uint256 _amount) public returns (uint256 _poolShares);

    function unStake(uint256 _numOfShares) public returns (uint256 _amount);

}
