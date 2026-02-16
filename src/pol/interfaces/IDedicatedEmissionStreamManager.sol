// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IPOLErrors } from "./IPOLErrors.sol";
import { IRewardAllocation } from "./IRewardAllocation.sol";

/// @notice Interface of the DedicatedEmissionStreamManager contract.
interface IDedicatedEmissionStreamManager is IRewardAllocation, IPOLErrors {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when the distributor address is set.
    /// @param distributor The address of the new distributor.
    event DistributorSet(address distributor);

    /// @notice Emitted when the beraChef address is set.
    /// @param beraChef The address of the new beraChef.
    event BeraChefSet(address beraChef);

    /// @notice Emitted when the reward allocation percentage is set.
    /// @param newEmissionPerc The new allocation percentage (basis points, 1e4 = 100%).
    event EmissionPercSet(uint96 newEmissionPerc);

    /// @notice Emitted when the reward allocation is set.
    /// @param newRewardAllocation The new reward allocation weights.
    event RewardAllocationSet(Weight[] newRewardAllocation);

    /// @notice Emitted when the target emission is set for a vault.
    /// @param vault The target vault address receiving the emission.
    /// @param targetEmission The target emission for the vault.
    event TargetEmissionSet(address indexed vault, uint256 targetEmission);

    /// @notice Emitted when an emission is notified for a vault.
    /// @param vault The target vault address receiving the emission.
    /// @param amount The amount of emission notified.
    event NotifyEmission(address indexed vault, uint256 amount);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          GETTERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Gets the percentage (in basis points, 1e4 = 100%) of rewards allocated to the reward allocation.
    /// @return The reward allocation percentage.
    function emissionPerc() external view returns (uint96);

    /// @notice Returns the current reward allocation weights.
    /// @return The array of Weight structs representing the allocation.
    function getRewardAllocation() external view returns (Weight[] memory);

    /// @notice Gets the emission amount capped by the target for a vault.
    /// @param vault The vault address to get the emission amount for.
    /// @param emission The amount to cap.
    /// @return The maximum emission for the vault.
    function getMaxEmission(address vault, uint256 emission) external view returns (uint256);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         SETTERS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Sets the percentage (in basis points, 1e4 = 100%) of rewards allocated to the reward allocation.
    /// @param _emissionPerc The new reward allocation percentage (basis points).
    function setEmissionPerc(uint96 _emissionPerc) external;

    /// @notice Sets the reward allocation.
    /// @param _rewardAllocation The array of Weight structs for the new allocation.
    function setRewardAllocation(Weight[] memory _rewardAllocation) external;

    /// @notice Sets the target emission for a vault.
    /// @dev The target emission must be greater than the current debt of the vault.
    /// @dev If a previous dedicated emission stream ended a new stream must start from the current debt.
    /// @param vault The target vault address receiving the emission.
    /// @param _targetEmission The target emission for the vault.
    function setTargetEmission(address vault, uint256 _targetEmission) external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     ADMIN FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Sets the distributor address.
    /// @param _distributor The new distributor address.
    function setDistributor(address _distributor) external;

    /// @notice Sets the beraChef address.
    /// @param _beraChef The new beraChef address.
    function setBeraChef(address _beraChef) external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   DISTRIBUTOR FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Notify the emission amount for a vault.
    /// @param vault The vault address to notify.
    /// @param amount The emission amount to notify.
    function notifyEmission(address vault, uint256 amount) external;
}
