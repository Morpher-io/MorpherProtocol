//SPDX-License-Identifier: GPLv3
pragma solidity 0.8.11;

import "./MorpherState.sol";
import "./interfaces/IMorpherStateDeprecated.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

contract MorpherDeprecatedTokenMapper is Initializable, ContextUpgradeable {
	MorpherState morpherState;
    IMorpherStateDeprecated morpherStateDeprecated;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant ADMINISTRATOR_ROLE = keccak256("ADMINISTRATOR_ROLE");

    modifier onlyRole(bytes32 role) {
        require(MorpherAccessControl(morpherState.morpherAccessControlAddress()).hasRole(role, _msgSender()), "MorpherOracle: Permission denied.");
        _;
    }

	function initialize(address _morpherState) public initializer {
		morpherState = MorpherState(_morpherState);
	}

    function updateDeprecatedMorpherStateAddress(address oldStateAddress) public onlyRole(ADMINISTRATOR_ROLE) {
        morpherStateDeprecated = IMorpherStateDeprecated(oldStateAddress);
    }


    function transfer(address to, uint amount) public {
        morpherStateDeprecated.burn(msg.sender, amount);
        morpherStateDeprecated.mint(to, amount);
    }

    function mint(address to, uint amount) public onlyRole(MINTER_ROLE) {
        morpherStateDeprecated.mint(to, amount);
    }

    function burn(address from, uint amount) public onlyRole(BURNER_ROLE) {
        morpherStateDeprecated.burn(from, amount);
    }

}
