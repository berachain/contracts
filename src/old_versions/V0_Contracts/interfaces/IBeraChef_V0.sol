// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IPOLErrors } from "src/pol/interfaces/IPOLErrors.sol";

/// @notice Interface of the BeraChef module
interface IBeraChef_V0 is IPOLErrors {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STRUCTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

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

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when the maximum number of weights per reward allocation has been set.
    /// @param maxNumWeightsPerRewardAllocation The maximum number of weights per reward allocation.
    event MaxNumWeightsPerRewardAllocationSet(uint8 maxNumWeightsPerRewardAllocation);

    /// @notice Emitted when the delay in blocks before a new reward allocation can go into effect has been set.
    /// @param rewardAllocationBlockDelay The delay in blocks before a new reward allocation can go into effect.
    event RewardAllocationBlockDelaySet(uint64 rewardAllocationBlockDelay);

    /// @notice Emitted when the vault's whitelisted status have been updated.
    /// @param receiver The address to remove or add as whitelisted vault.
    /// @param isWhitelisted The whitelist status; true if the receiver is being whitelisted, false otherwise.
    /// @param metadata The metadata of the vault.
    event VaultWhitelistedStatusUpdated(address indexed receiver, bool indexed isWhitelisted, string metadata);

    /**
     * @notice Emitted when the metadata of a whitelisted vault has been updated.
     * @param receiver The address of the whitelisted vault.
     * @param metadata The metadata of the vault.
     */
    event WhitelistedVaultMetadataUpdated(address indexed receiver, string metadata);

    /**
     * @notice Emitted when a new reward allocation has been queued.
     * @param valPubkey The validator's pubkey.
     * @param startBlock The block that the reward allocation goes into effect.
     * @param weights The weights of the reward allocation.
     */
    event QueueRewardAllocation(bytes indexed valPubkey, uint64 startBlock, Weight[] weights);

    /**
     * @notice Emitted when a new reward allocation has been activated.
     * @param valPubkey The validator's pubkey.
     * @param startBlock The block that the reward allocation goes into effect.
     * @param weights The weights of the reward allocation.
     */
    event ActivateRewardAllocation(bytes indexed valPubkey, uint64 startBlock, Weight[] weights);

    /**
     * @notice Emitted when the governance module has set a new default reward allocation.
     * @param rewardAllocation The default reward allocation.
     */
    event SetDefaultRewardAllocation(RewardAllocation rewardAllocation);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          GETTERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Returns the active reward allocation for validator with given pubkey
     * @param valPubkey The validator's pubkey.
     * @return rewardAllocation The active reward allocation.
     */
    function getActiveRewardAllocation(bytes calldata valPubkey) external view returns (RewardAllocation memory);

    /**
     * @notice Returns the queued reward allocation for a validator with given pubkey
     * @param valPubkey The validator's pubkey.
     * @return rewardAllocation The queued reward allocation.
     */
    function getQueuedRewardAllocation(bytes calldata valPubkey) external view returns (RewardAllocation memory);

    /**
     * @notice Returns the active reward allocation set by the validator with given pubkey.
     * @dev This will return active reward allocation set by validators even if its not valid.
     * @param valPubkey The validator's pubkey.
     * @return rewardAllocation The reward allocation.
     */
    function getSetActiveRewardAllocation(bytes calldata valPubkey) external view returns (RewardAllocation memory);

    /**
     * @notice Returns the default reward allocation for validators that do not have a reward allocation.
     * @return rewardAllocation The default reward allocation.
     */
    function getDefaultRewardAllocation() external view returns (RewardAllocation memory);

    /**
     * @notice Returns the status of whether a queued reward allocation is ready to be activated.
     * @param valPubkey The validator's pubkey.
     * @param blockNumber The block number to be queried.
     * @return isReady True if the queued reward allocation is ready to be activated, false otherwise.
     */
    function isQueuedRewardAllocationReady(
        bytes calldata valPubkey,
        uint256 blockNumber
    )
        external
        view
        returns (bool);

    /**
     * @notice Returns the status of whether the BeraChef contract is ready to be used.
     * @dev This function should be used by all contracts that depend on a system call.
     * @dev This will return false if the governance module has not set a default reward allocation yet.
     * @return isReady True if the BeraChef is ready to be used, false otherwise.
     */
    function isReady() external view returns (bool);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Sets the maximum number of weights per reward allocation.
    function setMaxNumWeightsPerRewardAllocation(uint8 _maxNumWeightsPerRewardAllocation) external;

    /// @notice Sets the delay in blocks before a new reward allocation can be queued.
    function setRewardAllocationBlockDelay(uint64 _rewardAllocationBlockDelay) external;

    /**
     * @notice Updates the vault's whitelisted status
     * @notice The caller of this function must be the governance module account.
     * @param receiver The address to remove or add as whitelisted vault.
     * @param isWhitelisted The whitelist status; true if the receiver is being whitelisted, false otherwise.
     * @param metadata The metadata of the vault.
     */
    function setVaultWhitelistedStatus(address receiver, bool isWhitelisted, string memory metadata) external;

    /**
     * @notice Updates the metadata of a whitelisted vault, reverts if vault is not whitelisted.
     * @notice The caller of this function must be the governance module account.
     * @param receiver The address of the whitelisted vault.
     * @param metadata The metadata of the vault, to associate info with the vault in the events log.
     */
    function updateWhitelistedVaultMetadata(address receiver, string memory metadata) external;

    /**
     * @notice Sets the default reward allocation for validators that do not have a reward allocation.
     * @dev The caller of this function must be the governance module account.
     * @param rewardAllocation The default reward allocation.
     */
    function setDefaultRewardAllocation(RewardAllocation calldata rewardAllocation) external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          SETTERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Add a new reward allocation to the queue for validator with given pubkey. Does not allow overwriting of
     * existing queued reward allocation.
     * @dev The weights of the reward allocation must add up to 100% or 1e4.
     * Only whitelisted pools may be used as well.
     * @param valPubkey The validator's pubkey.
     * @param startBlock The block that the reward allocation goes into effect.
     * @param weights The weights of the reward allocation.
     */
    function queueNewRewardAllocation(
        bytes calldata valPubkey,
        uint64 startBlock,
        Weight[] calldata weights
    )
        external;

    /// @notice Activates the queued reward allocation for a validator if its ready for the current block.
    /// @dev Should be called by the distribution contract.
    /// @param valPubkey The validator's pubkey.
    function activateReadyQueuedRewardAllocation(bytes calldata valPubkey) external;
}
