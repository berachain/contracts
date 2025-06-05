// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

/// @notice This is the interface of HoneyFactory.
/// @author Berachain Team
interface IHoneyFactory {
    /// @notice Emitted when a mint rate is set for an asset.
    event MintRateSet(address indexed asset, uint256 rate);

    /// @notice Emitted when a redemption rate is set for an asset.
    event RedeemRateSet(address indexed asset, uint256 rate);

    /// @notice Emitted when the POLFeeCollector fee rate is set.
    event POLFeeCollectorFeeRateSet(uint256 rate);

    /// @notice Emitted when honey is minted
    /// @param from The account that supplied assets for the minted honey.
    /// @param to The account that received the honey.
    /// @param asset The asset used to mint the honey.
    /// @param assetAmount The amount of assets supplied for minting the honey.
    /// @param mintAmount The amount of honey that was minted.
    event HoneyMinted(
        address indexed from, address indexed to, address indexed asset, uint256 assetAmount, uint256 mintAmount
    );

    /// @notice Emitted when honey is redeemed
    /// @param from The account that redeemed the honey.
    /// @param to The account that received the assets.
    /// @param asset The asset for redeeming the honey.
    /// @param assetAmount The amount of assets received for redeeming the honey.
    /// @param redeemAmount The amount of honey that was redeemed.
    event HoneyRedeemed(
        address indexed from, address indexed to, address indexed asset, uint256 assetAmount, uint256 redeemAmount
    );

    /// @notice Emitted when the basked mode is forced.
    /// @param forced The flag that represent the forced basket mode.
    event BasketModeForced(bool forced);

    /// @notice Emitted when the depeg offsets are changed.
    /// @param asset The asset that the depeg offsets are changed.
    /// @param lower The lower depeg offset.
    /// @param upper The upper depeg offset.
    event DepegOffsetsSet(address asset, uint256 lower, uint256 upper);

    /// @notice Emitted when the liquidation is enabled or disabled.
    /// @param enabled The flag that represent the liquidation status.
    event LiquidationStatusSet(bool enabled);

    /// @notice Emitted when the reference collateral is set.
    /// @param old The old reference collateral.
    /// @param asset The new reference collateral.
    event ReferenceCollateralSet(address old, address asset);

    /// @notice Emitted when the recapitalize balance threshold is set.
    /// @param asset The asset that the recapitalize balance threshold is set.
    /// @param target The target balance threshold.
    event RecapitalizeBalanceThresholdSet(address asset, uint256 target);

    /// @notice Emitted when the min shares to recapitalize is set.
    /// @param minShareAmount The min shares to recapitalize.
    event MinSharesToRecapitalizeSet(uint256 minShareAmount);

    /// @notice Emitted when the max feed delay is set.
    /// @param maxFeedDelay The max feed delay.
    event MaxFeedDelaySet(uint256 maxFeedDelay);

    /// @notice Emitted when the liquidation rate is set.
    /// @param asset The asset that the liquidation rate is set.
    /// @param rate The liquidation rate.
    event LiquidationRateSet(address asset, uint256 rate);

    /// @notice Emitted when the global cap is set.
    /// @param globalCap The global cap.
    event GlobalCapSet(uint256 globalCap);

    /// @notice Emitted when the relative cap is set.
    /// @param asset The asset that the relative cap is set.
    /// @param relativeCap The relative cap.
    event RelativeCapSet(address asset, uint256 relativeCap);

    /// @notice Emitted when the price oracle is replaced.
    /// @param oracle The address of the new price oracle.
    event PriceOracleSet(address oracle);

    /// @notice Emitted when the liquidate is performed.
    /// @param badAsset The bad asset that is liquidated.
    /// @param goodAsset The good asset that is provided.
    /// @param amount The amount of good asset provided.
    /// @param sender The account that performed the liquidation.
    event Liquidated(address badAsset, address goodAsset, uint256 amount, address sender);

    /// @notice Emitted when the collateral vault is recapitalized.
    /// @param asset The asset that is recapitalized.
    /// @param amount The amount of asset provided.
    /// @param sender The account that performed the recapitalization.
    event Recapitalized(address asset, uint256 amount, address sender);

    /// @notice Mint Honey by sending ERC20 to this contract.
    /// @dev Assest must be registered and must be a good collateral.
    /// @param amount The amount of ERC20 to mint with.
    /// @param receiver The address that will receive Honey.
    /// @param expectBasketMode The flag with which the client communicates its expectation of the basket mode
    /// status.
    /// @return The amount of Honey minted.
    /// @dev The expectBasketMode flag avoid behavioral issues that may happen when the basket mode status changes
    /// after the client signed its transaction.
    function mint(address asset, uint256 amount, address receiver, bool expectBasketMode) external returns (uint256);

    /// @notice Redeem assets by sending Honey in to burn.
    /// @param honeyAmount The amount of Honey to redeem.
    /// @param receiver The address that will receive assets.
    /// @param expectBasketMode The flag with which the client communicates its expectation of the basket mode
    /// status.
    /// @return The amount of assets redeemed.
    /// @dev The expectBasketMode flag avoid behavioral issues that may happen when the basket mode status changes
    /// after the client signed its transaction.
    function redeem(
        address asset,
        uint256 honeyAmount,
        address receiver,
        bool expectBasketMode
    )
        external
        returns (uint256[] memory);

    /// @notice Liquidate a bad collateral asset.
    /// @param badCollateral The ERC20 asset to liquidate.
    /// @param goodCollateral The ERC20 asset to provide in place.
    /// @param goodAmount The amount provided.
    /// @return badAmount The amount obtained.
    function liquidate(
        address badCollateral,
        address goodCollateral,
        uint256 goodAmount
    )
        external
        returns (uint256 badAmount);

    /// @notice Recapitalize a collateral vault.
    /// @param asset The ERC20 asset to recapitalize.
    /// @param amount The amount provided.
    function recapitalize(address asset, uint256 amount) external;
}
