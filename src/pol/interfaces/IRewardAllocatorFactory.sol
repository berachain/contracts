// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IPOLErrors } from "../interfaces/IPOLErrors.sol";
import { IBeraChef } from "../interfaces/IBeraChef.sol";
import { IRewardAllocation } from "./IRewardAllocation.sol";

interface IRewardAllocatorFactory is IPOLErrors {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          EVENTS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when the baseline reward allocation has been set.
    /// @param weights The weights of the baseline reward allocation.
    event BaselineAllocationSet(IRewardAllocation.Weight[] weights);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          ADMIN                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Sets the baseline reward allocation.
    /// @dev Only callable by admin.
    /// @param weights The weights of the reward allocation.
    function setBaselineAllocation(IRewardAllocation.Weight[] calldata weights) external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          READS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function getBaselineAllocation() external view returns (IRewardAllocation.RewardAllocation memory);
}
