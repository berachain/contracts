// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { BUSD } from "./BUSD.sol";

/// @notice This is the interface of BUSDFactory.
/// @author Berachain Team
interface IBUSDFactory {
    /// @notice Emitted when a mint rate is set for an asset.
    event MintRateSet(address indexed asset, uint256 rate);

    /// @notice Emitted when a redemption rate is set for an asset.
    event RedeemRateSet(address indexed asset, uint256 rate);

    /// @notice Emitted when the POLFeeCollector fee rate is set.
    event POLFeeCollectorFeeRateSet(uint256 rate);

    /// @notice Emitted when BUSD is minted
    /// @param from The account that supplied assets for the minted BUSD.
    /// @param to The account that received the BUSD.
    /// @param asset The asset used to mint the BUSD.
    /// @param assetAmount The amount of assets supplied for minting the BUSD.
    /// @param mintAmount The amount of BUSD that was minted.
    event BUSDMinted(
        address indexed from, address indexed to, address indexed asset, uint256 assetAmount, uint256 mintAmount
    );

    /// @notice Emitted when BUSD is redeemed
    /// @param from The account that redeemed the BUSD.
    /// @param to The account that received the assets.
    /// @param asset The asset for redeeming the BUSD.
    /// @param assetAmount The amount of assets received for redeeming the BUSD.
    /// @param redeemAmount The amount of BUSD that was redeemed.
    event BUSDRedeemed(
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

    /// @notice Returns the address of the BUSD token contract.
    /// @return busd_ Address of BUSD.
    function busd() external view returns (BUSD busd_);

    /// @notice Returns the flag to tell if factory is forced to basket mode.
    /// @return forcedBasketMode_ True if forced to basket mode.
    function forcedBasketMode() external view returns (bool forcedBasketMode_);

    /// @notice Returns the lower offset of the peg range for a given asset.
    /// @param asset The address of the asset to check lower peg offset.
    /// @return lowerPegOffset The lower peg offset.
    function lowerPegOffsets(address asset) external view returns (uint256 lowerPegOffset);

    /// @notice Returns the upper offset of the peg range for a given asset.
    /// @param asset The address of the asset to check upper peg offset.
    /// @return upperPegOffset The upper peg offset.
    function upperPegOffsets(address asset) external view returns (uint256 upperPegOffset);

    /// @notice Mint BUSD by sending ERC20 to this contract.
    /// @dev Assest must be registered and must be a good collateral.
    /// @param amount The amount of ERC20 to mint with.
    /// @param receiver The address that will receive BUSD.
    /// @param expectBasketMode The flag with which the client communicates its expectation of the basket mode
    /// status.
    /// @return The amount of BUSD minted.
    /// @dev The expectBasketMode flag avoid behavioral issues that may happen when the basket mode status changes
    /// after the client signed its transaction.
    function mint(address asset, uint256 amount, address receiver, bool expectBasketMode) external returns (uint256);

    /// @notice Redeem assets by sending BUSD in to burn.
    /// @param busdAmount The amount of BUSD to redeem.
    /// @param receiver The address that will receive assets.
    /// @param expectBasketMode The flag with which the client communicates its expectation of the basket mode
    /// status.
    /// @return The amount of assets redeemed.
    /// @dev The expectBasketMode flag avoid behavioral issues that may happen when the basket mode status changes
    /// after the client signed its transaction.
    function redeem(
        address asset,
        uint256 busdAmount,
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
