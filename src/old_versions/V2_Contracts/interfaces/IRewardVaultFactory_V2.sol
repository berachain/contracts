// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IPOLErrors } from "src/pol/interfaces/IPOLErrors.sol";

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
     * @notice Emitted when the BGTIncentiveDistributor contract is set.
     * @param newBGTIncentiveDistributor The address of the new BGTIncentiveDistributor contract.
     * @param oldBGTIncentiveDistributor The address of the old BGTIncentiveDistributor contract.
     */
    event BGTIncentiveDistributorSet(
        address indexed newBGTIncentiveDistributor, address indexed oldBGTIncentiveDistributor
    );

    /**
     * @notice Emitted when the incentive fee percentage is updated.
     * @param newValue The new rate (in basis points).
     * @param oldValue The old rate (in basis points).
     */
    event IncentiveFeeRateUpdated(uint256 newValue, uint256 oldValue);

    /**
     * @notice Emitted when the incentive fee collector address is updated.
     * @param newAddress The new address for incentive fees.
     * @param oldAddress The old address for incentive fees.
     */
    event IncentiveFeeCollectorUpdated(address newAddress, address oldAddress);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          ADMIN                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Sets the BGTIncentiveDistributor contract.
     * @dev Only callable by the admin.
     * @param _bgtIncentiveDistributor The address of the new BGTIncentiveDistributor contract.
     */
    function setBGTIncentiveDistributor(address _bgtIncentiveDistributor) external;

    /**
     * @notice Sets the incentives fee rate.
     * @dev Only callable by the admin.
     * @param _bgtIncentiveFeeRate The new value for the rate (in basis points).
     */
    function setBGTIncentiveFeeRate(uint256 _bgtIncentiveFeeRate) external;

    /**
     * @notice Sets the BGTIncentiveDistributor contract.
     * @dev Only callable by the admin.
     * @param _bgtIncentiveFeeCollector The address of the new BGTIncentiveFeeCollector contract.
     */
    function setBGTIncentiveFeeCollector(address _bgtIncentiveFeeCollector) external;

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
     * @notice Gets the address of the BGTIncentiveDistributor contract.
     * @return The address of the BGTIncentiveDistributor contract.
     */
    function bgtIncentiveDistributor() external view returns (address);

    /**
     * @notice Predicts the address of the reward vault for the given staking token.
     * @param stakingToken The address of the staking token.
     * @return The address of the reward vault.
     */
    function predictRewardVaultAddress(address stakingToken) external view returns (address);

    /**
     * @notice Gets the value of the incentive fee rate.
     * @return The rate (in basis points).
     */
    function bgtIncentiveFeeRate() external view returns (uint256);

    /**
     * @notice Gets the address of the incentive fee collector.
     * @return The address of the BGTIncentiveFeeCollector contract.
     */
    function bgtIncentiveFeeCollector() external view returns (address);

    /**
     * @notice Applies the fee percentage on the incentive amount.
     * @param incentiveAmount The amount of incentive tokens.
     * @return The fee amount.
     */
    function getIncentiveFeeAmount(uint256 incentiveAmount) external view returns (uint256);
}
