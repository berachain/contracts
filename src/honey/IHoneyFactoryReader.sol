// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

/// @notice This is the interface of IHoneyFactoryReader.
/// @author Berachain Team
interface IHoneyFactoryReader {
    /// @notice Computes the amount of collateral(s) to provide in order to obtain a given amount of Honey.
    /// @param asset The collateral to consider if not in basket mode.
    /// @param honey The desired amount of honey to obtain.
    /// @return amounts The amounts of collateral to provide.
    function previewMintCollaterals(address asset, uint256 honey) external view returns (uint256[] memory amounts);

    /// @notice Computes the amount of collateral(s) to provide in order to obtain a given amount of Honey.
    /// @param asset The collateral to consider if not in basket mode.
    /// @param honey The desired amount of honey to obtain.
    /// @param prices The prices of the Honey collaterals.
    /// @return amounts The amounts of collateral to provide.
    /// @dev The prices are sorted like the HoneyFactory.registeredAssets
    /// @dev The prices have a WAD representation
    function previewMintCollateralsWithPrices(
        address asset,
        uint256 honey,
        uint256[] memory prices
    )
        external
        view
        returns (uint256[] memory amounts);

    /// @notice Given one collateral, computes the obtained Honey and the amount of collaterals expected if the basket
    /// mode is enabled.
    /// @param asset The collateral to provide.
    /// @param amount The desired amount of collateral to provide.
    /// @return collaterals The amounts of collateral to provide for every asset.
    /// @return honey The expected amount of Honey to be minted (considering also the other collaterals in basket
    /// mode).
    function previewMintHoney(
        address asset,
        uint256 amount
    )
        external
        view
        returns (uint256[] memory collaterals, uint256 honey);

    /// @notice Given one collateral, computes the obtained Honey and the amount of collaterals expected if the basket
    /// mode is enabled.
    /// @param asset The collateral to provide.
    /// @param amount The desired amount of collateral to provide.
    /// @param prices The prices of the Honey collaterals.
    /// @return collaterals The amounts of collateral to provide for every asset.
    /// @return honey The expected amount of Honey to be minted (considering also the other collaterals in basket
    /// mode).
    /// @dev The prices are sorted like the HoneyFactory.registeredAssets
    /// @dev The prices have a WAD representation
    function previewMintHoneyWithPrices(
        address asset,
        uint256 amount,
        uint256[] memory prices
    )
        external
        view
        returns (uint256[] memory collaterals, uint256 honey);

    /// @notice Computes the obtaineable amount of collateral(s) given an amount of Honey.
    /// @param asset The collateral to obtain if not in basket mode.
    /// @param honey The amount of honey provided.
    /// @return collaterals The amounts of collateral to obtain.
    function previewRedeemCollaterals(
        address asset,
        uint256 honey
    )
        external
        view
        returns (uint256[] memory collaterals);

    /// @notice Computes the obtaineable amount of collateral(s) given an amount of Honey.
    /// @param asset The collateral to obtain if not in basket mode.
    /// @param honey The amount of honey provided.
    /// @param prices The prices of the Honey collaterals.
    /// @return collaterals The amounts of collateral to obtain.
    /// @dev The prices are sorted like the HoneyFactory.registeredAssets
    /// @dev The prices have a WAD representation
    function previewRedeemCollateralsWithPrices(
        address asset,
        uint256 honey,
        uint256[] memory prices
    )
        external
        view
        returns (uint256[] memory collaterals);

    /// @notice Given one desired collateral, computes the Honey to provide.
    /// @param asset The collateral to obtain.
    /// @param amount The desired amount of collateral to obtain.
    /// @return collaterals The amounts of obtainable collaterals.
    /// @return honey The amount of Honey to be provided.
    function previewRedeemHoney(
        address asset,
        uint256 amount
    )
        external
        view
        returns (uint256[] memory collaterals, uint256 honey);

    /// @notice Given one desired collateral, computes the Honey to provide.
    /// @param asset The collateral to obtain.
    /// @param amount The desired amount of collateral to obtain.
    /// @param prices The prices of the Honey collaterals.
    /// @return collaterals The amounts of obtainable collaterals.
    /// @return honey The amount of Honey to be provided.
    /// @dev The prices are sorted like the HoneyFactory.registeredAssets
    /// @dev The prices have a WAD representation
    function previewRedeemHoneyWithPrices(
        address asset,
        uint256 amount,
        uint256[] memory prices
    )
        external
        view
        returns (uint256[] memory collaterals, uint256 honey);

    /// @notice HoneyFactory isBasketModeEnabled with externally provided price.
    /// @param isMint True if checking basket mode for minting.
    /// @param prices The prices assumed to be valid.
    function isBasketModeEnabledWithPrices(bool isMint, uint256[] memory prices) external returns (bool basketMode);

    /// @notice HoneyFactory isPegged with externally provided price.
    /// @param asset The asset to check.
    /// @param price The price assumed to be valid.
    /// @return true if the asset is pegged.
    function isPeggedWithPrice(address asset, uint256 price) external returns (bool);
}
