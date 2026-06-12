// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IPOLErrors } from "./IPOLErrors.sol";

interface IRewardVaultHelper is IPOLErrors {
    /// @notice Emitted when the sWBERA address is set.
    /// @param sWBERA The address of the sWBERA token.
    event SWBERASet(address sWBERA);

    /// @notice Emitted when rewards are claimed.
    /// @param amount The amount of rewards claimed.
    /// @param receiver The address to receive the rewards.
    /// @param outputToken The token to convert the rewards to.
    event RewardsClaimed(uint256 amount, address receiver, address outputToken);

    /// @notice Claim all rewards from multiple vaults.
    /// @dev Reverts if any of the vaults do not implement the Berachain Reward Vault interface.
    /// @param vaults The array of vault addresses.
    /// @param receiver The address to receive the rewards.
    function claimAllRewards(address[] memory vaults, address receiver) external;

    /// @notice Claim all rewards from multiple vaults and convert them to a specific token.
    /// @dev Reverts if any of the vaults do not implement the Berachain Reward Vault interface.
    /// @dev Reverts if the output token is not a valid token (WBERA, sWBERA, or native BERA (address(0))).
    /// @param vaults The array of vault addresses.
    /// @param receiver The address to receive the rewards.
    /// @param outputToken The token to convert the rewards to.
    function claimAllRewards(address[] memory vaults, address receiver, address outputToken) external;

    /// @notice Withdraw the caller's self-staked balance from multiple vaults in a single transaction.
    /// @dev Skips vaults where the caller has no self-staked balance. Delegate-staked amounts are not withdrawn.
    /// @param vaults The array of vault addresses.
    /// @param receiver The address to receive the withdrawn stake tokens.
    function withdrawAllFromVaults(address[] memory vaults, address receiver) external;
}
