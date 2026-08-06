// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { ERC20 } from "solady/src/tokens/ERC20.sol";
import { ERC4626 } from "solady/src/tokens/ERC4626.sol";

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { IHoneyFactoryReader } from "./IHoneyFactoryReader.sol";
import { IHoneyErrors } from "./IHoneyErrors.sol";
import { Utils } from "../libraries/Utils.sol";
import { HoneyFactory } from "./HoneyFactory.sol";

/// @title HoneyFactoryReader
/// @author Berachain Team
/// @notice The HoneyFactoryReader contract is responsible for providing previews of minting/redeeming HONEY.
/// @dev This contract provides view functions to calculate expected outputs for various HoneyFactory operations.
contract HoneyFactoryReader is AccessControlUpgradeable, UUPSUpgradeable, IHoneyFactoryReader, IHoneyErrors {
    using Utils for bytes4;

    /// @notice The HoneyFactory contract.
    HoneyFactory public honeyFactory;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address honeyFactory_) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        if (honeyFactory_ == address(0)) ZeroAddress.selector.revertWith();
        honeyFactory = HoneyFactory(honeyFactory_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          GETTERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IHoneyFactoryReader
    /// @dev `asset` param is ignored if running in basket mode.
    function previewMintCollaterals(address asset, uint256 honey) external view returns (uint256[] memory amounts) {
        bool basketMode = honeyFactory.isBasketModeEnabled(true);

        amounts = _previewMintCollaterals(asset, honey, basketMode);
    }

    /// @inheritdoc IHoneyFactoryReader
    /// @dev `asset` param is ignored if running in basket mode.
    function previewMintCollateralsWithPrices(
        address asset,
        uint256 honey,
        uint256[] memory prices
    )
        external
        view
        returns (uint256[] memory amounts)
    {
        bool basketMode = isBasketModeEnabledWithPrices(true, prices);

        amounts = _previewMintCollaterals(asset, honey, basketMode);
    }

    /// @inheritdoc IHoneyFactoryReader
    function previewMintHoney(
        address asset,
        uint256 amount
    )
        external
        view
        returns (uint256[] memory collaterals, uint256 honey)
    {
        bool basketMode = honeyFactory.isBasketModeEnabled(true);

        (collaterals, honey) = _previewMintHoney(asset, amount, basketMode);
    }

    /// @inheritdoc IHoneyFactoryReader
    function previewMintHoneyWithPrices(
        address asset,
        uint256 amount,
        uint256[] memory prices
    )
        external
        view
        returns (uint256[] memory collaterals, uint256 honey)
    {
        bool basketMode = isBasketModeEnabledWithPrices(true, prices);

        (collaterals, honey) = _previewMintHoney(asset, amount, basketMode);
    }

    /// @inheritdoc IHoneyFactoryReader
    /// @dev `asset` param is ignored if running in basket mode.
    function previewRedeemCollaterals(
        address asset,
        uint256 honey
    )
        external
        view
        returns (uint256[] memory collaterals)
    {
        bool basketMode = honeyFactory.isBasketModeEnabled(false);

        collaterals = _previewRedeemCollaterals(asset, honey, basketMode);
    }

    /// @inheritdoc IHoneyFactoryReader
    /// @dev `asset` param is ignored if running in basket mode.
    function previewRedeemCollateralsWithPrices(
        address asset,
        uint256 honey,
        uint256[] memory prices
    )
        external
        view
        returns (uint256[] memory collaterals)
    {
        bool basketMode = isBasketModeEnabledWithPrices(false, prices);

        collaterals = _previewRedeemCollaterals(asset, honey, basketMode);
    }

    /// @inheritdoc IHoneyFactoryReader
    /// @dev If the basket mode is enabled, the required Honey amount will provide also other collaterals beside
    /// required `amount` of `asset`.
    function previewRedeemHoney(
        address asset,
        uint256 amount
    )
        external
        view
        returns (uint256[] memory collaterals, uint256 honey)
    {
        bool basketMode = honeyFactory.isBasketModeEnabled(false);

        (collaterals, honey) = _previewRedeemHoney(asset, amount, basketMode);
    }

    /// @inheritdoc IHoneyFactoryReader
    /// @dev If the basket mode is enabled, the required Honey amount will provide also other collaterals beside
    /// required `amount` of `asset`.
    function previewRedeemHoneyWithPrices(
        address asset,
        uint256 amount,
        uint256[] memory prices
    )
        external
        view
        returns (uint256[] memory collaterals, uint256 honey)
    {
        bool basketMode = isBasketModeEnabledWithPrices(false, prices);

        (collaterals, honey) = _previewRedeemHoney(asset, amount, basketMode);
    }

    /// @inheritdoc IHoneyFactoryReader
    /// @dev Implementation is copied 1:1 from HoneyFactory to not edit the original contract.
    function isBasketModeEnabledWithPrices(bool isMint, uint256[] memory prices)
        public
        view
        returns (bool basketMode)
    {
        uint256 registeredAssetsLen = honeyFactory.numRegisteredAssets();

        if (honeyFactory.forcedBasketMode()) return true;

        for (uint256 i = 0; i < registeredAssetsLen; i++) {
            address asset = honeyFactory.registeredAssets(i);
            bool isPegged_ = isPeggedWithPrice(asset, prices[i]);

            if (isMint) {
                if (isPegged_ && !honeyFactory.isBadCollateralAsset(asset)) {
                    // Basket mode should be disabled. It means there is a good collateral.
                    return false;
                }
            } else if (!isPegged_) {
                // If the not pegged asset is a bad collateral and its vault doesn't have shares
                // we can ignore it because it means it has been fully liquidated.
                uint256 sharesWithoutFees = honeyFactory.vaults(asset).balanceOf(address(honeyFactory))
                    - honeyFactory.collectedAssetFees(asset);
                bool usedAsCollateral = sharesWithoutFees > 0;

                if (!usedAsCollateral) {
                    continue;
                }
                return true;
            }
        }

        // When is mint and there is no asset that disable basket mode, return true.
        // When is redeem and there is no asset that enable basket mode, return false.
        return isMint ? true : false;
    }

    /// @inheritdoc IHoneyFactoryReader
    function isPeggedWithPrice(address asset, uint256 price) public view returns (bool) {
        return
            (1e18 - honeyFactory.lowerPegOffsets(asset) <= price)
                && (price <= 1e18 + honeyFactory.upperPegOffsets(asset));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _previewMintCollaterals(
        address asset,
        uint256 honey,
        bool basketMode
    )
        internal
        view
        returns (uint256[] memory amounts)
    {
        (address[] memory collaterals, uint256 num) = _getCollaterals();
        amounts = new uint256[](num);
        uint256[] memory weights = honeyFactory.getWeights();
        for (uint256 i = 0; i < num; i++) {
            if (!basketMode && collaterals[i] != asset) {
                continue;
            }
            if (!basketMode && collaterals[i] == asset) {
                weights[i] = 1e18;
            }
            ERC4626 vault = honeyFactory.vaults(collaterals[i]);
            uint256 mintRate = honeyFactory.mintRates(collaterals[i]);
            uint256 shares = honey * weights[i] / mintRate;

            // If the shares re-converted do not match the exact honey amount, we round up.
            if (weights[i] > 0 && shares * mintRate / weights[i] < honey) {
                shares++;
            }

            amounts[i] = vault.convertToAssets(shares);
        }
    }

    function _previewMintHoney(
        address asset,
        uint256 amount,
        bool basketMode
    )
        internal
        view
        returns (uint256[] memory collaterals, uint256 honey)
    {
        collaterals = _getWeightedCollaterals(asset, amount, basketMode);
        (address[] memory assets, uint256 num) = _getCollaterals();
        for (uint256 i = 0; i < num; i++) {
            honey += _previewMint(assets[i], collaterals[i]);
        }
    }

    function _previewRedeemCollaterals(
        address asset,
        uint256 honey,
        bool basketMode
    )
        internal
        view
        returns (uint256[] memory collaterals)
    {
        (address[] memory assets, uint256 num) = _getCollaterals();
        collaterals = new uint256[](num);

        if (!basketMode) {
            (uint256 refAssetIndex,) = _getIndexOfAsset(assets, num, asset);
            collaterals[refAssetIndex] = _previewRedeem(asset, honey);

            return collaterals;
        }

        uint256[] memory weights = honeyFactory.getWeights();
        for (uint256 i = 0; i < num; i++) {
            collaterals[i] = _previewRedeem(assets[i], honey * weights[i] / 1e18);
        }
    }

    function _previewRedeemHoney(
        address asset,
        uint256 amount,
        bool basketMode
    )
        internal
        view
        returns (uint256[] memory collaterals, uint256 honey)
    {
        collaterals = _getWeightedCollaterals(asset, amount, basketMode);
        (address[] memory assets, uint256 num) = _getCollaterals();
        for (uint256 i = 0; i < num; i++) {
            honey += _previewHoneyToRedeem(assets[i], collaterals[i]);
        }
    }

    /// @notice Get the amount of Honey that can be minted with the given ERC20.
    /// @param asset The ERC20 to mint with.
    /// @param amount The amount of ERC20 to mint with.
    /// @return honeyAmount The amount of Honey that can be minted.
    function _previewMint(address asset, uint256 amount) internal view returns (uint256 honeyAmount) {
        ERC4626 vault = honeyFactory.vaults(asset);
        // Get shares for a given assets.
        uint256 shares = vault.previewDeposit(amount);
        honeyAmount = _getHoneyMintedFromShares(asset, shares);
    }

    /// @notice Get the amount of ERC20 that can be redeemed with the given Honey.
    /// @param asset The ERC20 to redeem.
    /// @param honeyAmount The amount of Honey to redeem.
    /// @return The amount of ERC20 that can be redeemed.
    function _previewRedeem(address asset, uint256 honeyAmount) internal view returns (uint256) {
        ERC4626 vault = honeyFactory.vaults(asset);
        uint256 shares = _getSharesRedeemedFromHoney(asset, honeyAmount);
        // Get assets for a given shares.
        return vault.previewRedeem(shares);
    }

    function _getCollaterals() internal view returns (address[] memory collaterals, uint256 num) {
        num = honeyFactory.numRegisteredAssets();
        collaterals = new address[](num);
        for (uint256 i = 0; i < num; i++) {
            collaterals[i] = honeyFactory.registeredAssets(i);
        }
    }

    function _getHoneyMintedFromShares(address asset, uint256 shares) internal view returns (uint256 honeyAmount) {
        uint256 mintRate = honeyFactory.mintRates(asset);
        honeyAmount = shares * mintRate / 1e18;
    }

    function _getSharesRedeemedFromHoney(address asset, uint256 honeyAmount) internal view returns (uint256 shares) {
        uint256 redeemRate = honeyFactory.redeemRates(asset);
        shares = honeyAmount * redeemRate / 1e18;
    }

    function _getIndexOfAsset(
        address[] memory collaterals,
        uint256 num,
        address asset
    )
        internal
        pure
        returns (uint256 index, bool found)
    {
        found = false;
        for (uint256 i = 0; i < num; i++) {
            if (collaterals[i] == asset) {
                found = true;
                index = i;
                break;
            }
        }
    }

    /// @notice Given one collateral amount, returns the expected amounts of all the collaterals.
    function _getWeightedCollaterals(
        address asset,
        uint256 amount,
        bool basketMode
    )
        internal
        view
        returns (uint256[] memory res)
    {
        (address[] memory collaterals, uint256 num) = _getCollaterals();
        res = new uint256[](num);
        // Lookup index of input collateral:
        (uint256 refAssetIndex, bool found) = _getIndexOfAsset(collaterals, num, asset);

        // If not running in basket mode, simply returns `amount` for `asset` and 0 for the others.
        if (!basketMode) {
            if (found) {
                res[refAssetIndex] = amount;
            }
            return res;
        }

        // Otherwise, compute the scaled amounts of all the collaterals in order to match wanted `amount` for `asset`.
        uint256[] memory weights = honeyFactory.getWeights();
        if (weights[refAssetIndex] == 0) {
            return res;
        }
        uint8 decimals = ERC20(asset).decimals();
        uint256 refAmount = Utils.changeDecimals(amount, decimals, 18);
        refAmount = refAmount * 1e18 / weights[refAssetIndex];
        for (uint256 i = 0; i < num; i++) {
            ERC4626 vault = honeyFactory.vaults(collaterals[i]);
            // Amounts are converted to asset decimals in convertToAssets
            res[i] = vault.convertToAssets(refAmount * weights[i] / 1e18);
        }
    }

    /// @notice Previews the amount of honey required to redeem an exact amount of target ERC20 asset.
    /// @param asset The ERC20 asset to receive.
    /// @param exactAmount The exact amount of assets to receive.
    /// @return The amount of honey required.
    function _previewHoneyToRedeem(address asset, uint256 exactAmount) internal view returns (uint256) {
        ERC4626 vault = honeyFactory.vaults(asset);
        // Get shares for an exact assets.
        uint256 shares = vault.previewWithdraw(exactAmount);
        uint256 redeemRate = honeyFactory.redeemRates(asset);
        return shares * 1e18 / redeemRate;
    }
}
