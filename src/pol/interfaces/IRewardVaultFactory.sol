// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IPOLErrors } from "../interfaces/IPOLErrors.sol";

interface IRewardVaultFactory is IPOLErrors {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          EVENTS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Emitted when a new vault is created.
     * @param stakingToken The address of the staking token.
     * @param vault The address of the vault.
     */
    event VaultCreated(address indexed stakingToken, address indexed vault);

    /**
     * @notice Emitted when the incentive tokens collector address is updated.
     * @param newAddress The new address for incentive tokens collector.
     * @param oldAddress The old address for incentive tokens collector.
     */
    event IncentiveTokensCollectorUpdated(address newAddress, address oldAddress);

    /**
     * @notice Emitted when the reward vault helper address is updated.
     * @param newAddress The new address for reward vault helper.
     * @param oldAddress The old address for reward vault helper.
     */
    event RewardVaultHelperUpdated(address newAddress, address oldAddress);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          ADMIN                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Sets the incentive tokens collector address.
     * @dev Only callable by the admin.
     * @param _incentiveTokensCollector The address of the new incentive tokens collector contract.
     */
    function setIncentiveTokensCollector(address _incentiveTokensCollector) external;

    /**
     * @notice Sets the reward vault helper address.
     * @dev Only callable by the admin.
     * @param _rewardVaultHelper The address of the new RewardVaultHelper contract.
     */
    function setRewardVaultHelper(address _rewardVaultHelper) external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         VAULT CREATION                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Creates a new reward vault vault for the given staking token.
     * @dev Reverts if the staking token is not a contract.
     * @param stakingToken The address of the staking token.
     * @return The address of the new vault.
     */
    function createRewardVault(address stakingToken) external returns (address);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          READS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Gets the VAULT_MANAGER_ROLE.
     * @return The VAULT_MANAGER_ROLE.
     */
    function VAULT_MANAGER_ROLE() external view returns (bytes32);

    /**
     * @notice Gets the VAULT_PAUSER_ROLE.
     * @return The VAULT_PAUSER_ROLE.
     */
    function VAULT_PAUSER_ROLE() external view returns (bytes32);

    /**
     * @notice Gets the vault for the given staking token.
     * @param stakingToken The address of the staking token.
     * @return The address of the vault.
     */
    function getVault(address stakingToken) external view returns (address);

    /**
     * @notice Gets the number of vaults that have been created.
     * @return The number of vaults.
     */
    function allVaultsLength() external view returns (uint256);

    /**
     * @notice Gets the address of the RewardVaultHelper contract.
     * @return The address of the RewardVaultHelper contract.
     */
    function rewardVaultHelper() external view returns (address);

    /**
     * @notice Predicts the address of the reward vault for the given staking token.
     * @param stakingToken The address of the staking token.
     * @return The address of the reward vault.
     */
    function predictRewardVaultAddress(address stakingToken) external view returns (address);

    /**
     * @notice Gets the address of the incentive tokens collector.
     * @return The address of the incentive tokens collector.
     */
    function incentiveTokensCollector() external view returns (address);
}
