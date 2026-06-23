// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IPOLErrors } from "src/pol/interfaces/IPOLErrors.sol";

interface IBGTIncentiveFeeCollector_V1 is IPOLErrors {
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

    /**
     * @notice Emitted when a new LST staker vault is added.
     * @param lstStakerVault The address of the LST staker vault.
     * @param lstAdapter The address of the LST adapter.
     */
    event LstStakerVaultAdded(address indexed lstStakerVault, address indexed lstAdapter);

    /**
     * @notice Emitted when a LST staker vault is removed.
     * @param lstStakerVault The address of the LST staker vault.
     */
    event LstStakerVaultRemoved(address indexed lstStakerVault);

    /**
     * @notice Emitted when a WBERA denominated reward is converted to LST.
     * @param lstStakerVault The address of the LST staker vault.
     * @param amountBera The amount of BERA being swapped.
     * @param amountLST The amount of LST received.
     */
    event RewardConverted(address indexed lstStakerVault, uint256 amountBera, uint256 amountLST);

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

    /**
     * @notice Get the size of the LST staker vault address array.
     * @return The length of the LST staker vault address array.
     */
    function lstStakerVaultsLength() external view returns (uint256);

    /**
     * @notice Getter for the LST staker vault address array.
     * @param index The index of the LST staker vault.
     * @return The LST staker vault address at the given index.
     */
    function lstStakerVaults(uint256 index) external view returns (address);

    /**
     * @notice Getter for the LST adapter address for a given LST staker vault.
     * @param lstStakerVault The address of the LST staker vault.
     * @return The LST adapter address for the given LST staker vault.
     */
    function lstAdapters(address lstStakerVault) external view returns (address);

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
     * @notice Add a new LST staker vault to be considered for incentive fee distribution.
     * @dev Can only be called by `DEFAULT_ADMIN_ROLE`.
     * @dev Only supports 18 decimals tokens.
     * @param lstStakerVault The address of the LST staker vault.
     * @param lstAdapter The address of the LST adapter.
     */
    function addLstStakerVault(address lstStakerVault, address lstAdapter) external;

    /**
     * @notice Remove an existing LST staker vault from the incentive fee distribution list.
     * @dev Can only be called by `DEFAULT_ADMIN_ROLE`.
     * @param lstStakerVault The address of the LST staker vault.
     */
    function removeLstStakerVault(address lstStakerVault) external;

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
