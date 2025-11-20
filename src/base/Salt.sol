// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Container for the deployment salts of a contract.
struct Salt {
    uint256 proxy;
    uint256 implementation;
}
