pragma solidity 0.5.16;
// ------------------------------------------------------------------------
// Morpher Governance (MAIN CHAIN ONLY)
//
// Every user able and willig to lock up sufficient token can become a validator
// of the Morpher protocol. Validators function similiar to a board of directors
// and vote on the protocol Administrator and the Oracle contract.
// The Administrator (=Protocol CEO) has the power to add/delete markets and to
// pause the contracts to allow for updates.
// The Oracle contract is the address of the contract allowed to fetch prices
// from outside the smart contract.
//
// It becomes progressively harder to become a valdiator. Each new validator
// has to lock up (numberOfValidators + 1) * 10m Morpher token. Upon stepping
// down as validator only 99% of the locked up token are returned, the other 1%
// are burned.
//
// Governance is expected to become more sophisticated in the future
// ------------------------------------------------------------------------

import "./Ownable.sol";
import "./SafeMath.sol";
import "./MorpherState.sol";

contract MorpherGovernance is Ownable {

    using SafeMath for uint256;
    MorpherState state;
    
    event BecomeValidator(address indexed _sender, uint256 indexed _myValidatorIndex);
    event StepDownAsValidator(address indexed _sender, uint256 indexed _myValidatorIndex);
    event ElectedAdministrator(address indexed _administratorAddress, uint256 _votes);
    event ElectedOracle(address indexed _oracleAddress, uint256 _votes);

    uint256 public constant MINVALIDATORLOCKUP = 10**25;
    uint256 public constant MAXVALIDATORS = 21;
    uint256 public constant VALIDATORWARMUPPERIOD = 7 days;

    uint256 public numberOfValidators;
    uint256 public lastValidatorJoined;
    uint256 public rewardBasisPoints;

    address public morpherToken;

    mapping(address => uint256) private validatorIndex;
    mapping(address => uint256) private validatorJoinedAtTime;
    mapping(uint256 => address) private validatorAddress;
    mapping(address => address) private oracleVote;
    mapping(address => address) private administratorVote;
    mapping(address => uint256) private countVotes;

    constructor(address _stateAddress, address _coldStorageOwnerAddress) public {
        setMorpherState(_stateAddress);
        transferOwnership(_coldStorageOwnerAddress);        
    }
    
    modifier onlyValidator() {
        require(isValidator(msg.sender), "MorpherGovernance: Only Validators can invoke that function.");
        _;
    }

    function setMorpherState(address _stateAddress) private {
        state = MorpherState(_stateAddress);
    }

    function setMorpherTokenAddress(address _address) public onlyOwner {
        morpherToken = _address;
    }

    function getValidatorAddress(uint256 _index) public view returns (address _address) {
        return validatorAddress[_index];
    }

    function getValidatorIndex(address _address) public view returns (uint256 _index) {
        return validatorIndex[_address];
    }

    function isValidator(address _address) public view returns (bool) {
        return validatorIndex[_address] > 0;
    }

    function setOracle(address  _oracleAddress) private {
        state.setOracleContract(_oracleAddress);
    }

    function setAdministrator(address _administratorAddress) private {
        state.setAdministrator(_administratorAddress);
    }

    function getMorpherAdministrator() public view returns (address _address) {
        return state.getAdministrator();
    }

    function getMorpherOracle() public view returns (address _address)  {
        return state.getOracleContract();
    }

    function getOracleVote(address _address) public view returns (address _votedOracleAddress) {
        return oracleVote[_address];
    }

    function becomeValidator() public {
        // To become a validator you have to lock up 10m * (number of validators + 1) Morpher Token in escrow
        // After a warmup period of 7 days the new validator can vote on Oracle contract and protocol Administrator
        uint256 _requiredAmount = MINVALIDATORLOCKUP.mul(numberOfValidators.add(1));
        require(state.balanceOf(msg.sender) >= _requiredAmount, "MorpherGovernance: Insufficient balance to become Validator.");
        require(isValidator(msg.sender) == false, "MorpherGovernance: Address is already Validator.");
        require(numberOfValidators <= MAXVALIDATORS, "MorpherGovernance: number of Validators can not exceed Max Validators.");
        state.transfer(msg.sender, address(this), _requiredAmount);
        numberOfValidators = numberOfValidators.add(1);
        validatorIndex[msg.sender] = numberOfValidators;
        validatorJoinedAtTime[msg.sender] = now;
        lastValidatorJoined = now;
        validatorAddress[numberOfValidators] = msg.sender;
        emit BecomeValidator(msg.sender, numberOfValidators);
    }

    function stepDownValidator() public onlyValidator {
        // Stepping down as validator nullifies the validator's votes and releases his token
        // from escrow. If the validator stepping down is not the validator that joined last,
        // all validators who joined after the validator stepping down receive 10^7 * 0.99 token from
        // escrow, and their validator ordinal number is reduced by one. E.g. if validator 3 of 5 steps down
        // validator 4 becomes validator 3, and validator 5 becomes validator 4. Both receive 10^7 * 0.99 token
        // from escrow, as their new position requires fewer token in lockup. 1% of the token released from escrow 
        // are burned for every validator receiving a payout. 
        // Burning prevents vote delay attacks: validators stepping down and re-joining could
        // delay votes for VALIDATORWARMUPPERIOD.
        uint256 _myValidatorIndex = validatorIndex[msg.sender];
        require(state.balanceOf(address(this)) >= MINVALIDATORLOCKUP.mul(numberOfValidators), "MorpherGovernance: Escrow does not have enough funds. Should not happen.");
        // Stepping down as validator potentially releases token to the other validatorAddresses
        for (uint256 i = _myValidatorIndex; i < numberOfValidators; i++) {
            validatorAddress[i] = validatorAddress[i+1];
            validatorIndex[validatorAddress[i]] = i;
            // Release 9.9m of token to every validator moving up, burn 0.1m token
            state.transfer(address(this), validatorAddress[i], MINVALIDATORLOCKUP.div(100).mul(99));
            state.burn(address(this), MINVALIDATORLOCKUP.div(100));
        }
        // Release 99% of escrow token of validator dropping out, burn 1%
        validatorAddress[numberOfValidators] = address(0);
        validatorIndex[msg.sender] = 0;
        validatorJoinedAtTime[msg.sender] = 0;
        oracleVote[msg.sender] = address(0);
        administratorVote[msg.sender] = address(0);
        numberOfValidators = numberOfValidators.sub(1);
        countOracleVote();
        countAdministratorVote();
        state.transfer(address(this), msg.sender, MINVALIDATORLOCKUP.mul(_myValidatorIndex).div(100).mul(99));
        state.burn(address(this), MINVALIDATORLOCKUP.mul(_myValidatorIndex).div(100));
        emit StepDownAsValidator(msg.sender, validatorIndex[msg.sender]);
    }

    function voteOracle(address _oracleAddress) public onlyValidator {
        require(validatorJoinedAtTime[msg.sender].add(VALIDATORWARMUPPERIOD) < now, "MorpherGovernance: Validator was just appointed and is not eligible to vote yet.");
        require(lastValidatorJoined.add(VALIDATORWARMUPPERIOD) < now, "MorpherGovernance: New validator joined the board recently, please wait for the end of the warm up period.");
        oracleVote[msg.sender] = _oracleAddress;
        // Count Oracle Votes
        (address _votedOracleAddress, uint256 _votes) = countOracleVote();
        emit ElectedOracle(_votedOracleAddress, _votes);
    }

    function voteAdministrator(address _administratorAddress) public onlyValidator {
        require(validatorJoinedAtTime[msg.sender].add(VALIDATORWARMUPPERIOD) < now, "MorpherGovernance: Validator was just appointed and is not eligible to vote yet.");
        require(lastValidatorJoined.add(VALIDATORWARMUPPERIOD) < now, "MorpherGovernance: New validator joined the board recently, please wait for the end of the warm up period.");
        administratorVote[msg.sender] = _administratorAddress;
        // Count Administrator Votes
        (address _appointedAdministrator, uint256 _votes) = countAdministratorVote();
        emit ElectedAdministrator(_appointedAdministrator, _votes);
    }

    function countOracleVote() public returns (address _votedOracleAddress, uint256 _votes) {
        // Count oracle votes
        for (uint256 i = 1; i <= numberOfValidators; i++) {
            countVotes[oracleVote[validatorAddress[i]]]++;
            if (countVotes[oracleVote[validatorAddress[i]]] > _votes) {
                _votes = countVotes[oracleVote[validatorAddress[i]]];
                _votedOracleAddress = oracleVote[validatorAddress[i]];
            }
        }
        // Evaluate: Simple majority of Validators resets oracleAddress
        if (_votes > numberOfValidators.div(2)) {
            setOracle(_votedOracleAddress);
        }
        for (uint256 i = 1; i <= numberOfValidators; i++) {
            countVotes[administratorVote[validatorAddress[i]]] = 0;
        }
        return(_votedOracleAddress, _votes);
    }

    function countAdministratorVote() public returns (address _appointedAdministrator, uint256 _votes) {
        // Count Administrator votes
        for (uint256 i=1; i<=numberOfValidators; i++) {
            countVotes[administratorVote[validatorAddress[i]]]++;
            if (countVotes[administratorVote[validatorAddress[i]]] > _votes) {
                _votes = countVotes[administratorVote[validatorAddress[i]]];
                _appointedAdministrator = administratorVote[validatorAddress[i]];
            }
        }
        // Evaluate: Simple majority of Validators resets administratorAddress
        if (_votes > numberOfValidators / 2) {
            setAdministrator(_appointedAdministrator);
        }
        for (uint256 i = 1; i <= numberOfValidators; i++) {
            countVotes[administratorVote[validatorAddress[i]]] = 0;
        }
        return(_appointedAdministrator, _votes);
    }
}
