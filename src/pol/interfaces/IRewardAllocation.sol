// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

interface IRewardAllocation {
    /// @notice Represents a RewardAllocation entry
    struct RewardAllocation {
        // The block this reward allocation goes into effect.
        uint64 startBlock;
        // The weights of the reward allocation.
        Weight[] weights;
    }

    /// @notice Represents a Weight entry
    struct Weight {
        // The address of the receiver that this weight is for.
        address receiver;
        // The fraction of rewards going to this receiver.
        // the percentage denominator is: ONE_HUNDRED_PERCENT = 10000
        // the actual fraction is: percentageNumerator / ONE_HUNDRED_PERCENT
        // e.g. percentageNumerator for 50% is 5000, because 5000 / 10000 = 0.5
        uint96 percentageNumerator;
    }
}
