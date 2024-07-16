//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.11;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "./MorpherAccessControl.sol";


/// @custom:oz-upgrades-from contracts/prev/contracts/MorpherToken.sol:MorpherToken
contract MorpherToken is ERC20Upgradeable, ERC20PausableUpgradeable {
	MorpherAccessControl public morpherAccessControl;

	bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
	bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
	bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
	bytes32 public constant ADMINISTRATOR_ROLE = keccak256("ADMINISTRATOR_ROLE");
	bytes32 public constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");
	bytes32 public constant TRANSFERBLOCKED_ROLE = keccak256("TRANSFERBLOCKED_ROLE");
	bytes32 public constant POLYGONMINTER_ROLE = keccak256("POLYGONMINTER_ROLE");
	bytes32 public constant TOKENUPDATER_ROLE = keccak256("TOKENUPDATER_ROLE");

	uint256 private _totalTokensOnOtherChain;
	uint256 private _totalTokensInPositions;
	bool private _restrictTransfers;

	/**
	 * Permit functionality
	 * Added after proxy was deployed, so manually adding functionality here
	 */
	bytes32 private _HASHED_NAME; //todo: derive from the token name instad of a hardcoded value
	bytes32 private _HASHED_VERSION;
	bytes32 private constant _TYPE_HASH =
		keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
	using CountersUpgradeable for CountersUpgradeable.Counter;

	mapping(address => CountersUpgradeable.Counter) private _nonces;

	// solhint-disable-next-line var-name-mixedcase
	bytes32 private constant _PERMIT_TYPEHASH =
		keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
	
	bytes32 private _PERMIT_TYPEHASH_DEPRECATED_SLOT;

	event SetTotalTokensOnOtherChain(uint256 _oldValue, uint256 _newValue);
	event SetTotalTokensInPositions(uint256 _oldValue, uint256 _newValue);
	event SetRestrictTransfers(bool _oldValue, bool _newValue);

	function initialize(address _morpherAccessControl) public initializer {
		ERC20Upgradeable.__ERC20_init("Morpher", "MPH");
		morpherAccessControl = MorpherAccessControl(_morpherAccessControl);
		_HASHED_NAME = keccak256(bytes("MorpherToken"));
		_HASHED_VERSION = keccak256(bytes("1"));
	}

	modifier onlyRole(bytes32 role) {
		require(morpherAccessControl.hasRole(role, _msgSender()), "MorpherToken: Permission denied.");
		_;
	}

    function setHashedName(string memory _name) public onlyRole(ADMINISTRATOR_ROLE) {
        _HASHED_NAME = keccak256(bytes(_name));
    }
    function setHashedVersion(string memory _version) public onlyRole(ADMINISTRATOR_ROLE) {
        _HASHED_VERSION = keccak256(bytes(_version));
    }

	// function getMorpherAccessControl() public view returns(address) {
	//     return address(morpherAccessControl);
	// }

	function setRestrictTransfers(bool restrictTransfers) public onlyRole(ADMINISTRATOR_ROLE) {
		emit SetRestrictTransfers(_restrictTransfers, restrictTransfers);
		_restrictTransfers = restrictTransfers;
	}

	function getRestrictTransfers() public view returns (bool) {
		return _restrictTransfers;
	}

	function setTotalTokensOnOtherChain(uint256 totalOnOtherChain) public onlyRole(TOKENUPDATER_ROLE) {
		emit SetTotalTokensOnOtherChain(_totalTokensInPositions, totalOnOtherChain);
		_totalTokensOnOtherChain = totalOnOtherChain;
	}

	function getTotalTokensOnOtherChain() public view returns (uint256) {
		return _totalTokensOnOtherChain;
	}

	function setTotalInPositions(uint256 totalTokensInPositions) public onlyRole(TOKENUPDATER_ROLE) {
		emit SetTotalTokensInPositions(_totalTokensInPositions, totalTokensInPositions);
		_totalTokensInPositions = totalTokensInPositions;
	}

	function getTotalTokensInPositions() public view returns (uint256) {
		return _totalTokensInPositions;
	}

	/**
	 * @dev See {IERC20-totalSupply}.
	 */
	function totalSupply() public view virtual override returns (uint256) {
		return super.totalSupply() + _totalTokensOnOtherChain + _totalTokensInPositions;
	}

	function deposit(address user, bytes calldata depositData) external onlyRole(POLYGONMINTER_ROLE) {
		uint256 amount = abi.decode(depositData, (uint256));
		_mint(user, amount);
	}

	function withdraw(uint256 amount) external onlyRole(POLYGONMINTER_ROLE) {
		_burn(msg.sender, amount);
	}

	/**
	 * @dev Creates `amount` new tokens for `to`.
	 *
	 * See {ERC20-_mint}.
	 *
	 * Requirements:
	 *
	 * - the caller must have the `MINTER_ROLE`.
	 */
	function mint(address to, uint256 amount) public virtual {
		require(morpherAccessControl.hasRole(MINTER_ROLE, _msgSender()), "MorpherToken: must have minter role to mint");
		_mint(to, amount);
	}

	/**
	 * @dev Burns `amount` of tokens for `from`.
	 *
	 * See {ERC20-_burn}.
	 *
	 * Requirements:
	 *
	 * - the caller must have the `BURNER_ROLE`.
	 */
	function burn(address from, uint256 amount) public virtual {
		require(morpherAccessControl.hasRole(BURNER_ROLE, _msgSender()), "MorpherToken: must have burner role to burn");
		_burn(from, amount);
	}

	/**
	 * @dev Pauses all token transfers.
	 *
	 * See {ERC20Pausable} and {Pausable-_pause}.
	 *
	 * Requirements:
	 *
	 * - the caller must have the `PAUSER_ROLE`.
	 */
	function pause() public virtual {
		require(
			morpherAccessControl.hasRole(PAUSER_ROLE, _msgSender()),
			"MorpherToken: must have pauser role to pause"
		);
		_pause();
	}

	/**
	 * @dev Unpauses all token transfers.
	 *
	 * See {ERC20Pausable} and {Pausable-_unpause}.
	 *
	 * Requirements:
	 *
	 * - the caller must have the `PAUSER_ROLE`.
	 */
	function unpause() public virtual {
		require(
			morpherAccessControl.hasRole(PAUSER_ROLE, _msgSender()),
			"MorpherToken: must have pauser role to unpause"
		);
		_unpause();
	}

	function _beforeTokenTransfer(
		address from,
		address to,
		uint256 amount
	) internal virtual override(ERC20Upgradeable, ERC20PausableUpgradeable) {
		require(
			!_restrictTransfers ||
				morpherAccessControl.hasRole(TRANSFER_ROLE, _msgSender()) ||
				morpherAccessControl.hasRole(MINTER_ROLE, _msgSender()) ||
				morpherAccessControl.hasRole(BURNER_ROLE, _msgSender()) ||
				morpherAccessControl.hasRole(TRANSFER_ROLE, from),
			"MorpherToken: Transfer denied"
		);

		require(
			!morpherAccessControl.hasRole(TRANSFERBLOCKED_ROLE, _msgSender()),
			"MorpherToken: Transfer for User is blocked."
		);

		super._beforeTokenTransfer(from, to, amount);
	}

	/**
	 * @dev Returns the domain separator for the current chain.
	 */
	function _domainSeparatorV4() internal view returns (bytes32) {
		return _buildDomainSeparator(_TYPE_HASH, _EIP712NameHash(), _EIP712VersionHash());
	}

	function _buildDomainSeparator(
		bytes32 typeHash,
		bytes32 nameHash,
		bytes32 versionHash
	) private view returns (bytes32) {
		return keccak256(abi.encode(typeHash, nameHash, versionHash, block.chainid, address(this)));
	}

	/**
	 * @dev Given an already https://eips.ethereum.org/EIPS/eip-712#definition-of-hashstruct[hashed struct], this
	 * function returns the hash of the fully encoded EIP712 message for this domain.
	 *
	 * This hash can be used together with {ECDSA-recover} to obtain the signer of a message. For example:
	 *
	 * ```solidity
	 * bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(
	 *     keccak256("Mail(address to,string contents)"),
	 *     mailTo,
	 *     keccak256(bytes(mailContents))
	 * )));
	 * address signer = ECDSA.recover(digest, signature);
	 * ```
	 */
	function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32) {
		return ECDSAUpgradeable.toTypedDataHash(_domainSeparatorV4(), structHash);
	}

	/**
	 * @dev The hash of the name parameter for the EIP712 domain.
	 *
	 * NOTE: This function reads from storage by default, but can be redefined to return a constant value if gas costs
	 * are a concern.
	 */
	function _EIP712NameHash() internal view virtual returns (bytes32) {
		return _HASHED_NAME;
	}

	/**
	 * @dev The hash of the version parameter for the EIP712 domain.
	 *
	 * NOTE: This function reads from storage by default, but can be redefined to return a constant value if gas costs
	 * are a concern.
	 */
	function _EIP712VersionHash() internal view virtual returns (bytes32) {
		return _HASHED_VERSION;
	}

	/**
	 * @dev See {IERC20Permit-permit}.
	 */
	function permit(
		address owner,
		address spender,
		uint256 value,
		uint256 deadline,
		uint8 v,
		bytes32 r,
		bytes32 s
	) public virtual {
		require(block.timestamp <= deadline, "ERC20Permit: expired deadline");

		bytes32 structHash = keccak256(abi.encode(_PERMIT_TYPEHASH, owner, spender, value, _useNonce(owner), deadline));

		bytes32 hash = _hashTypedDataV4(structHash);

		address signer = ECDSAUpgradeable.recover(hash, v, r, s);
		require(signer == owner, "ERC20Permit: invalid signature");

		_approve(owner, spender, value);
	}

	/**
	 * @dev See {IERC20Permit-nonces}.
	 */
	function nonces(address owner) public view virtual returns (uint256) {
		return _nonces[owner].current();
	}

	/**
	 * @dev See {IERC20Permit-DOMAIN_SEPARATOR}.
	 */
	// solhint-disable-next-line func-name-mixedcase
	function DOMAIN_SEPARATOR() external view returns (bytes32) {
		return _domainSeparatorV4();
	}

	/**
	 * @dev "Consume a nonce": return the current value and increment.
	 *
	 * _Available since v4.1._
	 */
	function _useNonce(address owner) internal virtual returns (uint256 current) {
		CountersUpgradeable.Counter storage nonce = _nonces[owner];
		current = nonce.current();
		nonce.increment();
	}
}
