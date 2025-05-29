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

    /**
     * @notice Emitted when the min boosted reward rate has changed.
     * @param oldMinBoostedRewardRate The old min boosted reward rate.
     * @param newMinBoostedRewardRate The new min boosted reward rate.
     */
    event MinBoostedRewardRateChanged(uint256 oldMinBoostedRewardRate, uint256 newMinBoostedRewardRate);

    /**
     * @notice Emitted when the boostMultiplier parameter has changed.
     * @param oldBoostMultiplier The old boost multiplier parameter.
     * @param newBoostMultiplier The new boost multiplier parameter.
     */
    event BoostMultiplierChanged(uint256 oldBoostMultiplier, uint256 newBoostMultiplier);

    /**
     * @notice Emitted when the reward formula convexity parameter has changed.
     * @param oldRewardConvexity The old reward formula convexity parameter.
     * @param newRewardConvexity The new reward formula convexity parameter.
     */
    event RewardConvexityChanged(uint256 oldRewardConvexity, uint256 newRewardConvexity);

    /// @notice Emitted when the distributor is set.
    event SetDistributor(address indexed rewardDistribution);

    /// @notice Emitted when the rewards for the specified block have been processed.
    /// @param pubkey The validator's pubkey.
    /// @param nextTimestamp The timestamp of the next beacon block that was processed.
    /// @param baseRate The base amount of BGT minted to the validator's operator.
    /// @param rewardRate The amount of BGT minted to the distributor.
    event BlockRewardProcessed(bytes indexed pubkey, uint64 nextTimestamp, uint256 baseRate, uint256 rewardRate);

    /// @notice Emitted when base BGT is minted to either the operator or their receiver
    /// @param operator The operator address that earned the base rewards
    /// @param receiver The address that received the base rewards (operator or their set receiver)
    /// @param amount The amount of base BGT minted
    event BaseMinted(address indexed operator, address indexed receiver, uint256 indexed amount);

    /// @notice Emitted when an operator sets or changes their receiver address
    /// @param operator The operator address that changed their receiver
    /// @param oldReceiver The previous receiver address (zero if first time setting)
    /// @param newReceiver The new receiver address (zero if clearing receiver)
    event OperatorReceiverUpdated(address indexed operator, address indexed oldReceiver, address indexed newReceiver);

    /// @notice Returns the constant base rate for BGT.
    /// @return The constant base amount of BGT to be minted in the current block.
    function baseRate() external view returns (uint256);

    /// @notice Returns the reward rate for BGT.
    /// @return The unscaled amount of BGT to be minted in the current block.
    function rewardRate() external view returns (uint256);

    /// @notice Returns the minimum boosted reward rate for BGT.
    /// @return The minimum amount of BGT to be minted in the current block.
    function minBoostedRewardRate() external view returns (uint256);

    /// @notice Returns the boost mutliplier param in the reward function.
    /// @return The parameter that determines the inflation cap.
    function boostMultiplier() external view returns (uint256);

    /// @notice Returns the reward convexity param in the reward function.
    /// @return The parameter that determines how fast the function converges to its max.
    function rewardConvexity() external view returns (int256);

    /**
     * @notice Computes the reward given specified parameters, according to the formula.
     * r := (1 + mul) * (1 - 1 / (1 + mul * boost^conv)) * rewardRate ∈ [0, mul * rewardRate]
     * @dev Returns 0 for boost == 0 even if conv == 0, since contract enforces conv > 0.
     * @param boostPower the normalized boost.
     * @param _rewardRate the reward rate parameter.
     * @param _boostMultiplier the boost multiplier parameter.
     * @param _rewardConvexity  the reward convexity parameter.
     * @return the reward amount.
     */
    function computeReward(
        uint256 boostPower,
        uint256 _rewardRate,
        uint256 _boostMultiplier,
        int256 _rewardConvexity
    )
        external
        pure
        returns (uint256);

    /**
     * @notice Returns the current max BGT production per block.
     * @dev Exposed for BGT contract to calculate the max burnable native token amount.
     * @return amount The maximum amount of BGT that can be minted in one block.
     */
    function getMaxBGTPerBlock() external view returns (uint256 amount);

    /**
     * @notice Processes the rewards for the specified block and mints BGT to validator's operator and distributor.
     * @dev This function can only be called by the distributor.
     * @dev If in genesis only base rate for validators is minted.
     * @param pubkey The validator's pubkey.
     * @param nextTimestamp The timestamp of the next beacon block that was processed.
     * @param isReady The flag to enable reward minting to distributor (true when BeraChef is ready).
     * @return the amount of BGT minted to distributor.
     */
    function processRewards(bytes calldata pubkey, uint64 nextTimestamp, bool isReady) external returns (uint256);

    /**
     * @notice Sets the constant base reward rate for BGT.
     * @dev This function can only be called by the owner, which is the governance address.
     * @param _baseRate The new base rate.
     */
    function setBaseRate(uint256 _baseRate) external;

    /**
     * @notice Sets the reward rate for BGT.
     * @dev This function can only be called by the owner, which is the governance address.
     * @param _rewardRate The new reward rate.
     */
    function setRewardRate(uint256 _rewardRate) external;

    /**
     * @notice Sets the min boosted reward rate for BGT.
     * @dev This function can only be called by the owner, which is the governance address.
     * @param _minBoostedRewardRate The new min boosted reward rate.
     */
    function setMinBoostedRewardRate(uint256 _minBoostedRewardRate) external;

    /**
     * @notice Sets the boost multiplier parameter for the reward formula.
     * @dev This function can only be called by the owner, which is the governance address.
     * @param _boostMultiplier The new boost multiplier.
     */
    function setBoostMultiplier(uint256 _boostMultiplier) external;

    /**
     * @notice Sets the reward convexity parameter for the reward formula.
     * @dev This function can only be called by the owner, which is the governance address.
     * @param _rewardConvexity The new reward convexity.
     */
    function setRewardConvexity(uint256 _rewardConvexity) external;

    /**
     * @notice Sets the distributor contract that receives the minted BGT.
     * @dev This function can only be called by the owner, which is the governance address.
     * @param _distributor The new distributor contract.
     */
    function setDistributor(address _distributor) external;

    /**
     * @notice Sets or updates the receiver address for an operator's base BGT rewards
     * @dev Only the operator associated with the provided pubkey can set their receiver
     * @param pubkey The validator's public key used to retrieve the operator from the deposit contract
     * @param receiver The address that will receive base BGT rewards. Set to address(0) to receive rewards directly
     */
    function setOperatorReceiver(bytes calldata pubkey, address receiver) external;
}
