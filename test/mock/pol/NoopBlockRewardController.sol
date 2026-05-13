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
    function processRewards(bytes calldata, uint64, bool) external pure returns (uint256) {
        return 0;
    }

    /// @inheritdoc IBlockRewardController
    function getMaxBGTPerBlock() external pure returns (uint256) {
        return 0;
    }

    /// @inheritdoc IBlockRewardController
    function getMaxEmissionPerBlock() external pure returns (uint256) {
        return 0;
    }

    /// @inheritdoc IBlockRewardController
    function setDistributor(address _distributor) external { }

    /// @inheritdoc IBlockRewardController
    function burnExceedingBalance() external { }
}
