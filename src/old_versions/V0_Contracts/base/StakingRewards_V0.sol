// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { Utils } from "src/libraries/Utils.sol";
import { IStakingRewards } from "src/base/IStakingRewards.sol";

/// @title StakingRewards_V0
/// @author Berachain Team
/// @notice Frozen base class used exclusively by old_versions contracts (V0–V9).
/// @dev Preserves the original `public rewardToken` state variable layout so that
/// old implementation snapshots compile unchanged. The current StakingRewards base
/// promotes `rewardToken` to an internal variable with a virtual getter to enable
/// per-vault overrides; old_versions do not need that capability.
abstract contract StakingRewards_V0 is Initializable, IStakingRewards {
    using Utils for bytes4;
    using SafeERC20 for IERC20;

    /// @notice Struct to hold account data.
    /// @param balance The balance of the staked tokens.
    /// @param unclaimedReward The amount of unclaimed rewards.
    /// @param rewardsPerTokenPaid The amount of rewards per token paid, scaled by PRECISION.
    struct Info {
        uint256 balance;
        uint256 unclaimedReward;
        uint256 rewardsPerTokenPaid;
    }

    uint256 internal constant PRECISION = 1e18;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice ERC20 token which users stake to earn rewards.
    IERC20 public stakeToken;

    /// @notice ERC20 token in which rewards are denominated and distributed.
    IERC20 public rewardToken;

    /// @notice The reward rate for the current reward period scaled by PRECISION.
    uint256 public rewardRate;

    /// @notice The amount of undistributed rewards scaled by PRECISION.
    uint256 public undistributedRewards;

    /// @notice The last updated reward per token scaled by PRECISION.
    uint256 public rewardPerTokenStored;

    /// @notice The total supply of the staked tokens.
    uint256 public totalSupply;

    /// @notice The end of the current reward period, where we need to start a new one.
    uint256 public periodFinish;

    /// @notice The time over which the rewards will be distributed. Current default is 7 days.
    uint256 public rewardsDuration;

    /// @notice The last time the rewards were updated.
    uint256 public lastUpdateTime;

    /// @notice The mapping of accounts to their data.
    mapping(address account => Info) internal _accountInfo;

    /// @dev This gap is used to prevent storage collisions.
    uint256[50] private __gap;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         INITIALIZER                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Must be called by the initializer of the inheriting contract.
    /// @param _stakingToken The address of the token that users will stake.
    /// @param _rewardToken The address of the token that will be distributed as rewards.
    /// @param _rewardsDuration The duration of the rewards cycle.
    function __StakingRewards_init(
        address _stakingToken,
        address _rewardToken,
        uint256 _rewardsDuration
    )
        internal
        onlyInitializing
    {
        stakeToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        rewardsDuration = _rewardsDuration;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier updateReward(address account) {
        _updateReward(account);
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  STATE MUTATING FUNCTIONS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Notifies the staking contract of a new reward transfer.
    /// @param reward The quantity of reward tokens being notified.
    /// @dev Only authorized notifiers should call this method to avoid griefing or false notifications.
    function _notifyRewardAmount(uint256 reward) internal virtual updateReward(address(0)) {
        reward = reward * PRECISION;

        if (totalSupply != 0 && block.timestamp < periodFinish) {
            reward += _computeLeftOverReward();
        }

        undistributedRewards += reward;
        _checkRewardSolvency();

        if (totalSupply != 0) {
            _setRewardRate();
            lastUpdateTime = block.timestamp;
        }

        emit RewardAdded(reward);
    }

    /// @notice Check if the rewards are solvent.
    /// @dev Inherited contracts may override this function to implement custom solvency checks.
    function _checkRewardSolvency() internal view virtual {
        if (undistributedRewards / PRECISION > rewardToken.balanceOf(address(this))) {
            InsolventReward.selector.revertWith();
        }
    }

    /// @notice Claims the reward for a specified account and transfers it to the specified recipient.
    /// @param account The account to claim the reward for.
    /// @param recipient The account to receive the reward.
    /// @return The amount of the reward claimed.
    function _getReward(address account, address recipient) internal virtual updateReward(account) returns (uint256) {
        Info storage info = _accountInfo[account];
        uint256 reward = info.unclaimedReward; // get the rewards owed to the account
        if (reward != 0) {
            info.unclaimedReward = 0;
            _safeTransferRewardToken(recipient, reward);
            emit RewardPaid(account, recipient, reward);
        }
        return reward;
    }

    /// @notice Safely transfers the reward tokens to the specified recipient.
    /// @dev Inherited contracts may override this function to implement custom transfer logic.
    /// @param to The recipient address.
    /// @param amount The amount of reward tokens to transfer.
    function _safeTransferRewardToken(address to, uint256 amount) internal virtual {
        rewardToken.safeTransfer(to, amount);
    }

    /// @notice Stakes tokens in the vault for a specified account.
    /// @param account The account to stake the tokens for.
    /// @param amount The amount of tokens to stake.
    function _stake(address account, uint256 amount) internal virtual {
        if (amount == 0) StakeAmountIsZero.selector.revertWith();

        // set the reward rate after the first stake if there are undistributed rewards
        if (totalSupply == 0 && undistributedRewards > 0) {
            _setRewardRate();
        }

        // update the rewards for the account after `rewardRate` is updated
        _updateReward(account);

        unchecked {
            uint256 totalSupplyBefore = totalSupply; // cache storage read
            uint256 totalSupplyAfter = totalSupplyBefore + amount;
            // `<=` and `<` are equivalent here but the former is cheaper
            if (totalSupplyAfter <= totalSupplyBefore) TotalSupplyOverflow.selector.revertWith();
            totalSupply = totalSupplyAfter;
            // `totalSupply` would have overflowed first because `totalSupplyBefore` >= `_accountInfo[account].balance`
            _accountInfo[account].balance += amount;
        }
        _safeTransferFromStakeToken(msg.sender, amount);
        emit Staked(account, amount);
    }

    /// @notice Safely transfers staking tokens from the sender to the contract.
    /// @dev Inherited contracts may override this function to implement custom transfer logic.
    /// @param from The address to transfer the tokens from.
    /// @param amount The amount of tokens to transfer.
    function _safeTransferFromStakeToken(address from, uint256 amount) internal virtual {
        stakeToken.safeTransferFrom(from, address(this), amount);
    }

    /// @notice Withdraws staked tokens from the vault for a specified account.
    /// @param account The account to withdraw the tokens for.
    /// @param amount The amount of tokens to withdraw.
    function _withdraw(address account, uint256 amount) internal virtual {
        if (amount == 0) WithdrawAmountIsZero.selector.revertWith();

        // update the rewards for the account before the balance is updated
        _updateReward(account);

        unchecked {
            Info storage info = _accountInfo[account];
            uint256 balanceBefore = info.balance; // cache storage read
            if (balanceBefore < amount) InsufficientStake.selector.revertWith();
            info.balance = balanceBefore - amount;
            // underflow not possible because `totalSupply` >= `balanceBefore` >= `amount`
            totalSupply -= amount;
        }
        if (totalSupply == 0 && block.timestamp < periodFinish) {
            undistributedRewards += _computeLeftOverReward();
        }
        _safeTransferStakeToken(msg.sender, amount);
        emit Withdrawn(account, amount);
    }

    /// @notice Safely transfers staking tokens to the specified recipient.
    /// @param to The recipient address.
    /// @param amount The amount of tokens to transfer.
    function _safeTransferStakeToken(address to, uint256 amount) internal virtual {
        stakeToken.safeTransfer(to, amount);
    }

    function _setRewardRate() internal virtual {
        uint256 _rewardsDuration = rewardsDuration; // cache storage read
        uint256 _rewardRate = undistributedRewards / _rewardsDuration;
        rewardRate = _rewardRate;
        periodFinish = block.timestamp + _rewardsDuration;
        undistributedRewards -= _rewardRate * _rewardsDuration;
    }

    function _updateReward(address account) internal virtual {
        uint256 _rewardPerToken = rewardPerToken(); // cache result
        rewardPerTokenStored = _rewardPerToken;
        // record the last time the rewards were updated
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            Info storage info = _accountInfo[account];
            (info.unclaimedReward, info.rewardsPerTokenPaid) = (earned(account), _rewardPerToken);
        }
    }

    /// @dev Allows to change `rewardsDuration` during the reward cycle, not affecting `rewardRate` which
    /// will be updated upon next `_notifyRewardAmount()` call.
    function _setRewardsDuration(uint256 _rewardsDuration) internal virtual {
        if (_rewardsDuration == 0) RewardsDurationIsZero.selector.revertWith();
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(_rewardsDuration);
    }

    /// @notice Returns the left over amount scaled by PRECISION.
    function _computeLeftOverReward() internal view returns (uint256 leftOver) {
        uint256 remainingTime;
        unchecked {
            remainingTime = periodFinish - block.timestamp;
        }
        leftOver = rewardRate * remainingTime;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          GETTERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function balanceOf(address account) public view virtual returns (uint256) {
        return _accountInfo[account].balance;
    }

    function rewards(address account) public view virtual returns (uint256) {
        return _accountInfo[account].unclaimedReward;
    }

    function userRewardPerTokenPaid(address account) public view virtual returns (uint256) {
        return _accountInfo[account].rewardsPerTokenPaid;
    }

    function lastTimeRewardApplicable() public view virtual returns (uint256) {
        return FixedPointMathLib.min(block.timestamp, periodFinish);
    }

    /// @dev Gives current reward per token, result is scaled by PRECISION.
    function rewardPerToken() public view virtual returns (uint256) {
        uint256 _totalSupply = totalSupply; // cache storage read
        if (_totalSupply == 0) return rewardPerTokenStored;
        uint256 timeDelta;
        unchecked {
            timeDelta = lastTimeRewardApplicable() - lastUpdateTime;
        }
        // computes reward per token by rounding it down to avoid reverting '_getReward' with insufficient rewards
        uint256 _newRewardPerToken = FixedPointMathLib.fullMulDiv(rewardRate, timeDelta, _totalSupply);
        return rewardPerTokenStored + _newRewardPerToken;
    }

    function earned(address account) public view virtual returns (uint256) {
        Info storage info = _accountInfo[account];
        (uint256 balance, uint256 unclaimedReward, uint256 rewardsPerTokenPaid) =
            (info.balance, info.unclaimedReward, info.rewardsPerTokenPaid);
        uint256 rewardPerTokenDelta;
        unchecked {
            rewardPerTokenDelta = rewardPerToken() - rewardsPerTokenPaid;
        }
        return unclaimedReward + FixedPointMathLib.fullMulDiv(balance, rewardPerTokenDelta, PRECISION);
    }

    function getRewardForDuration() public view virtual returns (uint256) {
        return FixedPointMathLib.fullMulDiv(rewardRate, rewardsDuration, PRECISION);
    }
}
