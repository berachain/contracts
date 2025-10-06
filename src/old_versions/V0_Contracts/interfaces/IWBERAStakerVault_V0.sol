// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IPOLErrors } from "src/pol/interfaces/IPOLErrors.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IWBERAStakerVault_V0 is IPOLErrors {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         EVENTS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Emitted when a token has been recovered.
     * @param token The token that has been recovered.
     * @param amount The amount of token recovered.
     */
    event ERC20Recovered(address token, uint256 amount);

    /**
     * @notice Emitted when a withdrawal request is made.
     * @param sender The account that made the withdrawal request.
     * @param receiver The address to receive the shares.
     * @param owner The address that owns the shares.
     * @param assets The amount of assets requested to be withdrawn.
     * @param shares The amount of shares burnt.
     */
    event WithdrawalRequested(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    /**
     * @notice Emitted when a withdrawal is completed.
     * @param sender The account that made the withdrawal.
     * @param receiver The address to receive the shares.
     * @param owner The address that owns the shares.
     * @param assets The amount of assets requested to be withdrawn.
     * @param shares The amount of shares burnt while requesting the withdrawal.
     */
    event WithdrawalCompleted(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        ADMIN FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Recover ERC20 tokens.
     * @dev Recovering WBERA is not allowed.
     * @dev Can only be called by `DEFAULT_ADMIN_ROLE`.
     * @param tokenAddress The address of the token to recover.
     * @param tokenAmount The amount of token to recover.
     */
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external;

    /**
     * @notice Pause the contract.
     * @dev Can only be called by `PAUSER_ROLE`.
     */
    function pause() external;

    /**
     * @notice Unpause the contract.
     * @dev Can only be called by `MANAGER_ROLE`.
     */
    function unpause() external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  STATE MUTATING FUNCTIONS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Deposit BERA.
     * @dev Allows depositing BERA in the vault, msg.value must be equal to amount.
     * @param assets The amount of BERA to deposit.
     * @param receiver The address to receive the shares.
     * @return The amount of shares received.
     */
    function depositNative(uint256 assets, address receiver) external payable returns (uint256);

    /**
     * @notice Complete a requested withdrawal.
     * @dev Allows completing a requested withdrawal.
     * @dev Only the caller of `withdraw`/`redeem` can complete the withdrawal.
     * @param isNative Whether the withdrawal is in native currency.
     */
    function completeWithdrawal(bool isNative) external;
}
