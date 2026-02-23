/**
 * SPDX-License-Identifier: Apache-2.0
 *
 * Copyright (c) 2023, Circle Internet Financial, LLC.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * ---------------------------------------------------------------------
 *
 * Adapted and modified by Berachain for greater flexibility and reusability
 */
pragma solidity 0.8.26;

import { ERC20 } from "solady/src/tokens/ERC20.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title EIP-2612
 * @notice Provide implementation for gas-abstracted approvals with smart account support
 * @dev Extends ERC20 to use its EIP712 logic and EIP2612 nonce management.
 */
abstract contract EIP2612 is ERC20 {
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    /**
     * @notice Verify a signed approval permit and execute if valid
     * @dev Overrides Solady's permit to support smart account (EIP-1271) signatures.
     * @param owner     Token owner's address (Authorizer)
     * @param spender   Spender's address
     * @param value     Amount of allowance
     * @param deadline  The time at which the signature expires (unix time), or max uint256 value to signal no
     * expiration
     * @param v         v of the signature
     * @param r         r of the signature
     * @param s         s of the signature
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        public
        virtual
        override
    {
        _permit(owner, spender, value, deadline, abi.encodePacked(r, s, v));
    }

    /**
     * @notice Verify a signed approval permit and execute if valid (bytes signature version)
     * @dev EOA wallet signatures should be packed in the order of r, s, v.
     * @param owner      Token owner's address (Authorizer)
     * @param spender    Spender's address
     * @param value      Amount of allowance
     * @param deadline   The time at which the signature expires (unix time), or max uint256 value to signal no
     * expiration
     * @param signature  Signature byte array signed by an EOA wallet or a contract wallet
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        bytes memory signature
    )
        public
        virtual
    {
        _permit(owner, spender, value, deadline, signature);
    }

    /**
     * @notice Internal permit implementation with bytes signature
     * @param owner      Token owner's address (Authorizer)
     * @param spender    Spender's address
     * @param value      Amount of allowance
     * @param deadline   The time at which the signature expires (unix time), or max uint256 value to signal no
     * expiration
     * @param signature  Signature byte array signed by an EOA wallet or a contract wallet
     */
    function _permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        bytes memory signature
    )
        internal
    {
        if (deadline < block.timestamp) {
            revert PermitExpired();
        }

        bytes32 typedDataHash = MessageHashUtils.toTypedDataHash(
            DOMAIN_SEPARATOR(), keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces(owner), deadline))
        );
        _incrementNonce(owner);
        if (!SignatureChecker.isValidSignatureNow(owner, typedDataHash, signature)) {
            revert InvalidPermit();
        }

        _approve(owner, spender, value);
    }
}
