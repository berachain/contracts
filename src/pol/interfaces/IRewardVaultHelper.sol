// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IPOLErrors } from "./IPOLErrors.sol";

interface IRewardVaultHelper is IPOLErrors {
    /// @notice Claim all rewards from multiple vaults.
    /// @dev Reverts if any of the vaults do not implement the Berachain Reward Vault interface.
    /// @param vaults The array of vault addresses.
    /// @param receiver The address to receive the rewards.
    function claimAllRewards(address[] memory vaults, address receiver) external;
}
