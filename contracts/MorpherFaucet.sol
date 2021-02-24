pragma solidity 0.5.16;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./MorpherToken.sol";

// ----------------------------------------------------------------------------------
// Holds the Faucet Token balance on contract addressrdrop.
// Users can topup to fillUpAmount
// ----------------------------------------------------------------------------------

contract MorpherFaucet is Ownable {
    using SafeMath for uint256;

    MorpherToken morpherToken;

    uint public fillUpAmount; //100 * 10**18; //fill up to 100 MPH.

    event MorpherFaucetTopUp(address indexed _receiver, uint _amount);
    event MorpherFaucetFillUpAmountChanged(uint _oldAmount, uint _newAmount);

    constructor(address payable _morpherToken, address _coldStorageOwnerAddress, uint _fillUpAmount) public {
        morpherToken = MorpherToken(_morpherToken);
        transferOwnership(_coldStorageOwnerAddress);
        setFillUpAmount(_fillUpAmount);
    }
  
    function setMorpherTokenAddress(address payable _address) public onlyOwner {
        morpherToken = MorpherToken(_address);
    }

    function setFillUpAmount(uint _newFillUpAmount) public onlyOwner {
        emit MorpherFaucetFillUpAmountChanged(fillUpAmount, _newFillUpAmount);
        fillUpAmount = _newFillUpAmount;
    }


    /**
     * Only important function: User can top-up to his max amount. Needs to have less than fillUpAmount, otherwise it will fail.
     */
    function topUpToken() public {
        require(morpherToken.balanceOf(msg.sender) < fillUpAmount, "FILLUP_AMOUNT_REACHED");
        morpherToken.transfer(msg.sender, fillUpAmount.sub(morpherToken.balanceOf(msg.sender)));
        emit MorpherFaucetTopUp(msg.sender, fillUpAmount.sub(morpherToken.balanceOf(msg.sender)));
    }

    function () external payable {
        revert("MorpherFaucet: you can't deposit Ether here");
    }


}
