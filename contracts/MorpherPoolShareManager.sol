pragma solidity 0.5.16;

import "./MorpherState.sol";
import "./SafeMath.sol";

contract MorpherPoolShareManager {
    MorpherState state;
    
    using SafeMath for uint256;

    //this influences the total pool shares, where it is known to the oracle 
    //if the transaction goes through an in which order - per block
    mapping(uint256 => uint256) public burnedPoolSharesPerBlock;
    mapping(uint256 => uint256) public mintedPoolSharesPerBlock;
    uint256 public totalPoolShareTokens;
    uint256 public lastTxCountOracle;

    uint256 public totalBNBInPositions;

    constructor(address _state) public {
        state = MorpherState(_state);
    }

    modifier onlyOracle() {
        require(msg.sender == state.getOracleContract(), "MorpherPoolShareManager: only Oracle can call this function");
        _;
    }

     function mintPoolShares(address _userAddress, uint256 _totalPoolShares, uint256 _lastTxCountFromBackend, uint256 _openBNBAmount) public onlyOracle returns (uint256) {

        if(_lastTxCountFromBackend > lastTxCountOracle) {
            lastTxCountOracle = _lastTxCountFromBackend;
            totalPoolShareTokens = _totalPoolShares;
        }
        uint256 paidBNB = _openBNBAmount;
        uint256 totalBNB = getTotalBnb();
        totalBNBInPositions = totalBNB.add(paidBNB);
        uint256 totalPs = totalPoolShareTokens.add(mintedPoolSharesPerBlock[lastTxCountOracle]).sub(burnedPoolSharesPerBlock[lastTxCountOracle]);
                //pool shares = (totalPS / totalBNB) * paidBNB
        //@todo check if those assumptions are correct
        if(totalPs == 0) {
            totalPs = 1;
            totalBNB = 1; //if no ps, then 1 BNB = 1 PS
        }
        if(totalBNB == 0) {
            totalBNB = totalPs; //if no bnb in the pool yet, then 1 BNB = 1 PS
        }
        uint256 mintPoolShareTokens = (totalPs.mul(paidBNB).div(totalBNB));
        
        //and mint them
        mintedPoolSharesPerBlock[lastTxCountOracle] = mintedPoolSharesPerBlock[lastTxCountOracle].add(mintPoolShareTokens);
        state.mint(_userAddress, mintPoolShareTokens);

        //and set the amount as openMPHAmount... so tradeengine can calculate the trade. We're trading everything. Obviously.
        return mintPoolShareTokens;
    }

    function burnPoolShares(address _userAddress, uint256 _totalPoolShares, uint256 _lastTxCountFromBackend) public onlyOracle returns(uint256) {
        if(_lastTxCountFromBackend > lastTxCountOracle) {
            lastTxCountOracle = _lastTxCountFromBackend;
            totalPoolShareTokens = _totalPoolShares;
        }
        
        uint256 totalBNB = getTotalBnb();
        uint256 totalPs = totalPoolShareTokens.add(mintedPoolSharesPerBlock[lastTxCountOracle]).sub(burnedPoolSharesPerBlock[lastTxCountOracle]);
        uint256 balancePSOfUser = state.balanceOf(_userAddress);

        // //calulate the BNB and burn the tokens
        uint256 payOutBNB = balancePSOfUser.mul(totalBNB).div(totalPs);
        totalBNBInPositions = totalBNB.sub(payOutBNB);
        state.burn(_userAddress, balancePSOfUser);
        burnedPoolSharesPerBlock[lastTxCountOracle] = burnedPoolSharesPerBlock[lastTxCountOracle].add(balancePSOfUser);
        return payOutBNB;
    }

    function getTotalBnb() public view returns (uint256) {
        return totalBNBInPositions; //address(state.getOracleContract()).balance;
    }


}