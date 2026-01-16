// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IPOLErrors } from "src/pol/interfaces/IPOLErrors.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IStakerVaultWithdrawalRequest } from "./IStakerVaultWithdrawalRequest.sol";

interface IStakerVault is IPOLErrors {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         EVENTS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a token has been recovered.
    /// @param token The token that has been recovered.
    /// @param amount The amount of token recovered.
    event ERC20Recovered(address token, uint256 amount);

    /// @notice Emitted when rewards are received.
    /// @param sender The account that sent the rewards.
    /// @param amount The amount of rewards received.
    event RewardsReceived(address indexed sender, uint256 indexed amount, uint256 totalAssets);

    /// @notice Emitted when a withdrawal request is made.
    /// @param sender The account that made the withdrawal request.
    /// @param receiver The address to receive the shares.
    /// @param owner The address that owns the shares.
    /// @param assets The amount of assets requested to be withdrawn.
    /// @param shares The amount of shares burnt.
    event WithdrawalRequested(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    /// @notice Emitted when a withdrawal request is cancelled.
    /// @param sender The account that owned the NFT of the withdrawal request.
    /// @param owner The address that owned the shares.
    /// @param assets The amount of assets corresponding to the queued withdrawal.
    /// @param shares The amount of shares burnt during the withdrawal request enqueuing.
    /// @param newSharesMinted The amount of shares minted back to the NFT owner.
    event WithdrawalCancelled(
        address indexed sender, address indexed owner, uint256 assets, uint256 shares, uint256 newSharesMinted
    );

    /// @notice Emitted when a withdrawal is completed.
    /// @param sender The account that made the withdrawal.
    /// @param receiver The address to receive the shares.
    /// @param owner The address that owns the shares.
    /// @param assets The amount of assets requested to be withdrawn.
    /// @param shares The amount of shares burnt while requesting the withdrawal.
    event WithdrawalCompleted(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        ADMIN FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Recover ERC20 tokens.
    /// @dev Recovering the staking token is not allowed.
    /// @dev Can only be called by the factory admin.
    /// @param tokenAddress The address of the token to recover.
    /// @param tokenAmount The amount of token to recover.
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external;

    /// @notice Pause the contract.
    /// @dev Can only be called by the factory pauser.
    function pause() external;

    /// @notice Unpause the contract.
    /// @dev Can only be called by the factory manager.
    function unpause() external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  STATE MUTATING FUNCTIONS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Receive rewards.
    /// @dev Rewards are received from `BGTIncentiveFeeCollector` contract and this function is being introduced
    /// for better tracking of rewards.
    /// @param amount The amount of rewards to receive.
    function receiveRewards(uint256 amount) external;

    /// @notice Queue a withdrawal request, with the amount of shares to withdraw.
    /// @dev Burns the shares to not allow farming during the cooldown period.
    /// @param shares The amount of shares to withdraw.
    /// @param receiver The address to receive the shares.
    /// @param owner The address that owns the shares.
    /// @return assets The amount of staked tokens to withdraw.
    /// @return withdrawalId The ID of the withdrawal request created.
    function queueRedeem(
        uint256 shares,
        address receiver,
        address owner
    )
        external
        returns (uint256 assets, uint256 withdrawalId);

    /// @notice Queue a withdrawal request, with the amount of assets to receive.
    /// @dev Burns the shares to not allow farming during the cooldown period.
    /// @param assets The amount of assets to withdraw.
    /// @param receiver The address to receive the shares.
    /// @param owner The address that owns the shares.
    /// @return shares The amount of shares burnt for the withdrawal.
    /// @return withdrawalId The ID of the withdrawal request created.
    function queueWithdraw(
        uint256 assets,
        address receiver,
        address owner
    )
        external
        returns (uint256 shares, uint256 withdrawalId);

    /// @notice Cancel a queued withdrawal request.
    /// @dev Can only be called by the NFT owner.
    /// @dev If the exchange rate changes, cancelling a withdrawal request will not mint the same number of shares that
    /// were burned when the request was enqueued.
    /// During the cooldown period, no rewards accrue; upon cancellation, shares are minted so their value equals the
    /// fixed underlying asset amount captured at request time, using the current exchange rate.
    /// Example: if a user requests to withdraw 10 shares at a 1:1 rate (locking in 10 assets) and later cancels when
    /// the exchange rate is 2, they receive 5 shares, since 5 shares represent the same 10 assets at cancellation.
    /// @param requestId The ID of the withdrawal request to cancel.
    function cancelQueuedWithdrawal(uint256 requestId) external;

    /// @notice Complete a requested withdrawal with a specific LSTStakerVaultWithdrawalRequest ID.
    /// @dev Permissionless, so not mandatory to call it by token owner, which is the `caller` of queue methods.
    /// @param requestId The ID of the withdrawal request to complete.
    function completeWithdrawal(uint256 requestId) external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        VIEW FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns the withdrawal cooldown period.
    /// @dev Reads the withdrawal cooldown period from the WithdrawalRequestERC721 contract.
    function WITHDRAWAL_COOLDOWN() external view returns (uint256);

    /// @notice Returns the reserved assets amount (part of the balance reserved for ongoing withdrawals).
    /// @return The amount of reserved assets.
    function reservedAssets() external view returns (uint256);

    /// @notice Returns the withdrawal request with the given ID.
    /// @dev This is a helper function to get the withdrawal request from the WithdrawalRequestERC721 contract.
    /// @dev This returns empty struct if the request does not exist.
    /// @param requestId The ID of the withdrawal request to retrieve.
    /// @return The withdrawal request with the given ID.
    function getERC721WithdrawalRequest(uint256 requestId)
        external
        view
        returns (IStakerVaultWithdrawalRequest.WithdrawalRequest memory);

    /// @notice Returns the number of active withdrawal requests created by the user.
    /// @dev This is a helper function to get the number of active withdrawal requests created by the user.
    /// @param user The address of the user to get the number of withdrawal requests for.
    /// @return The number of active withdrawal requests created by the user.
    function getUserERC721WithdrawalRequestCount(address user) external view returns (uint256);

    /// @notice Returns the IDs of the active withdrawal requests created by the user.
    /// @dev This is a helper function to get the IDs of the active withdrawal requests created by the user.
    /// @param user The address of the user to get the IDs of the withdrawal requests for.
    /// @return The IDs of the active withdrawal requests created by the user.
    function getERC721WithdrawalRequestIds(address user) external view returns (uint256[] memory);

    /// @notice Returns a paginated slice of IDs of the active withdrawal requests created by the user.
    /// @dev Uses `IERC721Enumerable.tokenOfOwnerByIndex` for enumeration.
    /// @param user The address of the user to get the IDs of the withdrawal requests for.
    /// @param offset The starting index within the user's tokens.
    /// @param limit The maximum number of IDs to return.
    /// @return ids The paginated list of withdrawal request IDs.
    function getERC721WithdrawalRequestIds(
        address user,
        uint256 offset,
        uint256 limit
    )
        external
        view
        returns (uint256[] memory);
}
