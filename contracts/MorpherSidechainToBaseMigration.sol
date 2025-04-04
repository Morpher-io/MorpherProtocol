// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0; // Using 0.8.x for features like custom errors, though block.chainid is replaced

// --- Interfaces ---

interface IMorpherState {
    function getPosition(address _address, bytes32 _marketId) external view returns (
        uint256 longShares,
        uint256 shortShares,
        uint256 meanEntryPrice,
        uint256 meanEntrySpread,
        uint256 meanEntryLeverage,
        uint256 liquidationPrice
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

    function balanceOf(address _tokenOwner) external view returns (uint256 balance);

    function burn(address _address, uint256 _token) external;

    // Needed if MorpherState restricts access based on administrator
    function getAdministrator() external view returns(address);
    // Add any other functions required for interaction or permissions
}

interface IMorpherOracle {
    function isCallbackAddress(address _address) external view returns (bool _isCallBackAddress);
}

// --- Contract ---

/**
 * @title MorpherSidechainToBaseMigration
 * @notice Handles the migration of user assets (positions and tokens) from a sidechain
 *         to a target chain (e.g., Base L2) by verifying a user signature that includes
 *         the target chain ID. Migration can only be initiated by authorized Oracle callback addresses.
 * @dev Implements custom ECDSA signature recovery to avoid external libraries.
 */
contract MorpherSidechainToBaseMigration {
    // --- State Variables ---

    IMorpherState public morpherState;
    IMorpherOracle public morpherOracle;
    address public administrator;
    uint256 public immutable targetChainId; // Set at deployment, used in signature

    // --- Events ---

    event AdministratorChanged(address indexed oldAdmin, address indexed newAdmin);
    event MorpherStateChanged(address indexed newStateAddress);
    event MorpherOracleChanged(address indexed newOracleAddress);
    event MigrationExecuted(address indexed user, uint256 burnedAmount);
    event PositionClosed(address indexed user, bytes32 indexed marketId);
    event MigrationFailed(address indexed user, address indexed caller, string reason);

    // --- Constants for Signature Verification ---

    // bytes32(0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0)
    bytes32 constant internal SECP256K1_N_DIV_2_PLUS_1 = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A1;
    string constant internal SIGNATURE_PREFIX = "I authorize migration of all my positions from plasma chain to Base L2";
    bytes constant internal ETH_SIGNED_MESSAGE_PREFIX = "\x19Ethereum Signed Message:\n32";

    // --- Errors ---
    // Using custom errors for better gas efficiency (Solidity ^0.8.4)
    error InvalidSignature();
    error InvalidSignatureLength(uint256 length);
    error InvalidSignatureSValue(bytes32 s);
    error InvalidSignatureVValue();
    error EcrecoverFailure();
    error CallerNotAdmin();
    error CallerNotOracleCallback();
    error InvalidAddress();
    error SignerMismatch();


    // --- Modifiers ---

    modifier onlyAdministrator {
        if (msg.sender != administrator) revert CallerNotAdmin();
        _;
    }

    modifier onlyOracleCallback {
        if (!morpherOracle.isCallbackAddress(msg.sender)) revert CallerNotOracleCallback();
        _;
    }

    // --- Constructor ---

    constructor(address _stateAddress, address _oracleAddress, uint256 _targetChainId) {
        if (_stateAddress == address(0) || _oracleAddress == address(0)) revert InvalidAddress();

        morpherState = IMorpherState(_stateAddress);
        morpherOracle = IMorpherOracle(_oracleAddress);
        targetChainId = _targetChainId; // Set the immutable target chain ID
        administrator = msg.sender;

        emit AdministratorChanged(address(0), msg.sender);
        emit MorpherStateChanged(_stateAddress);
        emit MorpherOracleChanged(_oracleAddress);
    }

    // --- Administrative Functions ---

    function setMorpherState(address _stateAddress) public onlyAdministrator {
        if (_stateAddress == address(0)) revert InvalidAddress();
        morpherState = IMorpherState(_stateAddress);
        emit MorpherStateChanged(_stateAddress);
    }

    function setMorpherOracle(address _oracleAddress) public onlyAdministrator {
         if (_oracleAddress == address(0)) revert InvalidAddress();
        morpherOracle = IMorpherOracle(_oracleAddress);
        emit MorpherOracleChanged(_oracleAddress);
    }

    function transferAdministrator(address _newAdmin) public onlyAdministrator {
        if (_newAdmin == address(0)) revert InvalidAddress();
        address oldAdmin = administrator;
        administrator = _newAdmin;
        emit AdministratorChanged(oldAdmin, _newAdmin);
    }

    // --- Core Migration Logic ---

    /**
     * @notice Migrates a user's assets by closing positions and burning tokens after verifying their signature.
     * @dev Can only be called by an authorized Oracle callback address.
     * @param _user The address of the user whose assets are being migrated.
     * @param _signature The user's signature authorizing the migration (must include targetChainId).
     * @param _marketIds An array of market IDs where the user might have positions to close.
     */
    function migrateUserAssets(
        address _user,
        bytes calldata _signature,
        bytes32[] calldata _marketIds
    ) external onlyOracleCallback { // Restrict caller
        // 1. Verify Signature
        address recoveredSigner = _verifySignature(_user, _signature);
        if (recoveredSigner != _user) {
             emit MigrationFailed(_user, msg.sender, "Signer mismatch");
             revert SignerMismatch();
        }
        // Note: _recover already reverts if recoveredSigner is address(0)

        // 2. Close Positions
        for (uint i = 0; i < _marketIds.length; i++) {
            _closePosition(_user, _marketIds[i]);
        }

        // 3. Burn Tokens
        uint256 burnedAmount = _burnTokens(_user);

        emit MigrationExecuted(_user, burnedAmount);
    }

    // --- Internal Helper Functions ---

    /**
     * @dev Verifies the user's signature against the expected message format using the stored targetChainId.
     * @param _user The user address included in the signed message.
     * @param _signature The signature bytes (expected length 65).
     * @return recoveredAddress The address recovered from the signature.
     */
    function _verifySignature(address _user, bytes calldata _signature) internal view returns (address recoveredAddress) {
        // Reconstruct the message hash that was signed
        bytes32 messageHash = keccak256(abi.encodePacked(
            SIGNATURE_PREFIX,
            _user,
            targetChainId // Use the stored targetChainId
        ));

        // Apply the Ethereum Signed Message prefix
        bytes32 ethSignedHash = keccak256(abi.encodePacked(ETH_SIGNED_MESSAGE_PREFIX, messageHash));

        // Recover the signer address using custom logic
        recoveredAddress = _recover(ethSignedHash, _signature);
    }

    /**
     * @dev Recovers the signer address from a hash and signature, implementing ECDSA logic directly.
     *      Based on OpenZeppelin's ECDSA library logic. Reverts on failure.
     * @param _hash The hash that was signed (typically the ethSignedHash).
     * @param _signature The signature bytes (expected length 65: r, s, v).
     * @return signer The recovered address.
     */
    function _recover(bytes32 _hash, bytes calldata _signature) internal pure returns (address signer) {
        // Signature Length Check
        if (_signature.length != 65) {
            revert InvalidSignatureLength(_signature.length);
        }

        bytes32 r;
        bytes32 s;
        uint8 v;

        // Extract r, s, v from signature
        // solhint-disable-next-line no-inline-assembly
        assembly {
            r := calldataload(add(_signature.offset, 0x20)) // offset + 32 bytes (skip length)
            s := calldataload(add(_signature.offset, 0x40)) // offset + 64 bytes
            v := byte(0, calldataload(add(_signature.offset, 0x60))) // offset + 96 bytes
        }

        // EIP-2 Signature Malleability Check (v must be 27 or 28)
         if (v != 27 && v != 28) {
             revert InvalidSignatureVValue();
         }

        // EIP-2 Signature Malleability Check (s must be in the lower half order)
        if (uint256(s) >= uint256(SECP256K1_N_DIV_2_PLUS_1)) {
             revert InvalidSignatureSValue(s);
        }

        // Perform ecrecover precompile
        signer = ecrecover(_hash, v, r, s);

        // Ensure recovery was successful (ecrecover returns address(0) on failure)
        if (signer == address(0)) {
            revert EcrecoverFailure();
        }
    }


    /**
     * @dev Closes a user's position in a specific market if it exists by setting shares to zero.
     * @param _user The user address.
     * @param _marketId The market ID to close the position in.
     */
    function _closePosition(address _user, bytes32 _marketId) internal {
        (uint256 longShares, uint256 shortShares, , , , ) = morpherState.getPosition(_user, _marketId);

        if (longShares > 0 || shortShares > 0) {
            // Set all position parameters to 0 to effectively close/delete it
            morpherState.setPosition(
                _user,
                _marketId,
                block.timestamp, // Use current time for the update
                0, // longShares
                0, // shortShares
                0, // meanEntryPrice
                0, // meanEntrySpread
                0, // meanEntryLeverage
                0  // liquidationPrice
            );
            emit PositionClosed(_user, _marketId);
        }
        // If no shares, do nothing for this market.
    }

    /**
     * @dev Burns all tokens held by the user by calling MorpherState.
     * @param _user The user address.
     * @return burnedAmount The amount of tokens burned.
     */
    function _burnTokens(address _user) internal returns (uint256 burnedAmount) {
        burnedAmount = morpherState.balanceOf(_user);
        if (burnedAmount > 0) {
            morpherState.burn(_user, burnedAmount);
            // Event emitted by MorpherState.burn, no need to re-emit here
        }
        return burnedAmount;
    }
}
