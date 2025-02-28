// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IBlockRewardController } from "src/pol/interfaces/IBlockRewardController.sol";

/// @notice A no-op implementation of the BlockRewardController.
contract NoopBlockRewardController is IBlockRewardController {
    /// @inheritdoc IBlockRewardController
    function baseRate() external pure returns (uint256) {
        return 0;
    }

    /// @inheritdoc IBlockRewardController
    function rewardRate() external pure returns (uint256) {
        return 0;
    }

    /// @inheritdoc IBlockRewardController
    function minBoostedRewardRate() external pure returns (uint256) {
        return 0;
    }

    /// @inheritdoc IBlockRewardController
    function boostMultiplier() external pure returns (uint256) {
        return 0;
    }

    /// @inheritdoc IBlockRewardController
    function rewardConvexity() external pure returns (int256) {
        return 0;
    }

    /// @inheritdoc IBlockRewardController
    function processRewards(bytes calldata, uint64, bool) external pure returns (uint256) {
        return 0;
    }

    /// @inheritdoc IBlockRewardController
    function computeReward(uint256, uint256, uint256, int256) external pure returns (uint256) {
        return 0;
    }

    /// @inheritdoc IBlockRewardController
    function getMaxBGTPerBlock() external pure returns (uint256) {
        return 0;
    }

    /// @inheritdoc IBlockRewardController
    function setBaseRate(uint256 _baseRate) external { }

    /// @inheritdoc IBlockRewardController
    function setRewardRate(uint256 _rewardRate) external { }

    /// @inheritdoc IBlockRewardController
    function setMinBoostedRewardRate(uint256 _minBoostedRewardRate) external { }

    /// @inheritdoc IBlockRewardController
    function setBoostMultiplier(uint256 _boostMultiplier) external { }

    /// @inheritdoc IBlockRewardController
    function setRewardConvexity(uint256 _rewardConvexity) external { }

    /// @inheritdoc IBlockRewardController
    function setDistributor(address _distributor) external { }

    /// @inheritdoc IBlockRewardController
    function setOperatorReceiver(bytes calldata pubkey, address _receiver) external { }
}
