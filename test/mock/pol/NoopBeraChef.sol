// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IBeraChef } from "src/pol/interfaces/IBeraChef.sol";

/// @notice A no-op implementation of the BeraChef.
contract NoopBeraChef is IBeraChef {
    /// @inheritdoc IBeraChef
    function getActiveRewardAllocation(bytes calldata) external pure returns (RewardAllocation memory) {
        return RewardAllocation({ weights: new Weight[](0), startBlock: 0 });
    }

    /// @inheritdoc IBeraChef
    function getQueuedRewardAllocation(bytes calldata) external pure returns (RewardAllocation memory) {
        return RewardAllocation({ weights: new Weight[](0), startBlock: 0 });
    }

    /// @inheritdoc IBeraChef
    function getSetActiveRewardAllocation(bytes calldata) external pure returns (RewardAllocation memory) {
        return RewardAllocation({ weights: new Weight[](0), startBlock: 0 });
    }

    /// @inheritdoc IBeraChef
    function getDefaultRewardAllocation() external pure returns (RewardAllocation memory) {
        return RewardAllocation({ weights: new Weight[](0), startBlock: 0 });
    }

    /// @inheritdoc IBeraChef
    function isQueuedRewardAllocationReady(bytes calldata, uint256) external pure returns (bool) {
        return false;
    }

    /// @inheritdoc IBeraChef
    function isReady() external pure returns (bool) {
        return false;
    }

    /// @inheritdoc IBeraChef
    function getValQueuedCommissionOnIncentiveTokens(bytes calldata)
        external
        pure
        returns (QueuedCommissionRateChange memory)
    {
        return QueuedCommissionRateChange({ blockNumberLast: 0, commissionRate: 0 });
    }

    /// @inheritdoc IBeraChef
    function getValCommissionOnIncentiveTokens(bytes calldata) external pure returns (uint96) {
        return 0;
    }

    /// @inheritdoc IBeraChef
    function getValidatorIncentiveTokenShare(bytes calldata, uint256) external pure returns (uint256) {
        return 0;
    }

    /// @inheritdoc IBeraChef
    function setMaxNumWeightsPerRewardAllocation(uint8) external pure { }

    /// @inheritdoc IBeraChef
    function setMaxWeightPerVault(uint96) external pure { }

    /// @inheritdoc IBeraChef
    function setRewardAllocationBlockDelay(uint64) external pure { }

    /// @inheritdoc IBeraChef
    function setVaultWhitelistedStatus(address, bool, string memory) external pure { }

    /// @inheritdoc IBeraChef
    function updateWhitelistedVaultMetadata(address receiver, string memory) external pure { }

    /// @inheritdoc IBeraChef
    function setDefaultRewardAllocation(RewardAllocation calldata) external pure { }

    /// @inheritdoc IBeraChef
    function queueNewRewardAllocation(bytes calldata, uint64, Weight[] calldata) external pure { }

    /// @inheritdoc IBeraChef
    function activateReadyQueuedRewardAllocation(bytes calldata) external pure { }

    /// @inheritdoc IBeraChef
    function setCommissionChangeDelay(uint64) external pure { }
    /// @inheritdoc IBeraChef
    function queueValCommission(bytes calldata, uint96) external pure { }

    /// @inheritdoc IBeraChef
    function activateQueuedValCommission(bytes calldata) external pure { }
}
