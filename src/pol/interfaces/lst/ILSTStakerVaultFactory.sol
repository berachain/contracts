// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IPOLErrors } from "../IPOLErrors.sol";

interface ILSTStakerVaultFactory is IPOLErrors {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STRUCTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Struct to hold the addresses of the created contract pairs.
    struct LSTAddresses {
        /// @notice The address of the vault.
        address vault;
        /// @notice The address of the withdrawal request contract (ERC721).
        address withdrawal721;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a new LST staker vault is created.
    /// @param stakingToken The address of the staking token.
    /// @param vault The address of the vault.
    event LSTStakerVaultCreated(address indexed stakingToken, address indexed vault);

    /// @notice Emitted when a new LST withdrawal request contract is created.
    /// @param stakingToken The address of the staking token.
    /// @param withdrawalContract The address of the withdrawal request contract (ERC721).
    event LSTStakerVaultWithdrawalRequestCreated(address indexed stakingToken, address indexed withdrawalContract);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ADMIN                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Creates a new pair LSTStakerVault (ERC4626) / LSTStakerVaultWithdrawalRequest (ERC721)
    /// to participate to BGTIncentiveFeeCollector redistribution.
    /// @dev Can only be called by `DEFAULT_ADMIN_ROLE`.
    /// @dev Only supports 18 decimals tokens.
    /// @param stakingToken The address of the staking token.
    /// @return The addresses of the new vault and withdrawal management contract.
    function createLSTStakerVaultSystem(address stakingToken) external returns (LSTAddresses memory);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          READS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Gets the vault for the given staking token.
    /// @param stakingToken The address of the staking token.
    /// @return The addresses of the vault and withdrawal management contract.
    function getLSTStakerContracts(address stakingToken) external view returns (LSTAddresses memory);

    /// @notice Gets the number of vaults and withdrawal contracts that have been created.
    /// @return The number of contract pairs.
    function allLSTStakerContractsLength() external view returns (uint256);

    /// @notice Predicts the address of the staker vault for the given staking token.
    /// @param stakingToken The address of the staking token.
    /// @return The address of the staker vault.
    function predictStakerVaultAddress(address stakingToken) external view returns (address);

    /// @notice Predicts the address of the withdrawal request contract for the given staking token.
    /// @param stakingToken The address of the staking token.
    /// @return The address of the withdrawal request contract.
    function predictWithdrawalRequestAddress(address stakingToken) external view returns (address);
}
