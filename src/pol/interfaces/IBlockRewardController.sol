// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IPOLErrors } from "./IPOLErrors.sol";

interface IBlockRewardController is IPOLErrors {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Emitted when the constant base rate has changed.
     * @param oldBaseRate The old base rate.
     * @param newBaseRate The new base rate.
     */
    event BaseRateChanged(uint256 oldBaseRate, uint256 newBaseRate);

    /**
     * @notice Emitted when the reward rate has changed.
     * @param oldRewardRate The old reward rate.
     * @param newRewardRate The new reward rate.
     */
    event RewardRateChanged(uint256 oldRewardRate, uint256 newRewardRate);

    /// @notice Emitted when the distributor is set.
    event SetDistributor(address indexed rewardDistribution);

    /// @notice Emitted when the rewards for the specified block have been processed.
    /// @param pubkey The validator's pubkey.
    /// @param nextTimestamp The timestamp of the next beacon block that was processed.
    /// @param baseRate The base amount of WBERA sent to the validator's operator.
    /// @param rewardRate The amount of WBERA sent to the distributor.
    event BlockRewardProcessed(bytes indexed pubkey, uint64 nextTimestamp, uint256 baseRate, uint256 rewardRate);

    /// @notice Emitted when the exceeding native balance is burnt.
    /// @param amount The amount of native tokens sent to address(0).
    event ExceedingBalanceBurnt(uint256 amount);

    /// @notice Returns the constant base rate for the emission token.
    /// @return The constant base amount of emission token to be emitted in the current block.
    function baseRate() external view returns (uint256);

    /// @notice Returns the reward rate for the emission token.
    /// @return The unscaled amount of emission token to be emitted in the current block.
    function rewardRate() external view returns (uint256);

    /**
     * @notice Returns the current max BGT production per block.
     * @dev Deprecated. Exposed for BGT contract to calculate the max burnable native token amount.
     * @return amount The maximum amount of BGT that can be minted in one block.
     */
    function getMaxBGTPerBlock() external view returns (uint256 amount);

    /**
     * @notice Returns the current max emission per block.
     * @return amount The maximum amount of rewards that can be emitted in one block.
     */
    function getMaxEmissionPerBlock() external view returns (uint256 amount);

    /**
     * @notice Processes the rewards for the specified block and distributes emission tokens to the validator's
     * operator and distributor.
     * @dev This function can only be called by the distributor.
     * @dev If in genesis only base rate for validators is sent.
     * @param pubkey The validator's pubkey.
     * @param nextTimestamp The timestamp of the next beacon block that was processed.
     * @param isReady The flag to enable reward sending to distributor (true when BeraChef is ready).
     * @return the amount of emission tokens sent to distributor.
     */
    function processRewards(bytes calldata pubkey, uint64 nextTimestamp, bool isReady) external returns (uint256);

    /**
     * @notice Sets the distributor contract that receives the minted WBERA.
     * @dev This function can only be called by the owner, which is the governance address.
     * @param _distributor The new distributor contract.
     */
    function setDistributor(address _distributor) external;

    /**
     * @notice Burns all exceeding native balance by sending it to address(0).
     * @dev Can only be called once per block by the distributor.
     */
    function burnExceedingBalance() external;
}
