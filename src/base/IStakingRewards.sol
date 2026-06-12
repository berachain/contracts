// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IStakingRewardsErrors } from "./IStakingRewardsErrors.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Interface of staking rewards
interface IStakingRewards is IStakingRewardsErrors {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a reward has been added to the vault.
    /// @param reward The amount of reward added, scaled by PRECISION.
    event RewardAdded(uint256 reward);

    /// @notice Emitted when the staking balance of an account has increased.
    /// @param account The account that has staked.
    /// @param amount The amount of staked tokens.
    event Staked(address indexed account, uint256 amount);

    /// @notice Emitted when the staking balance of an account has decreased.
    /// @param account The account that has withdrawn.
    /// @param amount The amount of withdrawn tokens.
    event Withdrawn(address indexed account, uint256 amount);

    /// @notice Emitted when a reward has been claimed.
    /// @param account The account whose reward has been claimed.
    /// @param to The address that the reward was sent to. (user or operator).
    /// @param reward The amount of reward claimed.
    event RewardPaid(address indexed account, address to, uint256 reward);

    /// @notice Emitted when the reward duration has been updated.
    /// @param newDuration The new duration of the reward.
    event RewardsDurationUpdated(uint256 newDuration);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          GETTERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The ERC20 token which users stake to earn rewards.
    function stakeToken() external view returns (IERC20);

    /// @notice Get the balance of the staked tokens for an account.
    /// @param account The account to get the balance for.
    /// @return The balance of the staked tokens.
    function balanceOf(address account) external view returns (uint256);

    /// @notice Get the reward balance for a specific account.
    /// @param account The account to retrieve the reward balance for.
    /// @return The current reward balance of the specified account.
    function rewards(address account) external view returns (uint256);

    /// @notice Get the user reward per token paid.
    /// @param account The account to retrieve the reward for.
    /// @return The current reward balance of the specified account.
    function userRewardPerTokenPaid(address account) external view returns (uint256);

    /// @notice Retrieves the amount of reward earned by a specific account.
    /// @param account The account to calculate the reward for.
    /// @return The amount of reward earned by the account.
    function earned(address account) external view returns (uint256);

    /// @notice Retrieves the total reward vested over the specified duration.
    /// @return The total reward vested over the duration.
    function getRewardForDuration() external view returns (uint256);

    /// @notice Returns the timestamp of the last reward distribution. This is either the current timestamp (if rewards
    /// are still being actively distributed) or the timestamp when the reward duration ended (if all rewards have
    /// already been distributed).
    /// @return The timestamp of the last reward distribution.
    function lastTimeRewardApplicable() external view returns (uint256);

    /// @notice Retrieves the current value of the global reward per token accumulator. This value is the sum of the
    /// last checkpoint value and the accumulated value since the last checkpoint. It should increase monotonically
    /// over time as more rewards are distributed.
    /// @return The current value of the global reward per token accumulator scaled by 1e18.
    function rewardPerToken() external view returns (uint256);

    /// @notice Get the total supply of the staked tokens in the vault.
    /// @return The total supply of the staked tokens in the vault.
    function totalSupply() external view returns (uint256);

    /// @notice Get the end of the current reward period.
    /// @return The end of the current reward period.
    function periodFinish() external view returns (uint256);

    /// @notice Get the reward rate for the current reward period.
    /// @return The reward rate.
    function rewardRate() external view returns (uint256);

    /// @notice Get the time over which the rewards will be distributed.
    /// @return The duration of the rewards cycle.
    function rewardsDuration() external view returns (uint256);

    /// @notice Get the last time the rewards were updated.
    /// @return The last time the rewards were updated.
    function lastUpdateTime() external view returns (uint256);

    /// @notice Get the amount of undistributed rewards.
    /// @return The amount of undistributed rewards.
    function undistributedRewards() external view returns (uint256);

    /// @notice Get the last updated reward per token scaled.
    /// @return The last updated reward per token.
    function rewardPerTokenStored() external view returns (uint256);
}
