// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IPOLErrors } from "./IPOLErrors.sol";

interface IBGTIncentiveFeeCollector is IPOLErrors {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /**
     * @notice Emitted when the admin queues the payout amount.
     * @param queuedPayoutAmount The queued payout amount.
     * @param currentPayoutAmount The current payout amount.
     */
    event QueuedPayoutAmount(uint256 queuedPayoutAmount, uint256 currentPayoutAmount);

    /**
     * @notice Emitted when the payout amount is updated.
     * @param oldPayoutAmount The old payout amount.
     * @param newPayoutAmount The new payout amount.
     */
    event PayoutAmountSet(uint256 indexed oldPayoutAmount, uint256 indexed newPayoutAmount);

    /**
     * @notice Emitted when the incentive fees are claimed.
     * @param caller Caller of the `claimFees` function.
     * @param recipient The address to which collected incentive fees will be transferred.
     */
    event IncentiveFeesClaimed(address indexed caller, address indexed recipient);

    /**
     * @notice Emitted when the fee token is claimed.
     * @param caller Caller of the `claimFees` function.
     * @param recipient The address to which collected incentive fees will be transferred.
     * @param feeToken The address of the fee token to collect.
     * @param amount The amount of fee token to transfer.
     */
    event IncentiveFeeTokenClaimed(
        address indexed caller, address indexed recipient, address indexed feeToken, uint256 amount
    );

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           Getters                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Get the queued payout amount.
     * @return The queued payout amount.
     */
    function queuedPayoutAmount() external view returns (uint256);

    /**
     * @notice Get the current payout amount.
     * @return The current payout amount.
     */
    function payoutAmount() external view returns (uint256);

    /**
     * @notice Get the WBERA staker vault address.
     * @return The WBERA staker vault address.
     */
    function wberaStakerVault() external view returns (address);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    PERMISSIONED FUNCTIONS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Queue a payout amount change.
     * @dev Can only be called by `DEFAULT_ADMIN_ROLE`.
     * @param _newPayoutAmount The new payout amount.
     */
    function queuePayoutAmountChange(uint256 _newPayoutAmount) external;

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
    /*                  STATE MUTATING FUNCTION                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Claim collected incentive fees and transfer them to the recipient.
     * @dev Caller needs to pay the PAYOUT_AMOUNT of WBERA tokens.
     * @dev This function is NOT implementing slippage protection. Caller has to check that received amounts match the
     * minimum expected.
     * @param recipient The address to which collected incentive fees will be transferred.
     * @param incentiveFeeTokens The addresses of the incentive fee token to collect to the recipient.
     */
    function claimFees(address recipient, address[] calldata incentiveFeeTokens) external;
}
