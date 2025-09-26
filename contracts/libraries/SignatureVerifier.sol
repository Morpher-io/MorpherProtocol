//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.15;

/**
 * @title SignatureVerifier
 * @author Morpher
 * @notice A library to verify signatures from EOAs and contracts, including support for EIP-1271 and EIP-6492.
 * This is based on the reference implementation from EIP-6492.
 */

/**
 * @dev Interface of the ERC1271 standard signature validation method for contracts.
 */
interface IERC1271Wallet {
  /**
   * @dev Should return whether the signature provided is valid for the provided hash
   * @param _hash      Hash of the data to be signed
   * @param _signature Signature byte array associated with _hash
   *
   * MUST return the bytes4 magic value 0x1626ba7e when function passes.
   * MUST NOT modify state (using view modifier for solc > 0.5)
   * MUST allow external calls
   */ 
  function isValidSignature(bytes32 _hash, bytes memory _signature) external view returns (bytes4 magicValue);
}

library SignatureVerifier {
    bytes32 private constant ERC6492_DETECTION_SUFFIX = 0x6492649264926492649264926492649264926492649264926492649264926492;
    bytes4 private constant ERC1271_SUCCESS_VALUE = 0x1626ba7e;

    error ERC1271InvalidSignature(bytes reason);
    error ERC6492DeploymentFailed(bytes reason);

    /**
     * @notice Verifies an EOA signature provided as v, r, s components.
     * @param _signer The address of the account that should have signed the message.
     * @param _hash The hash of the message that was signed.
     * @param v The recovery ID of the signature.
     * @param r The r value of the signature.
     * @param s The s value of the signature.
     * @return A boolean indicating if the signature is valid.
     */
    function isValidSignatureNow(
        address _signer,
        bytes32 _hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public pure returns (bool) {
        if (v != 27 && v != 28) {
            console.log("Invalid v value:", v);
            return false;
        }
        address recovered = ecrecover(_hash, v, r, s);
        console.log("Recovered Address:", recovered);
        return recovered == _signer;
    }

    /**
     * @notice Verifies a signature, supporting EOA (ecrecover), EIP-1271 (deployed contracts), and EIP-6492 (undeployed contracts).
     * @dev The order of checks is critical as per EIP-6492.
     * This function can have side effects (contract deployment via EIP-6492) and should NOT be called from a view function.
     * For EIP-6492, this implementation assumes the factory call data is for contract deployment. It does not yet
     * support the "prepare" call pattern for already-deployed-but-not-ready contracts.
     * @param _signer The address of the account that should have signed the message.
     * @param _hash The hash of the message that was signed.
     * @param _signature The signature bytes to verify.
     * @return A boolean indicating if the signature is valid.
     */
    function isValidSignatureNow(
        address _signer,
        bytes32 _hash,
        bytes memory _signature
    ) public returns (bool) {
        console.log("--- SignatureVerifier ---");
        console.log("Expected Signer:", _signer);
        console.log("Message Hash:", _hash);
        console.logBytes("Signature:", _signature);

        // 1. EIP-6492 Check: Signature wrapping for counterfactual contracts.
        // This must be checked first to allow EIP-6492 signatures to remain valid even after the contract is deployed.
        if (_signature.length >= 32) {
            bytes32 suffix;
            // Read the last 32 bytes of the signature without creating a memory copy.
            assembly {
                suffix := mload(add(_signature, sub(mload(_signature), 31)))
            }
            if (suffix == ERC6492_DETECTION_SUFFIX) {
                console.log("Detected EIP-6492 Signature");
                bool result = _verifyEIP6492(_signer, _hash, _signature);
                console.log("EIP-6492 Verification Result:", result);
                console.log("--- End SignatureVerifier ---");
                return result;
            }
        }
        
        // 2. EIP-1271 Check: If the signer is a contract, use its own validation logic.
        if (_signer.code.length > 0) {
            console.log("Detected Contract Signature (EIP-1271)");
            bool result = _verifyEIP1271(_signer, _hash, _signature);
            console.log("EIP-1271 Verification Result:", result);
            console.log("--- End SignatureVerifier ---");
            return result;
        }

        // 3. EOA Check: Fallback to standard ecrecover for Externally Owned Accounts.
        if (_signature.length == 65) {
            bytes32 r;
            bytes32 s;
            uint8 v;
            // Ecrecover signature validation
            assembly {
                r := mload(add(_signature, 32))
                s := mload(add(_signature, 64))
                v := byte(0, mload(add(_signature, 96)))
            }
            console.log("Detected EOA Signature");
            return isValidSignatureNow(_signer, _hash, v, r, s);
        }

        console.log("Signature did not match any known format.");
        console.log("--- End SignatureVerifier ---");
        return false;
    }

    function _verifyEIP1271(
        address _signer,
        bytes32 _hash,
        bytes memory _signature
    ) private view returns (bool) {
        try IERC1271Wallet(_signer).isValidSignature(_hash, _signature) returns (bytes4 magicValue) {
            return magicValue == ERC1271_SUCCESS_VALUE;
        } catch (bytes memory reason) {
            // Forward the revert reason for better debugging.
            revert ERC1271InvalidSignature(reason);
        }
    }

    function _verifyEIP6492(
        address _signer,
        bytes32 _hash,
        bytes memory _signature
    ) private returns (bool) {
        // The EIP-6492 signature format is `abi.encode(...) | magic_suffix`.
        // To decode the prefix, we must copy all but the last 32 bytes into a new memory array,
        // as slicing memory arrays is not supported in this way.
        uint256 prefixLength = _signature.length - 32;
        bytes memory prefix = new bytes(prefixLength);
        for (uint256 i = 0; i < prefixLength; i++) {
            prefix[i] = _signature[i];
        }

        // Decode the wrapped signature to get deployment data and the original signature.
        (address factory, bytes memory factoryCalldata, bytes memory originalSignature) = abi.decode(
            prefix,
            (address, bytes, bytes)
        );

        // If the contract is not yet deployed, deploy it. This is a state-changing operation.
        if (_signer.code.length == 0) {
            (bool success, bytes memory reason) = factory.call(factoryCalldata);
            if (!success) {
                revert ERC6492DeploymentFailed(reason);
            }
        }

        // After potential deployment, perform a standard EIP-1271 check.
        return _verifyEIP1271(_signer, _hash, originalSignature);
    }
}
