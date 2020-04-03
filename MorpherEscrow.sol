pragma solidity 0.5.16;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./IERC20.sol";

// ----------------------------------------------------------------------------------
// Escrow contract to safely store and release the token allocated to Morpher at
// protocol  inception
// ----------------------------------------------------------------------------------

contract MorpherEscrow is Ownable{
    using SafeMath for uint256;
    
    uint256 public lastEscrowTransferTime;    
    address public recipient;
    address public morpherToken;
    
    uint256 constant DECIMALS = 18;
    
    event EscrowReleased(uint256 _released, uint256 _leftInEscrow, uint256 _timeStamp);    
    
    constructor(address _recipientAddress) public {
        setRecipientAddress(_recipientAddress);
        lastEscrowTransferTime = now;
    }

// ----------------------------------------------------------------------------------
// Owner can modify recipient address and link to MorpherState
// ----------------------------------------------------------------------------------
    function setRecipientAddress(address _recipientAddress) public onlyOwner {
        recipient = _recipientAddress;
    }

    function setMorpherTokenAddress(address _address) public onlyOwner {
        morpherToken = _address;
    }

// ----------------------------------------------------------------------------------
// Anyone can release funds from escrow if enough time has elapsed
// Every 30 days 1% of the total initial supply or 10m token are released to Morpher
// ----------------------------------------------------------------------------------
    function releaseFromEscrow() public {
        require(IERC20(morpherToken).balanceOf(address(this)) > 0, "No funds left in escrow.");
        // !! Change to 30 days after testing !!
        uint256 _releasedAmount;
        if (now > lastEscrowTransferTime.add(1 days)) {
            if (IERC20(morpherToken).balanceOf(address(this)) > (10**DECIMALS).mul(10000000)) {
                _releasedAmount = (10**DECIMALS).mul(10000000);
            } else {
                _releasedAmount = IERC20(morpherToken).balanceOf(address(this));
            }
            IERC20(morpherToken).transfer(recipient, _releasedAmount);
            // !! Change to 30 days after testing !!
            lastEscrowTransferTime = lastEscrowTransferTime.add(1 days);
            emit EscrowReleased(_releasedAmount, IERC20(morpherToken).balanceOf(address(this)), now);
        }
    }
}
