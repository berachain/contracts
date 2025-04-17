// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { ERC20 } from "solady/src/tokens/ERC20.sol";
import { ERC4626 } from "solady/src/tokens/ERC4626.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { IPriceOracle } from "../extras/IPriceOracle.sol";
import { IHoneyFactory } from "src/honey/IHoneyFactory.sol";
import { Utils } from "../libraries/Utils.sol";
import { Honey } from "src/honey/Honey.sol";
import { VaultAdmin_V0 } from "./VaultAdmin_V0.sol";

/// @notice This is the factory contract for minting and redeeming Honey.
/// @author Berachain Team
contract HoneyFactory_V0 is IHoneyFactory, VaultAdmin_V0 {
    using Utils for bytes4;

    /// @dev The constant representing 100% of mint/redeem rate.
    uint256 private constant ONE_HUNDRED_PERCENT_RATE = 1e18;

    /// @dev The constant representing 98% of mint/redeem rate.
    uint256 private constant NINETY_EIGHT_PERCENT_RATE = 98e16;

    /// @dev The constant representing the default symmetrical offset for USD peg.
    uint256 private constant DEFAULT_PEG_OFFSET = 0.002e18;

    /// @dev The constant representing the default mint/redeem rate.
    uint256 private constant DEFAULT_MINT_REDEEM_RATE = 0.9995e18;

    /// @notice The constant representing the default minimum amount of shares to recapitalize.
    /// @dev It's set to 1 share.
    uint256 private constant DEFAULT_MIN_SHARES_TO_RECAPITALIZE = 1e18;

    /// @notice The constant representing the max peg offset allowed.
    /// @dev It's set to 2 cents.
    uint256 private constant MAX_PEG_OFFSET = 0.02e18;

    /// @notice The constant representing the max price feed delay tolerance in seconds allowed.
    uint256 private constant MAX_PRICE_FEED_DELAY_TOLERANCE = 120 seconds;

    /// @notice The Honey token contract.
    Honey public honey;

    /// @notice The rate of POLFeeCollector fees, 60.18-decimal fixed-point number representation
    /// @dev 1e18 will imply all the fees are collected by the POLFeeCollector
    /// @dev 0 will imply all fees goes to the feeReceiver
    uint256 public polFeeCollectorFeeRate;

    /// @notice Mint rate of Honey for each asset, 60.18-decimal fixed-point number representation
    mapping(address asset => uint256 rate) public mintRates;
    /// @notice Redemption rate of Honey for each asset, 60.18-decimal fixed-point number representation
    mapping(address asset => uint256 rate) public redeemRates;

    /// @notice WAD offset from 1e18 for USD peg
    mapping(address asset => uint256 lowerPegOffset) internal lowerPegOffsets;
    mapping(address asset => uint256 upperPegOffset) internal upperPegOffsets;

    /// @notice Premium rate applied upon liquidation
    mapping(address asset => uint256 rate) internal liquidationRates;

    /// @notice Whether the basket mode is forced regardless of the price oracle
    bool public forcedBasketMode;
    /// @notice Whether the liquidation is enabled
    bool public liquidationEnabled;

    /// @notice The price oracle
    IPriceOracle public priceOracle;

    /// @notice The max number of seconds of tolerated staleness
    /// @dev It's involved into deeming a collateral asset pegged or not
    uint256 public priceFeedMaxDelay;

    address public referenceCollateral;
    mapping(address asset => uint256 limit) public relativeCap;
    uint256 public globalCap;

    /// @notice The target balance for recapitalization of each asset
    mapping(address asset => uint256 targetBalance) public recapitalizeBalanceThreshold;

    /// @notice The minimum amount of shares that the user have to mint to recapitalize
    uint256 public minSharesToRecapitalize;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _governance,
        address _honey,
        address _polFeeCollector,
        address _feeReceiver,
        address _priceOracle
    )
        external
        initializer
    {
        __VaultAdmin_init(_governance, _polFeeCollector, _feeReceiver);

        if (_honey == address(0)) ZeroAddress.selector.revertWith();
        if (_priceOracle == address(0)) ZeroAddress.selector.revertWith();

        honey = Honey(_honey);

        // initialize with 100% of the mint/redeem fee to the polFeeCollector
        polFeeCollectorFeeRate = ONE_HUNDRED_PERCENT_RATE;

        // NOTE: based on the average block time of ~2 seconds.
        priceFeedMaxDelay = 10 seconds;
        minSharesToRecapitalize = DEFAULT_MIN_SHARES_TO_RECAPITALIZE;
        priceOracle = IPriceOracle(_priceOracle);
        globalCap = ONE_HUNDRED_PERCENT_RATE;
        liquidationEnabled = false;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       MANAGER FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Set the mint rate of Honey for an asset.
    function setMintRate(address asset, uint256 mintRate) external {
        _checkRole(MANAGER_ROLE);
        // Revert if the mint rate is over 100%
        if (mintRate > ONE_HUNDRED_PERCENT_RATE) {
            OverOneHundredPercentRate.selector.revertWith(mintRate);
        }
        // Ensure manager cannot set the mint rate below 98%
        if (mintRate < NINETY_EIGHT_PERCENT_RATE) {
            UnderNinetyEightPercentRate.selector.revertWith(mintRate);
        }
        mintRates[asset] = mintRate;
        emit MintRateSet(asset, mintRate);
    }

    /// @notice Set the redemption rate of Honey for an asset.
    function setRedeemRate(address asset, uint256 redeemRate) external {
        _checkRole(MANAGER_ROLE);
        // Revert if the redeem rate is over 100%
        if (redeemRate > ONE_HUNDRED_PERCENT_RATE) {
            OverOneHundredPercentRate.selector.revertWith(redeemRate);
        }
        // Ensure manager cannot set the redeem rate below 98%
        if (redeemRate < NINETY_EIGHT_PERCENT_RATE) {
            UnderNinetyEightPercentRate.selector.revertWith(redeemRate);
        }
        redeemRates[asset] = redeemRate;
        emit RedeemRateSet(asset, redeemRate);
    }

    /// @notice Set the forced basket mode status.
    /// @dev Only Manager role can call this function.
    function setForcedBasketMode(bool forced) external {
        _checkRole(MANAGER_ROLE);
        forcedBasketMode = forced;
        emit BasketModeForced(forced);
    }

    /// @notice Set the max tolerated number of seconds for oracle staleness.
    /// @dev It's involved into deeming a collateral asset pegged or not.
    /// @dev Only Manager role can call this function.
    function setMaxFeedDelay(uint256 maxTolerance) external {
        _checkRole(MANAGER_ROLE);
        if (maxTolerance > MAX_PRICE_FEED_DELAY_TOLERANCE) {
            AmountOutOfRange.selector.revertWith();
        }
        priceFeedMaxDelay = maxTolerance;
        emit MaxFeedDelaySet(maxTolerance);
    }

    /// @notice Set lower and upper depeg offset for an asset.
    /// @dev Only Manager role can call this function.
    function setDepegOffsets(address asset, uint256 lowerOffset, uint256 upperOffset) external {
        _checkRole(MANAGER_ROLE);
        _checkRegisteredAsset(asset);

        if (lowerOffset > MAX_PEG_OFFSET || upperOffset > MAX_PEG_OFFSET) {
            AmountOutOfRange.selector.revertWith();
        }
        lowerPegOffsets[asset] = lowerOffset;
        upperPegOffsets[asset] = upperOffset;
        emit DepegOffsetsSet(asset, lowerOffset, upperOffset);
    }

    /// @notice Set the reference collateral for cap limits.
    function setReferenceCollateral(address asset) external {
        _checkRole(MANAGER_ROLE);
        _checkRegisteredAsset(asset);

        address old = referenceCollateral;
        referenceCollateral = asset;
        emit ReferenceCollateralSet(old, asset);
    }

    /// @notice Set the global cap limit.
    function setGlobalCap(uint256 limit) external {
        _checkRole(MANAGER_ROLE);

        // A change in the weights distribution that frontruns this transaction
        // may cause a DoS in the redeem of Honey
        uint256[] memory weights = _getWeights(true, false);
        uint256 max = 0;
        for (uint256 i = 0; i < registeredAssets.length; i++) {
            if (weights[i] > max) {
                max = weights[i];
            }
        }
        if (limit < max) {
            CapCanCauseDenialOfService.selector.revertWith();
        }

        globalCap = limit;
        emit GlobalCapSet(limit);
    }

    /// @notice Set the relative cap limit.
    function setRelativeCap(address asset, uint256 limit) external {
        _checkRole(MANAGER_ROLE);
        relativeCap[asset] = limit;
        emit RelativeCapSet(asset, limit);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        ADMIN FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Set the POLFeeCollector fee rate.
    function setPOLFeeCollectorFeeRate(uint256 _polFeeCollectorFeeRate) external {
        _checkRole(DEFAULT_ADMIN_ROLE);
        // Revert if the POLFeeCollector fee rate is over 100%
        if (_polFeeCollectorFeeRate > ONE_HUNDRED_PERCENT_RATE) {
            OverOneHundredPercentRate.selector.revertWith(_polFeeCollectorFeeRate);
        }
        polFeeCollectorFeeRate = _polFeeCollectorFeeRate;
        emit POLFeeCollectorFeeRateSet(_polFeeCollectorFeeRate);
    }

    /// @notice Set whether the liquidation is enabled or not.
    function setLiquidationEnabled(bool enabled) external {
        _checkRole(DEFAULT_ADMIN_ROLE);
        liquidationEnabled = enabled;
        emit LiquidationStatusSet(enabled);
    }

    /// @notice Set the liquidation rate for an asset
    /// @dev The `extraRate` is a premium, hence a 0.25 rate means a 1.25 premium factor.
    function setLiquidationRate(address asset, uint256 extraRate) external {
        _checkRole(DEFAULT_ADMIN_ROLE);
        _checkRegisteredAsset(asset);

        liquidationRates[asset] = extraRate;
        emit LiquidationRateSet(asset, extraRate);
    }

    /// @notice Set the minimum amount of shares that the user have to mint to recapitalize
    function setMinSharesToRecapitalize(uint256 minSharesAmount) external {
        _checkRole(DEFAULT_ADMIN_ROLE);
        if (minSharesAmount < DEFAULT_MIN_SHARES_TO_RECAPITALIZE) {
            AmountOutOfRange.selector.revertWith(minSharesAmount);
        }
        minSharesToRecapitalize = minSharesAmount;
        emit MinSharesToRecapitalizeSet(minSharesAmount);
    }

    /// @notice Set the target balance for recapitalization.
    /// @param asset The collateral asset to which the target applies.
    /// @param target The target amount with the token's decimals.
    function setRecapitalizeBalanceThreshold(address asset, uint256 target) external {
        _checkRole(DEFAULT_ADMIN_ROLE);
        recapitalizeBalanceThreshold[asset] = target;
        emit RecapitalizeBalanceThresholdSet(asset, target);
    }

    /// @notice Replace the price oracle.
    /// @param priceOracle_ The new price oracle to use.
    function setPriceOracle(address priceOracle_) external {
        _checkRole(DEFAULT_ADMIN_ROLE);
        if (priceOracle_ == address(0)) ZeroAddress.selector.revertWith();
        priceOracle = IPriceOracle(priceOracle_);
        emit PriceOracleSet(priceOracle_);
    }

    /// @dev Create a new ERC4626 vault for a pair of asset - Honey and register it with VaultAdmin.
    /// @dev Reverts if the vault for the given asset is already registered.
    /// @dev Reverts if the asset is zero address during `vault.initialize`.
    /// @param asset The asset to create a vault for.
    /// @return vault The newly created vault.
    function createVault(address asset) external returns (ERC4626 vault) {
        if (numRegisteredAssets() == 0) {
            referenceCollateral = asset;
        }

        vault = _createVault(asset);

        relativeCap[asset] = ONE_HUNDRED_PERCENT_RATE;
        mintRates[asset] = DEFAULT_MINT_REDEEM_RATE;
        redeemRates[asset] = DEFAULT_MINT_REDEEM_RATE;

        // Check if oracle has the needed data and the asset is a stable one:
        lowerPegOffsets[asset] = MAX_PEG_OFFSET;
        upperPegOffsets[asset] = MAX_PEG_OFFSET;
        if (!isPegged(asset)) {
            NotPegged.selector.revertWith(asset);
        }
        // Restore the default value:
        lowerPegOffsets[asset] = DEFAULT_PEG_OFFSET;
        upperPegOffsets[asset] = DEFAULT_PEG_OFFSET;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       USER FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IHoneyFactory
    function mint(
        address asset,
        uint256 amount,
        address receiver,
        bool expectBasketMode
    )
        external
        whenNotPaused
        returns (uint256 honeyToMint)
    {
        _checkRegisteredAsset(asset);

        bool basketMode = isBasketModeEnabled(true);
        if (basketMode != expectBasketMode) {
            UnexpectedBasketModeStatus.selector.revertWith();
        }

        if (!basketMode) {
            // Check if the asset is not market as bad collateral and if it is pegged.
            _checkGoodCollateralAsset(asset);
            if (!isPegged(asset)) {
                NotPegged.selector.revertWith(asset);
            }

            honeyToMint = _mint(asset, amount, receiver, false);
            if (!_isCappedGlobal(true, asset)) {
                ExceedGlobalCap.selector.revertWith();
            }
        } else {
            uint256[] memory weights = _getWeights(false, true);
            // Here the assumption is that the callers knows about the basket mode and
            // has already approved all the needed (and previewed) amounts.
            // As we cannot trust the caller to have provided the right asset/amount tuples
            // without changing their distribution or without tricking it (e.g. by repeating some assets),
            // we take one of those amount as reference and compute the others accordingly.
            uint256 refAssetWeight = weights[_lookupRegistrationIndex(asset)];
            if (refAssetWeight == 0) {
                ZeroWeight.selector.revertWith(asset);
            }
            uint8 decimals = ERC20(asset).decimals();
            uint256 refAmount = Utils.changeDecimals(amount, decimals, 18);
            refAmount = refAmount * 1e18 / refAssetWeight;
            for (uint256 i = 0; i < registeredAssets.length; i++) {
                amount = refAmount * weights[i] / 1e18;
                amount = vaults[registeredAssets[i]].convertToAssets(amount);

                honeyToMint += _mint(registeredAssets[i], amount, receiver, true);
            }
        }
    }

    /// @inheritdoc IHoneyFactory
    function redeem(
        address asset,
        uint256 honeyAmount,
        address receiver,
        bool expectBasketMode
    )
        external
        whenNotPaused
        returns (uint256[] memory redeemed)
    {
        _checkRegisteredAsset(asset);

        bool basketMode = isBasketModeEnabled(false);
        if (basketMode != expectBasketMode) {
            UnexpectedBasketModeStatus.selector.revertWith();
        }

        if (!basketMode) {
            redeemed = new uint256[](registeredAssets.length);
            uint256 index = _lookupRegistrationIndex(asset);
            redeemed[index] = _redeem(asset, honeyAmount, receiver);

            // When the redeemed asset is the reference collateral
            // it might block other assets on mint due to its usage in the computation of the relative cap limits.
            // Because of this, we need to check the relative cap limits for all the other assets.
            if (asset == referenceCollateral) {
                for (uint256 i = 0; i < registeredAssets.length; i++) {
                    if (registeredAssets[i] == asset) {
                        continue;
                    }
                    if (!_isCappedRelative(registeredAssets[i])) {
                        ExceedRelativeCap.selector.revertWith();
                    }
                }
            }

            if (!_isCappedGlobal(false, asset)) {
                ExceedGlobalCap.selector.revertWith();
            }

            return redeemed;
        }

        uint256[] memory weights = _getWeights(false, true);
        redeemed = new uint256[](registeredAssets.length);
        for (uint256 i = 0; i < registeredAssets.length; i++) {
            uint256 amount = honeyAmount * weights[i] / 1e18;

            redeemed[i] = _redeem(registeredAssets[i], amount, receiver);
        }
    }

    /// @inheritdoc IHoneyFactory
    function liquidate(
        address badCollateral,
        address goodCollateral,
        uint256 goodAmount
    )
        external
        whenNotPaused
        returns (uint256 badAmount)
    {
        _checkRegisteredAsset(badCollateral);
        _checkRegisteredAsset(goodCollateral);
        _checkGoodCollateralAsset(goodCollateral);

        if (!liquidationEnabled) {
            LiquidationDisabled.selector.revertWith();
        }
        if (!isBadCollateralAsset[badCollateral]) {
            AssetIsNotBadCollateral.selector.revertWith();
        }
        // If the bad collateral is the reference one, a liquidation may block other assets on mint
        // due to its usage in the computation of the relative cap limits.
        // As a conseguence, the reference asset must first be replaced.
        if (badCollateral == referenceCollateral) {
            LiquidationWithReferenceCollateral.selector.revertWith();
        }

        uint256 goodShares = _approveAndDeposit(goodCollateral, goodAmount);

        uint256 priceBad = _getPrice(badCollateral);
        uint256 priceGood = _getPrice(goodCollateral);
        badAmount = (goodShares * priceGood / priceBad) * (1e18 + liquidationRates[badCollateral]) / 1e18;

        uint256 badShares = _getSharesWithoutFees(badCollateral);
        if (badAmount > badShares) {
            // x = bs / (pg / pb) * (1 + r)
            // optimized (for gas and rounding issues) as:
            // x = bs * (pb / pg) / (1 + r)
            uint256 goodSharesAdjusted =
                (badShares * priceBad / priceGood) * 1e18 / (1e18 + liquidationRates[badCollateral]);
            _redeemShares(goodCollateral, goodShares - goodSharesAdjusted, msg.sender);
            badAmount = badShares;
        }

        if (!_isCappedRelative(goodCollateral)) {
            ExceedRelativeCap.selector.revertWith();
        }
        if (!_isCappedGlobal(false, badCollateral)) {
            ExceedGlobalCap.selector.revertWith();
        }

        badAmount = _redeemShares(badCollateral, badAmount, msg.sender);

        if (badAmount == 0) {
            ZeroAmount.selector.revertWith();
        }

        _checkInvariants(badCollateral);
        _checkInvariants(goodCollateral);
        emit Liquidated(badCollateral, goodCollateral, goodAmount, msg.sender);
    }

    /// @inheritdoc IHoneyFactory
    function recapitalize(address asset, uint256 amount) external whenNotPaused {
        _checkRegisteredAsset(asset);
        _checkGoodCollateralAsset(asset);
        uint256 targetBalance = recapitalizeBalanceThreshold[asset];
        uint256 feeAssetBalance = vaults[asset].convertToAssets(collectedAssetFees[asset]);
        uint256 currentBalance = vaults[asset].totalAssets() - feeAssetBalance;

        if (currentBalance >= targetBalance) {
            RecapitalizeNotNeeded.selector.revertWith(asset);
        }

        if (!isPegged(asset)) {
            NotPegged.selector.revertWith(asset);
        }

        if (currentBalance + amount > targetBalance) {
            amount = targetBalance - currentBalance;
        }

        // Convert the amount to shares to avoid the need of decimals handling.
        uint256 shares = vaults[asset].convertToShares(amount);

        if (shares < minSharesToRecapitalize) {
            InsufficientRecapitalizeAmount.selector.revertWith(amount);
        }

        _approveAndDeposit(asset, amount);

        if (!_isCappedRelative(asset)) {
            ExceedRelativeCap.selector.revertWith();
        }
        if (!_isCappedGlobal(true, asset)) {
            ExceedGlobalCap.selector.revertWith();
        }

        _checkInvariants(asset);
        emit Recapitalized(asset, amount, msg.sender);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          GETTERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Get the status of the basket mode.
    /// @dev On mint, basket mode is enabled if all collaterals are either depegged or bad.
    /// @dev On redeem, basket mode is enabled if at least one asset is deppegged
    /// except for the collateral assets that have been fully liquidated.
    function isBasketModeEnabled(bool isMint) public view returns (bool basketMode) {
        if (forcedBasketMode) {
            return true;
        }

        for (uint256 i = 0; i < registeredAssets.length; i++) {
            bool isPegged_ = isPegged(registeredAssets[i]);

            if (isMint) {
                if (isPegged_ && !isBadCollateralAsset[registeredAssets[i]]) {
                    // Basket mode should be disabled. It means there is a good collateral.
                    return false;
                }
            } else if (!isPegged_) {
                // If the not pegged asset is a bad collateral and its vault doesn't have shares
                // we can ignore it because it means it has been fully liquidated.
                bool usedAsCollateral = _getSharesWithoutFees(registeredAssets[i]) > 0;

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

    /// @notice Get weights of all the registered assets except for the paused ones.
    /// @return w weights of all the registered assets.
    function getWeights() external view returns (uint256[] memory w) {
        w = _getWeights(false, true);
    }

    /// @notice Get if an asset is pegged or not.
    /// @param asset The asset to check.
    /// @return true if the asset is pegged.
    function isPegged(address asset) public view returns (bool) {
        if (!priceOracle.priceAvailable(asset)) {
            return false;
        }
        IPriceOracle.Data memory data = priceOracle.getPriceUnsafe(asset);
        if (data.publishTime < block.timestamp - priceFeedMaxDelay) {
            return false;
        }
        return (1e18 - lowerPegOffsets[asset] <= data.price) && (data.price <= 1e18 + upperPegOffsets[asset]);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _mint(address asset, uint256 amount, address receiver, bool basketMode) internal returns (uint256) {
        if (amount == 0) {
            return 0;
        }

        uint256 shares = _approveAndDeposit(asset, amount);

        // The factory mints the corresponding amount of Honey to the receiver
        // with the consideration of the static mint fee.
        (uint256 honeyToMint, uint256 feeReceiverFeeShares, uint256 polFeeCollectorFeeShares) =
            _getHoneyMintedFromShares(asset, shares);

        // Updates the fee accounts for the minted shares.
        _handleFees(asset, polFeeCollectorFeeShares, feeReceiverFeeShares);
        if (!basketMode && !_isCappedRelative(asset)) {
            ExceedRelativeCap.selector.revertWith();
        }
        honey.mint(receiver, honeyToMint);

        _checkInvariants(asset);
        emit HoneyMinted(msg.sender, receiver, asset, amount, honeyToMint);
        return honeyToMint;
    }

    function _redeem(address asset, uint256 honeyAmount, address receiver) internal returns (uint256 redeemedAssets) {
        // The function reverts if the sender does not have enough Honey to burn or
        // the vault does not have enough assets to redeem.
        // The factory burns the corresponding amount of Honey of the sender
        // to get the shares and redeem them for assets from the vault.
        if (honeyAmount == 0) {
            return 0;
        }

        {
            (uint256 sharesForRedeem, uint256 feeReceiverFeeShares, uint256 polFeeCollectorFeeShares) =
                _getSharesRedeemedFromHoney(asset, honeyAmount);
            honey.burn(msg.sender, honeyAmount);
            // Updates the fee accounts for the redeemed shares.
            _handleFees(asset, polFeeCollectorFeeShares, feeReceiverFeeShares);
            // The factory redeems the corresponding amount of assets from Vault
            // and transfer the assets to the receiver.
            redeemedAssets = _redeemShares(asset, sharesForRedeem, receiver);
        }
        _checkInvariants(asset);

        emit HoneyRedeemed(msg.sender, receiver, asset, redeemedAssets, honeyAmount);
    }

    function _getHoneyMintedFromShares(
        address asset,
        uint256 shares
    )
        internal
        view
        returns (uint256 honeyAmount, uint256 feeReceiverFeeShares, uint256 polFeeCollectorFeeShares)
    {
        uint256 mintRate = mintRates[asset];
        honeyAmount = shares * mintRate / 1e18;
        uint256 feeShares = shares - honeyAmount;
        polFeeCollectorFeeShares = feeShares * polFeeCollectorFeeRate / 1e18;
        feeReceiverFeeShares = feeShares - polFeeCollectorFeeShares;
    }

    function _getSharesRedeemedFromHoney(
        address asset,
        uint256 honeyAmount
    )
        internal
        view
        returns (uint256 shares, uint256 feeReceiverFeeShares, uint256 polFeeCollectorFeeShares)
    {
        uint256 redeemRate = redeemRates[asset];
        shares = honeyAmount * redeemRate / 1e18;
        uint256 feeShares = honeyAmount - shares;
        // Distribute the fee to the polFeeCollector based on the polFeeCollectorFeeRate.
        polFeeCollectorFeeShares = feeShares * polFeeCollectorFeeRate / 1e18;
        // The remaining fee is distributed to the feeReceiver.
        feeReceiverFeeShares = feeShares - polFeeCollectorFeeShares;
    }

    function _getWeights(
        bool filterBadCollaterals,
        bool filterPausedCollateral
    )
        internal
        view
        returns (uint256[] memory weights)
    {
        weights = new uint256[](registeredAssets.length);
        uint256 sum = 0;
        for (uint256 i = 0; i < registeredAssets.length; i++) {
            if (filterBadCollaterals && isBadCollateralAsset[registeredAssets[i]]) {
                continue;
            }
            // If vault is paused, the weight of the asset is 0.
            if (filterPausedCollateral && vaults[registeredAssets[i]].paused()) {
                continue;
            }
            // NOTE: vault shares are always in WAD, regardless of the asset's decimals
            weights[i] = _getSharesWithoutFees(registeredAssets[i]);
            sum += weights[i];
        }

        if (sum == 0) {
            return weights;
        }
        for (uint256 i = 0; i < registeredAssets.length; i++) {
            weights[i] = weights[i] * 1e18 / sum;
        }
    }

    function _isCappedRelative(address asset) internal view returns (bool) {
        if (asset == referenceCollateral) {
            return true;
        }

        uint256 balance = _getSharesWithoutFees(asset);
        uint256 refBalance = _getSharesWithoutFees(referenceCollateral);

        if (refBalance == 0) {
            // If the balance of the asset is 0, it means that is capped
            // because the refence asset has also 0 balance.
            return (balance == 0) ? true : false;
        }
        uint256 weight = balance * 1e18 / refBalance;

        return weight <= relativeCap[asset];
    }

    function _isCappedGlobal(bool isMint, address collateralAsset) internal view returns (bool) {
        uint256[] memory weights = _getWeights(true, false);
        for (uint256 i = 0; i < registeredAssets.length; i++) {
            // Upon mint, we don't care about the other collaterals, as their weight can
            // only decrease; also, shall we check them all, it's enough to have at least
            // one of them that exceeds their weight to prevent the current mint.
            if (isMint && registeredAssets[i] != collateralAsset) {
                continue;
            }
            // Upon redeem, we always allows the weight of the asset to be reduced, even if
            // its current weight is already over the globalCap (due to a lowered value),
            // as long as it doesn't cause the other collateral to exceeds the limit.
            if (!isMint && registeredAssets[i] == collateralAsset) {
                continue;
            }
            if (weights[i] > globalCap) {
                return false;
            }
        }
        return true;
    }

    function _getPrice(address asset) internal view returns (uint256) {
        IPriceOracle.Data memory data = priceOracle.getPriceNoOlderThan(asset, priceFeedMaxDelay);
        return data.price;
    }

    /// @dev Returns the amount of the shares of the factory for the given asset excluding the fees.
    function _getSharesWithoutFees(address asset) internal view returns (uint256) {
        return vaults[asset].balanceOf(address(this)) - collectedAssetFees[asset];
    }

    function _approveAndDeposit(address asset, uint256 amount) internal returns (uint256 shares) {
        SafeTransferLib.safeTransferFrom(asset, msg.sender, address(this), amount);
        SafeTransferLib.safeApprove(asset, address(vaults[asset]), amount);
        shares = vaults[asset].deposit(amount, address(this));
    }

    function _redeemShares(address asset, uint256 shares, address receiver) internal returns (uint256) {
        return vaults[asset].redeem(shares, receiver, address(this));
    }

    /// @notice Handles the fee to distribute for a given asset to the PoL fee collector and the fee receiver.
    function _handleFees(address asset, uint256 polFeeCollectorFeeShares, uint256 feeReceiverFeeShares) internal {
        // The PoL fee collector's fee, if any, are transferred right away:
        if (polFeeCollectorFeeShares > 0) {
            _redeemShares(asset, polFeeCollectorFeeShares, polFeeCollector);
        }
        // The fee receiver's fee (shares), if any, are held until they are redeemed:
        if (feeReceiverFeeShares > 0) {
            collectedFees[feeReceiver][asset] += feeReceiverFeeShares;
            collectedAssetFees[asset] += feeReceiverFeeShares;
        }
    }

    /// @dev Check the invariant of the vault to ensure that assets are always sufficient to redeem.
    function _checkInvariants(address asset) internal view {
        ERC4626 vault = vaults[asset];
        uint256 totalShares = vault.totalSupply();
        uint256 totalAssets = ERC20(asset).balanceOf(address(vault));
        if (vault.convertToAssets(totalShares) > totalAssets) {
            InsufficientAssets.selector.revertWith(totalAssets, totalShares);
        }

        // A user cannot redeem also the collected fees
        uint256 vaultShares = vault.balanceOf(address(this));
        if (vaultShares < collectedAssetFees[asset]) {
            uint256 vaultAssets = vault.convertToAssets(vaultShares);
            InsufficientAssets.selector.revertWith(vaultAssets, vaultShares);
        }
    }
}
