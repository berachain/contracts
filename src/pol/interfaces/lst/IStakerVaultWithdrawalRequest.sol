// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IPOLErrors } from "src/pol/interfaces/IPOLErrors.sol";

interface IStakerVaultWithdrawalRequest is IPOLErrors {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a withdrawal request is created.
    /// @param requestId The ID of the withdrawal request.
    event WithdrawalRequestCreated(uint256 indexed requestId);

    /// @notice Emitted when a withdrawal request is finalized and burnt.
    /// @param requestId The ID of the withdrawal request that was finalized.
    event WithdrawalRequestCompleted(uint256 requestId);

    /// @notice Emitted when a withdrawal request is cancelled.
    /// @param requestId The ID of the withdrawal request that was cancelled.
    event WithdrawalRequestCancelled(uint256 requestId);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           STRUCTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Represents a withdrawal request.
    /// @param assets The amount of BERA required for the withdrawal.
    /// @param shares The amount of shares burned for the withdrawal.
    /// @param requestTimestamp The block number when the withdrawal request was made.
    /// @param owner The address of the user owning the shares requested for the withdrawal.
    /// @param receiver The address that will receive the withdrawn assets.
    struct WithdrawalRequest {
        uint256 assets;
        uint256 shares;
        uint256 requestTime;
        address owner;
        address receiver;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          FUNCTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Mints a withdrawal request with given information.
    /// @dev Can only be called by the Staker Vault.
    /// @param caller The address that initiated the withdrawal request, and will own the token.
    /// @param receiver The address that will receive the withdrawn assets.
    /// @param owner The address of the user owning the shares requested for the withdrawal.
    /// @param assets The amount of BERA requested for withdrawal.
    /// @param shares The amount of burnt shares.
    /// @return requestId The ID of the withdrawal request created.
    function mint(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    )
        external
        returns (uint256 requestId);

    /// @notice Completes a withdrawal request burning the associated NFT.
    /// @dev Can only be called by the Staker Vault.
    /// @param requestId The ID of the withdrawal request to burn.
    function burn(uint256 requestId) external;

    /// @notice Cancels a withdrawal request burning the associated NFT.
    /// @dev Can only be called by the Staker Vault.
    /// @param requestId The ID of the withdrawal request to cancel.
    function cancel(uint256 requestId) external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          GETTERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns the withdrawal cooldown period.
    function WITHDRAWAL_COOLDOWN() external view returns (uint256);

    /// @notice Returns the withdrawal request with the given ID.
    /// @param requestId The ID of the withdrawal request to retrieve.
    /// @return The withdrawal request with the given ID.
    function getRequest(uint256 requestId) external view returns (WithdrawalRequest memory);
}
