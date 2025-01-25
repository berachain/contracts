// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Each salt is unique and derived from the keccak256 hash of the contract name
// This ensures no collisions while maintaining deterministic addresses
uint256 constant WBERA_SALT = uint256(keccak256("WBERA_V1"));
uint256 constant BGT_SALT = uint256(keccak256("BGT_V1"));
uint256 constant BERA_CHEF_SALT = uint256(keccak256("BERA_CHEF_V1"));
uint256 constant BLOCK_REWARD_CONTROLLER_SALT = uint256(keccak256("BLOCK_REWARD_CONTROLLER_V1"));
uint256 constant DISTRIBUTOR_SALT = uint256(keccak256("DISTRIBUTOR_V1"));
uint256 constant REWARDS_FACTORY_SALT = uint256(keccak256("REWARDS_FACTORY_V1"));
uint256 constant BGT_STAKER_SALT = uint256(keccak256("BGT_STAKER_V1"));
uint256 constant FEE_COLLECTOR_SALT = uint256(keccak256("FEE_COLLECTOR_V1"));
