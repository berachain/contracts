// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { LibClone } from "solady/src/utils/LibClone.sol";
import { ERC20 } from "solady/src/tokens/ERC20.sol";
import { ERC4626 } from "solady/src/tokens/ERC4626.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";
import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";
import { PythStructs } from "@pythnetwork/PythStructs.sol";
import { PythUtils } from "@pythnetwork/PythUtils.sol";

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { CollateralVault } from "src/honey/CollateralVault.sol";
import { HoneyBaseTest, HoneyFactory, VaultAdmin } from "./HoneyBase.t.sol";
import { IHoneyErrors } from "src/honey/IHoneyErrors.sol";
import { IHoneyFactory } from "src/honey/IHoneyFactory.sol";
import { Utils } from "src/libraries/Utils.sol";
import { MockVault, FaultyVault } from "@mock/honey/MockVault.sol";
import { MockUSDT, MockDummy, MockAsset } from "@mock/honey/MockAssets.sol";
import { MockFeed } from "@mock/oracle/MockFeed.sol";

contract HoneyFactoryTest is HoneyBaseTest {
    CollateralVault dummyVault;

    MockDummy dummy = new MockDummy();
    uint256 dummyBalance = 100e20; // 100 Dummy
    uint256 dummyMintRate = 0.99e18;
    uint256 dummyRedeemRate = 0.98e18;

    bytes32 dummyFeed = keccak256("DUMMY/USD");

    uint256 private constant PEG_OFFSET = 0.002e18;

    enum DepegDirection {
        UnderOneDollar,
        OverOneDollar
    }

    function setUp() public override {
        super.setUp();

        oracle.setPriceFeed(address(dummy), dummyFeed);
        pyth.setData(dummyFeed, int64(99_993_210), uint64(31_155), int32(-8), block.timestamp);

        dummy.mint(address(this), dummyBalance);
        vm.prank(governance);
        dummyVault = CollateralVault(address(factory.createVault(address(dummy))));
        vm.startPrank(manager);
        factory.setMintRate(address(dummy), dummyMintRate);
        factory.setRedeemRate(address(dummy), dummyRedeemRate);
        factory.setDepegOffsets(address(dai), PEG_OFFSET, PEG_OFFSET);
        factory.setDepegOffsets(address(usdt), PEG_OFFSET, PEG_OFFSET);
        factory.setDepegOffsets(address(dummy), PEG_OFFSET, PEG_OFFSET);
        vm.stopPrank();
    }

    function test_InitializeFactoryWithZeroAddresses() public {
        address beacon = factory.beacon();
        HoneyFactory newFactory = HoneyFactory(LibClone.deployERC1967(address(new HoneyFactory())));

        // initialize with zero address governance
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.ZeroAddress.selector));
        newFactory.initialize(address(0), address(honey), feeReceiver, polFeeCollector, address(oracle), beacon);

        // initialize with zero address honey
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.ZeroAddress.selector));
        newFactory.initialize(governance, address(0), feeReceiver, polFeeCollector, address(oracle), beacon);

        // initialize with zero address feeReceiver
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.ZeroAddress.selector));
        newFactory.initialize(governance, address(honey), address(0), polFeeCollector, address(oracle), beacon);

        // initialize with zero address polFeeCollector
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.ZeroAddress.selector));
        newFactory.initialize(governance, address(honey), feeReceiver, address(0), address(oracle), beacon);

        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.ZeroAddress.selector));
        newFactory.initialize(governance, address(honey), feeReceiver, polFeeCollector, address(oracle), address(0));
    }

    function test_Initialize_ParamsSet() public {
        assertEq(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), governance), true);
        assertEq(address(factory.honey()), address(honey));
        assertEq(factory.feeReceiver(), feeReceiver);
        assertEq(factory.polFeeCollector(), polFeeCollector);
        assertEq(factory.polFeeCollectorFeeRate(), 1e18);
    }

    function test_CreateVault() public {
        uint256 initialVaultsLength = factory.numRegisteredAssets();
        address dummyAsset = address(new MockDummy());
        address predictedVault = _predictVaultAddress(dummyAsset);
        oracle.setPriceFeed(dummyAsset, dummyFeed);
        vm.prank(governance);
        vm.expectEmit();
        emit VaultAdmin.VaultCreated(predictedVault, dummyAsset);
        address vault = address(factory.createVault(dummyAsset));
        assertEq(vault, predictedVault);
        // registeredAssets and vaults mappings are updated
        assertEq(address(factory.vaults(dummyAsset)), vault);
        assertEq(factory.numRegisteredAssets(), initialVaultsLength + 1);
    }

    function test_createVault_failsWithoutDefaultAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), factory.DEFAULT_ADMIN_ROLE()
            )
        );
        factory.createVault(address(dummy));
    }

    function test_createVault_failsWithZeroAddressAsset() external {
        vm.prank(governance);
        vm.expectRevert();
        factory.createVault(address(0));
    }

    function test_createVault_failsIfAssetIsDepegged() external {
        MockDummy dummyDepegged = new MockDummy();
        bytes32 depeggedFeedId = keccak256("DUMMY-2/USD");

        int64 depegPrice = 1e8 - int64(0.021e8);
        pyth.setData(depeggedFeedId, depegPrice, uint64(31_155), int32(-8), block.timestamp);
        oracle.setPriceFeed(address(dummyDepegged), depeggedFeedId);

        vm.startPrank(governance);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.NotPegged.selector, address(dummyDepegged)));
        factory.createVault(address(dummyDepegged));
    }

    function test_createAlreadyRegisteredVault() external {
        vm.prank(governance);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.VaultAlreadyRegistered.selector, address(dai)));
        factory.createVault(address(dai));
    }

    function test_setPriceOracle_failsIfNotAdmin(address priceOracle_) external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), factory.DEFAULT_ADMIN_ROLE()
            )
        );
        factory.setPriceOracle(priceOracle_);
    }

    function test_setPriceOracle_failsIfZero() external {
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.ZeroAddress.selector));

        vm.prank(governance);
        factory.setPriceOracle(address(0));
    }

    function test_setPriceOracle(address priceOracle_) external {
        vm.assume(priceOracle_ != address(0));

        vm.expectEmit();
        emit IHoneyFactory.PriceOracleSet(priceOracle_);

        vm.prank(governance);
        factory.setPriceOracle(priceOracle_);

        assertEq(address(factory.priceOracle()), priceOracle_);
    }

    function test_setReferenceCollateral_failsWithoutManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), MANAGER_ROLE
            )
        );
        factory.setReferenceCollateral(address(usdt));
    }

    function test_setReferenceCollateral_failsIfAssetIsNotRegistered() external {
        MockUSDT usdtNew = new MockUSDT(); // new unregistered usdt token instance
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssetNotRegistered.selector, address(usdtNew)));
        factory.setReferenceCollateral(address(usdtNew));
    }

    function test_SetReferenceCollateral() external {
        assertEq(factory.referenceCollateral(), address(dai));
        vm.prank(manager);
        vm.expectEmit();
        emit IHoneyFactory.ReferenceCollateralSet(address(dai), address(usdt));
        factory.setReferenceCollateral(address(usdt));
        assertEq(factory.referenceCollateral(), address(usdt));
    }

    function test_setLiquidationRate_failsWithoutAdminRole() external {
        uint256 newLiquidationRate = 0.5e18;
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), DEFAULT_ADMIN_ROLE
            )
        );
        factory.setLiquidationRate(address(dai), newLiquidationRate);
    }

    function test_setLiquidationRate_failsIfAssetIsNotRegistered() external {
        MockUSDT usdtNew = new MockUSDT(); // new unregistered usdt token instance
        vm.prank(governance);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssetNotRegistered.selector, address(usdtNew)));
        factory.setLiquidationRate(address(usdtNew), 0.5e18);
    }

    function test_setLiquidationRate() external {
        uint256 newLiquidationRate = 0.5e18;
        vm.prank(governance);
        vm.expectEmit();
        emit IHoneyFactory.LiquidationRateSet(address(dai), newLiquidationRate);
        factory.setLiquidationRate(address(dai), newLiquidationRate);
    }

    function test_setGlobalCap_failsWithoutManager() external {
        uint256 newGlobalCap = 50e18;
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), MANAGER_ROLE
            )
        );
        factory.setGlobalCap(newGlobalCap);
    }

    function test_SetGlobalCap() external {
        uint256 newGlobalCap = 50e18;
        vm.prank(manager);
        vm.expectEmit();
        emit IHoneyFactory.GlobalCapSet(newGlobalCap);
        factory.setGlobalCap(newGlobalCap);
        assertEq(factory.globalCap(), newGlobalCap);
    }

    function test_setRelativeCap_failsWithoutManager() external {
        uint256 newRelativeCap = 50e18;
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), MANAGER_ROLE
            )
        );
        factory.setRelativeCap(address(dai), newRelativeCap);
    }

    function test_SetRelativeCap() external {
        uint256 newRelativeCap = 50e18;
        vm.prank(manager);
        vm.expectEmit();
        emit IHoneyFactory.RelativeCapSet(address(dai), newRelativeCap);
        factory.setRelativeCap(address(dai), newRelativeCap);
        assertEq(factory.relativeCap(address(dai)), newRelativeCap);
    }

    function test_setDepegOffsets_failsWithoutManager() external {
        uint256 newOffset = 0.01e18; // 1 cent
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), MANAGER_ROLE
            )
        );
        factory.setDepegOffsets(address(dai), newOffset, newOffset);
    }

    function test_setDepegOffsets_failsOutOfRance() external {
        uint256 newOffset = 0.03e18; // 1 cent
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AmountOutOfRange.selector));
        factory.setDepegOffsets(address(dai), newOffset, newOffset);
    }

    function test_setDepegOffsets_failsIfAssetIsNotRegistered() external {
        MockUSDT usdtNew = new MockUSDT(); // new unregistered usdt token instance
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssetNotRegistered.selector, address(usdtNew)));
        factory.setDepegOffsets(address(usdtNew), 0.01e18, 0.01e18);
    }

    function testFuzz_setDepegOffsets(uint256 lowerOffset, uint256 upperOffset) public {
        lowerOffset = _bound(lowerOffset, 0, 0.02e18);
        upperOffset = _bound(upperOffset, 0, 0.02e18);
        vm.startPrank(manager);
        vm.expectEmit();
        emit IHoneyFactory.DepegOffsetsSet(address(dai), lowerOffset, upperOffset);
        factory.setDepegOffsets(address(dai), lowerOffset, upperOffset);
    }

    function test_setMaxDelay_failsWithoutManager() external {
        uint256 newMaxDelay = 60 seconds;
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), MANAGER_ROLE
            )
        );
        factory.setMaxFeedDelay(newMaxDelay);
    }

    function test_setMaxDelay_failsOutOfRange() external {
        uint256 newMaxDelay = 121 seconds;
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AmountOutOfRange.selector));
        factory.setMaxFeedDelay(newMaxDelay);
    }

    function testFuzz_setMaxDelay(uint256 newMaxDelay) public {
        newMaxDelay = _bound(newMaxDelay, 0, 60 seconds);
        vm.startPrank(manager);
        vm.expectEmit();
        emit IHoneyFactory.MaxFeedDelaySet(newMaxDelay);
        factory.setMaxFeedDelay(newMaxDelay);
        assertEq(factory.priceFeedMaxDelay(), newMaxDelay);
    }

    function test_ForceBasketModeWhenMint() public {
        assertFalse(factory.isBasketModeEnabled(true));
        vm.prank(manager);
        vm.expectEmit();
        emit IHoneyFactory.BasketModeForced(true);
        factory.setForcedBasketMode(true);

        assertTrue(factory.forcedBasketMode());
        assertTrue(factory.isBasketModeEnabled(true));
    }

    function test_ForceBasketModeWhenRedeem() public {
        assertFalse(factory.isBasketModeEnabled(false));
        vm.prank(manager);
        vm.expectEmit();
        emit IHoneyFactory.BasketModeForced(true);
        factory.setForcedBasketMode(true);

        assertTrue(factory.forcedBasketMode());
        assertTrue(factory.isBasketModeEnabled(false));
    }

    function test_forceBasketMode_FailsWithoutManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), MANAGER_ROLE
            )
        );
        factory.setForcedBasketMode(true);
    }

    function test_BasketModeEnabledWhenAllFeedsAreStale_WhenMint() external {
        // basket mode is disabled because all the feeds are pegged and the price is not stale
        assertFalse(factory.isBasketModeEnabled(true));
        // Increase chain time in order to set the time to the upper bound of the stale price
        vm.warp(block.timestamp + factory.priceFeedMaxDelay());
        assertFalse(factory.isBasketModeEnabled(true));
        // Increase time to the upper bound of the stale price + 1
        vm.warp(block.timestamp + 1);
        // Because all the feeds are pegged due to the stale price, basket mode should be enabled
        assertTrue(factory.isBasketModeEnabled(true));
    }

    function test_BasketModeEnabledWhenStalePriceOnOneFeed_DisabledWhenMint() external {
        // basket mode is disabled because all the feeds are pegged and the price is not stale
        assertFalse(factory.isBasketModeEnabled(true));
        // Increase chain time in order to set the time to the upper bound of the stale price
        vm.warp(block.timestamp + factory.priceFeedMaxDelay());
        assertFalse(factory.isBasketModeEnabled(true));
        // Increase time to the upper bound of the stale price + 1
        vm.warp(block.timestamp + 1);
        // Because all the feeds are not pegged due to the stale price, basket mode should be enabled
        assertTrue(factory.isBasketModeEnabled(true));

        // Change price feed to a non-stale price
        pyth.setData(daiFeed, int64(99_993_210), uint64(31_155), int32(-8), block.timestamp);
        pyth.setData(usdtFeed, int64(99_993_210), uint64(31_155), int32(-8), block.timestamp);
        // If there is one stale price, basket mode should be disable on mint because of 2 good feeds
        assertFalse(factory.isBasketModeEnabled(true));
        // Make the last price feed non-stale
        pyth.setData(dummyFeed, int64(99_993_210), uint64(31_155), int32(-8), block.timestamp);
        // If all price feeds are non-stale, basket mode should be disabled
        assertFalse(factory.isBasketModeEnabled(true));
    }

    function test_BasketModeEnabledWhenStalePriceOnOneFeed_WhenRedeem() external {
        _factoryMint(dai, daiBalance, receiver, false);
        // basket mode is disabled because all the feeds are pegged and the price is not stale
        assertFalse(factory.isBasketModeEnabled(false));
        // Increase chain time in order to set the time to the upper bound of the stale price
        vm.warp(block.timestamp + factory.priceFeedMaxDelay());
        assertFalse(factory.isBasketModeEnabled(false));
        // Increase time to the upper bound of the stale price + 1
        vm.warp(block.timestamp + 1);
        assertTrue(factory.isBasketModeEnabled(false));

        // Change price feed to a non-stale price
        pyth.setData(dummyFeed, int64(99_993_210), uint64(31_155), int32(-8), block.timestamp);
        pyth.setData(usdtFeed, int64(99_993_210), uint64(31_155), int32(-8), block.timestamp);
        // Basket mode is enabled because of the dai collateral is used and it's still stale.
        assertTrue(factory.isBasketModeEnabled(false));
        // Make the last price feed non-stale
        pyth.setData(daiFeed, int64(99_993_210), uint64(31_155), int32(-8), block.timestamp);
        // If all price feeds are non-stale, basket mode should be disabled
        assertFalse(factory.isBasketModeEnabled(false));
    }

    function testFuzz_BasketModeDisabledWhenAnAssetDepegUnderOneDollar_WhenMint(uint256 pegOffset) public {
        pegOffset = _bound(pegOffset, PEG_OFFSET + 0.1e18, 1e18 - 0.1e18);
        // basket mode is disabled because all the feeds are pegged and the price is not stale
        assertFalse(factory.isBasketModeEnabled(true));

        // Depeg the usdt asset
        _depegFeed(usdtFeed, pegOffset, DepegDirection.UnderOneDollar);
        assertFalse(factory.isBasketModeEnabled(true));
    }

    function testFuzz_BasketModeEnabledWhenAllAssetsDepegUnderOneDollar_WhenMint(uint256 pegOffset) public {
        pegOffset = _bound(pegOffset, PEG_OFFSET + 0.1e18, 1e18 - 0.1e18);
        // basket mode is disabled because all the feeds are pegged and the price is not stale
        assertFalse(factory.isBasketModeEnabled(true));

        // Depeg all the assets
        _depegFeed(daiFeed, pegOffset, DepegDirection.UnderOneDollar);
        _depegFeed(usdtFeed, pegOffset, DepegDirection.UnderOneDollar);
        _depegFeed(dummyFeed, pegOffset, DepegDirection.UnderOneDollar);

        assertTrue(factory.isBasketModeEnabled(true));
    }

    function testFuzz_BasketModeDisabledWhenAnAssetDepegUnderOneDollarAndItIsNotUsedAsCollateral_WhenRedeem(
        uint256 pegOffset
    )
        public
    {
        pegOffset = _bound(pegOffset, PEG_OFFSET + 0.1e18, 1e18 - 0.1e18);
        // basket mode is disabled because all the feeds are pegged and the price is not stale
        assertFalse(factory.isBasketModeEnabled(false));

        // Depeg the usdt asset
        _depegFeed(usdtFeed, pegOffset, DepegDirection.UnderOneDollar);
        assertFalse(factory.isBasketModeEnabled(false));
    }

    function testFuzz_BasketModeEnabledWhenAnAssetDepegUnderOneDollarAndItUsedAsCollateral_WhenRedeem(
        uint256 daiToMint,
        uint256 pegOffset
    )
        public
    {
        pegOffset = _bound(pegOffset, PEG_OFFSET + 1e10, 1e18);
        daiToMint = _bound(daiToMint, 1e18, daiBalance);
        // basket mode is disabled because all the feeds are pegged and the price is not stale
        assertFalse(factory.isBasketModeEnabled(false));

        _factoryMint(dai, daiToMint, receiver, false);

        // Depeg the usdt asset
        _depegFeed(daiFeed, pegOffset, DepegDirection.UnderOneDollar);
        assertTrue(factory.isBasketModeEnabled(false));
    }

    function testFuzz_BasketModeDisabledWhenAnAssetDepegOverOneDollar_WhenMint(uint256 pegOffset) public {
        pegOffset = _bound(pegOffset, PEG_OFFSET + 1e10, 1e18);
        // basket mode is disabled because all the feeds are pegged and the price is not stale
        assertFalse(factory.isBasketModeEnabled(true));

        // Depeg the usdt asset
        _depegFeed(usdtFeed, pegOffset, DepegDirection.OverOneDollar);
        assertFalse(factory.isBasketModeEnabled(true));
    }

    function testFuzz_BasketModeEnabledWhenAllAssetsDepegOverOneDollar_WhenMint(uint256 pegOffset) public {
        pegOffset = _bound(pegOffset, PEG_OFFSET + 1e10, 1e18);
        // basket mode is disabled because all the feeds are pegged and the price is not stale
        assertFalse(factory.isBasketModeEnabled(true));

        // Depeg all the assets
        _depegFeed(daiFeed, pegOffset, DepegDirection.OverOneDollar);
        _depegFeed(usdtFeed, pegOffset, DepegDirection.OverOneDollar);
        _depegFeed(dummyFeed, pegOffset, DepegDirection.OverOneDollar);
        assertTrue(factory.isBasketModeEnabled(true));
    }

    function testFuzz_BasketModeDisabledWhenAnAssetDepegOverOneDollarButItIsNotUsedAsCollateral_WhenRedeem(
        uint256 pegOffset
    )
        public
    {
        pegOffset = _bound(pegOffset, PEG_OFFSET + 1e10, 1e18);
        // basket mode is disabled because all the feeds are pegged and the price is not stale
        assertFalse(factory.isBasketModeEnabled(false));

        // Depeg the usdt asset
        _depegFeed(usdtFeed, pegOffset, DepegDirection.OverOneDollar);
        // Basket mode is keeped disabled because the asset has not used.
        assertFalse(factory.isBasketModeEnabled(false));
    }

    function testFuzz_BasketModeEnabledWhenAnAssetDepegOverOneDollarAndItUsedAsCollateral_WhenRedeem(
        uint256 daiToMint,
        uint256 pegOffset
    )
        public
    {
        pegOffset = _bound(pegOffset, PEG_OFFSET + 1e10, 1e18);
        daiToMint = _bound(daiToMint, 1e18, daiBalance);
        // basket mode is disabled because all the feeds are pegged and the price is not stale
        assertFalse(factory.isBasketModeEnabled(false));

        _factoryMint(dai, daiToMint, receiver, false);

        // Depeg the usdt asset
        _depegFeed(daiFeed, pegOffset, DepegDirection.OverOneDollar);
        assertTrue(factory.isBasketModeEnabled(false));
    }

    function test_BaskedModeIsDisabledWhenBadAssetIsDepeggedAndFullyLiquidated_WhenRedeem() external {
        // basket mode is disabled because all the feeds are pegged and the price is not stale
        vm.prank(governance);
        factory.setLiquidationEnabled(true);

        assertFalse(factory.isBasketModeEnabled(false));

        _factoryMint(dai, 100e18, receiver, false);
        _factoryMint(usdt, 100e6, receiver, false);

        // Depeg the usdt asset
        _depegFeed(usdtFeed, PEG_OFFSET + 1e10, DepegDirection.OverOneDollar);

        // set usdt as bad collateral
        vm.prank(manager);
        factory.setCollateralAssetStatus(address(usdt), true);

        // basket mode is still enabled because the asset is depegged but it has shares
        assertTrue(factory.isBasketModeEnabled(false));

        // Liquidate the usdt asset
        dai.approve(address(factory), 100e18);
        factory.liquidate(address(usdt), address(dai), 100e18);

        // Now basket mode is disabled because the asset is depegged and fully liquidated
        assertFalse(factory.isBasketModeEnabled(false));
    }

    function testFuzz_setMintRate(uint256 _mintRate) external {
        _mintRate = _bound(_mintRate, 98e16, 1e18);
        vm.prank(manager);
        vm.expectEmit();
        emit IHoneyFactory.MintRateSet(address(dai), _mintRate);
        factory.setMintRate(address(dai), _mintRate);
        assertEq(factory.mintRates(address(dai)), _mintRate);
    }

    function testFuzz_setRedeemRate(uint256 _redeemRate) external {
        _redeemRate = _bound(_redeemRate, 98e16, 1e18);
        vm.prank(manager);
        vm.expectEmit();
        emit IHoneyFactory.RedeemRateSet(address(dai), _redeemRate);
        factory.setRedeemRate(address(dai), _redeemRate);
        assertEq(factory.redeemRates(address(dai)), _redeemRate);
    }

    function test_setMintRate_failsWithoutManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), MANAGER_ROLE
            )
        );
        factory.setMintRate(address(dai), 1e18);
    }

    function test_setRedeemRate_failsWithoutManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), MANAGER_ROLE
            )
        );
        factory.setRedeemRate(address(dai), 1e18);
    }

    function testFuzz_setMintRate_failsWithOverOneHundredPercentRate(uint256 _mintRate) external {
        _mintRate = _bound(_mintRate, 1e18 + 1, type(uint256).max);
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.OverOneHundredPercentRate.selector, _mintRate));
        factory.setMintRate(address(dai), _mintRate);
    }

    function testFuzz_setRedeemRate_failsWithOverOneHundredPercentRate(uint256 _redeemRate) external {
        _redeemRate = _bound(_redeemRate, 1e18 + 1, type(uint256).max);
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.OverOneHundredPercentRate.selector, _redeemRate));
        factory.setRedeemRate(address(dai), _redeemRate);
    }

    function testFuzz_setMintRate_failsWithUnderNinetyEightPercentRate(uint256 _mintRate) external {
        _mintRate = _bound(_mintRate, 0, 98e16 - 1);
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.UnderNinetyEightPercentRate.selector, _mintRate));
        factory.setMintRate(address(dai), _mintRate);
    }

    function testFuzz_setRedeemRate_failsWithUnderNinetyEightPercentRate(uint256 _redeemRate) external {
        _redeemRate = _bound(_redeemRate, 0, 98e16 - 1);
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.UnderNinetyEightPercentRate.selector, _redeemRate));
        factory.setRedeemRate(address(dai), _redeemRate);
    }

    function test_setPOLFeeCollectorFeeRate_failsWithoutAdminRole() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), DEFAULT_ADMIN_ROLE
            )
        );
        factory.setPOLFeeCollectorFeeRate(1e18);
    }

    function test_setPOLFeeCollectorFeeRate_failsWithOverOneHundredPercentRate(uint256 _polFeeCollectorFeeRate)
        external
    {
        _polFeeCollectorFeeRate = _bound(_polFeeCollectorFeeRate, 1e18 + 1, type(uint256).max);
        vm.prank(governance);
        vm.expectRevert(
            abi.encodeWithSelector(IHoneyErrors.OverOneHundredPercentRate.selector, _polFeeCollectorFeeRate)
        );
        factory.setPOLFeeCollectorFeeRate(_polFeeCollectorFeeRate);
    }

    function test_setPOLFeeCollectorFeeRate() external {
        uint256 polFeeCollectorFeeRate = 1e16; // 1%
        testFuzz_setPOLFeeCollectorFeeRate(polFeeCollectorFeeRate);
    }

    function testFuzz_setPOLFeeCollectorFeeRate(uint256 _polFeeCollectorFeeRate) public {
        _polFeeCollectorFeeRate = _bound(_polFeeCollectorFeeRate, 0, 1e18);
        vm.expectEmit();
        emit IHoneyFactory.POLFeeCollectorFeeRateSet(_polFeeCollectorFeeRate);
        vm.prank(governance);
        factory.setPOLFeeCollectorFeeRate(_polFeeCollectorFeeRate);
        assertEq(factory.polFeeCollectorFeeRate(), _polFeeCollectorFeeRate);
    }

    function test_setMinSharesToRecapitalize_failsWithoutAdminRole() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), DEFAULT_ADMIN_ROLE
            )
        );
        factory.setMinSharesToRecapitalize(1e18);
    }

    function testFuzz_setMinSharesToRecapitalize_failsAmountOutOfRange(uint256 amount) external {
        uint256 MINIMUM_SHARES_TO_RECAPITALIZE = 1e18;
        amount = _bound(amount, 0, MINIMUM_SHARES_TO_RECAPITALIZE - 1);
        vm.prank(governance);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AmountOutOfRange.selector, amount));
        factory.setMinSharesToRecapitalize(amount);
    }

    function testFuzz_setMinSharesToRecapitalize(uint256 amount) public {
        uint256 MINIMUM_SHARES_TO_RECAPITALIZE = 1e18;
        amount = _bound(amount, MINIMUM_SHARES_TO_RECAPITALIZE, type(uint256).max);
        vm.prank(governance);
        vm.expectEmit();
        emit IHoneyFactory.MinSharesToRecapitalizeSet(amount);
        factory.setMinSharesToRecapitalize(amount);

        assertEq(factory.minSharesToRecapitalize(), amount);
    }

    function test_setRecapitalizeBalanceThreshold_failsWithoutAdminRole() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), DEFAULT_ADMIN_ROLE
            )
        );
        factory.setRecapitalizeBalanceThreshold(address(usdt), 1e18);
    }

    function testFuzz_setRecapitalizeBalanceThreshold(uint256 amount) public {
        vm.prank(governance);
        vm.expectEmit();
        emit IHoneyFactory.RecapitalizeBalanceThresholdSet(address(usdt), amount);
        factory.setRecapitalizeBalanceThreshold(address(usdt), amount);

        assertEq(factory.recapitalizeBalanceThreshold(address(usdt)), amount);
    }

    function testFuzz_mint_failsWithUnregisteredAsset(uint32 _usdtToMint) external {
        MockUSDT usdtNew = new MockUSDT(); // new unregistered usdt token instance
        usdtNew.mint(address(this), _usdtToMint);
        usdtNew.approve(address(factory), _usdtToMint);

        vm.prank(governance);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssetNotRegistered.selector, address(usdtNew)));
        factory.mint(address(usdtNew), _usdtToMint, receiver, false);
    }

    function test_mint_failsWithBadCollateralAsset() external {
        // sets dai as bad collateral asset.
        test_setCollateralAssetStatus();

        dai.approve(address(factory), 100e18);

        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssetIsBadCollateral.selector, address(dai)));
        factory.mint(address(dai), 100e18, receiver, false);
    }

    function test_mint_failsWhenVaultIsPaused() external {
        dai.approve(address(factory), 100e18);
        vm.prank(pauser);
        factory.pauseVault(address(dai));

        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.VaultPaused.selector, address(dai)));
        factory.mint(address(dai), 100e18, receiver, false);
    }

    function testFuzz_mint_failsWithPausedFactory(uint128 _daiToMint) external {
        vm.prank(pauser);
        factory.pause();

        dai.approve(address(factory), _daiToMint);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        factory.mint(address(dai), _daiToMint, receiver, false);
    }

    function testFuzz_mint_failsIfExceedsGlobalCap(uint256 usdtToMint) external {
        uint256 daiToMint = 100e18;
        usdtToMint = _bound(usdtToMint, 1e6, 99e6);

        _provideReferenceCollateral(daiToMint);
        _factoryMint(usdt, usdtToMint, receiver, false);

        assertEq(daiVault.balanceOf(address(factory)), daiToMint * daiMintRate / 1e18);
        assertEq(usdtVault.balanceOf(address(factory)), usdtToMint * 10 ** 12 * usdtMintRate / 1e18);

        uint256 daiWeight = daiToMint * 1e18 / (daiToMint + usdtVault.convertToShares(usdtToMint));
        vm.prank(manager);
        factory.setGlobalCap(daiWeight);

        dai.approve(address(factory), 1e18);
        vm.expectRevert(IHoneyErrors.ExceedGlobalCap.selector);
        factory.mint(address(dai), 1e18, receiver, false);
    }

    function testFuzz_mint_failsIfExceedsRelativeCap(uint256 usdtToMint, uint256 referenceCollateralToMint) external {
        referenceCollateralToMint = _bound(referenceCollateralToMint, 1e12, 100e18);
        // reference collateral to mint is the lower bound
        // so usdToMint will always be greater than referenceCollateralToMint
        usdtToMint = _bound(usdtToMint, referenceCollateralToMint / 10 ** 12 + 1, usdtBalance);
        assertGt(usdtToMint * 10 ** 12, referenceCollateralToMint);

        usdt.approve(address(factory), usdtToMint);
        vm.expectRevert(IHoneyErrors.ExceedRelativeCap.selector);
        factory.mint(address(usdt), usdtToMint, receiver, false);
    }

    function testFuzz_mint_failsWithInsufficientAllowance(uint256 _daiToMint) external {
        _daiToMint = _bound(_daiToMint, 1, daiBalance);

        dai.approve(address(factory), _daiToMint - 1);

        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        factory.mint(address(dai), _daiToMint, receiver, false);
    }

    function test_mint_failsWhenAssetIsDepegged() external {
        _initialMint(100e18);
        _depegFeed(daiFeed, PEG_OFFSET + 1e10, DepegDirection.OverOneDollar);

        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.NotPegged.selector, address(dai)));
        factory.mint(address(dai), 100e18, receiver, false);
    }

    function testFuzz_mint(uint256 _daiToMint) external {
        _daiToMint = _bound(_daiToMint, 0, daiBalance);
        uint256 mintedHoneys = _factoryMint(dai, _daiToMint, receiver, false);
        _verifyOutputOfMint(dai, daiVault, daiBalance, _daiToMint, mintedHoneys);
    }

    function testFuzz_mintWithLowerDecimalAsset(uint256 _usdtToMint) public returns (uint256 mintedHoneysForUsdt) {
        _usdtToMint = _bound(_usdtToMint, 0, daiBalance / 1e12);

        uint256 mintedHoneyForDai = _provideReferenceCollateral(daiBalance);
        mintedHoneysForUsdt = _factoryMint(usdt, _usdtToMint, receiver, false);

        uint256 mintedHoneys = mintedHoneyForDai + mintedHoneysForUsdt;
        _verifyOutputOfMint(usdt, usdtVault, usdtBalance, _usdtToMint, mintedHoneys);
    }

    function testFuzz_mintWithHigherDecimalAsset(uint256 _dummyToMint) external {
        _dummyToMint = _bound(_dummyToMint, 0.001e20, dummyBalance);
        // Needed in order to allow the minting of the dummy token due to relative cap protection.
        uint256 mintedHoneyForDai = _factoryMint(dai, daiBalance, receiver, false);
        // uint256 mintedHoneysForDummy = (((_dummyToMint / dummyOverHoneyRate)) * dummyMintRate) / 1e18;
        uint256 mintedHoneysForDummy = _factoryMint(dummy, _dummyToMint, receiver, false);

        uint256 mintedHoneys = mintedHoneyForDai + mintedHoneysForDummy;
        _verifyOutputOfMint(dummy, dummyVault, dummyBalance, _dummyToMint, mintedHoneys);
    }

    function test_mint() public {
        uint256 _daiToMint = 100e18;
        uint256 mintedHoneys = (_daiToMint * daiMintRate) / 1e18;
        dai.approve(address(factory), _daiToMint);

        vm.expectEmit();
        emit IHoneyFactory.HoneyMinted(address(this), receiver, address(dai), _daiToMint, mintedHoneys);
        mintedHoneys = factory.mint(address(dai), _daiToMint, receiver, false);
    }

    function test_mint_failsIfDepositAssetWithZeroWeightWhenBasketModeIsEnabled() external {
        uint256 usdtToMint = 100e6;
        // Deposit reference collateral
        _initialMint(100e18);
        _forceBasketMode();

        usdt.approve(address(factory), usdtToMint);
        // The assumption is: Basket mode ensures the distribution of the weight of the assets
        // If the weight of the deposit asset is zero, the minting should fail
        // because it move upon a specific direction the distribution of the collateral
        // making the distribution changed.
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.ZeroWeight.selector, address(usdt)));
        factory.mint(address(usdt), usdtToMint, receiver, true);
    }

    function testFuzz_mint_WhenBasketModeIsEnabledBecauseOfAllAssetsAreDepegged(uint256 honeyToMintBM) external {
        uint256 initialDaiToMint = daiBalance / 2;
        uint256 usdtToMint = initialDaiToMint / 1e12;
        uint256 dummyToMint = initialDaiToMint * 1e2;

        uint256 initialWeightRatio = uint256(1e18) / 3;

        honeyToMintBM = _bound(honeyToMintBM, 1, 1e30);
        uint256 dummyToUseForMint = (honeyToMintBM * 1e18) / dummyMintRate * 1e2;

        // Deposit reference collateral and another asset in 33/33/33 ratio
        uint256 initialHoneyMintForDai = _factoryMint(dai, initialDaiToMint, receiver, false);
        uint256 initialHoneyMintForUsdt = _factoryMint(usdt, usdtToMint, receiver, false);
        uint256 initialHoneyMintForDummy = _factoryMint(dummy, dummyToMint, receiver, false);

        uint256 numAssets = factory.numRegisteredAssets();
        uint256[] memory weights = factory.getWeights();

        for (uint256 i = 0; i < numAssets; i++) {
            assertEq(weights[i], initialWeightRatio);
        }

        // Depeg all the asset to ensure that the basket mode is enabled
        _depegFeed(daiFeed, PEG_OFFSET, DepegDirection.OverOneDollar);
        _depegFeed(usdtFeed, PEG_OFFSET, DepegDirection.OverOneDollar);
        _depegFeed(dummyFeed, PEG_OFFSET, DepegDirection.UnderOneDollar);

        assertTrue(factory.isBasketModeEnabled(true));
        // Get previews minted honeys and the amount required of each asset required to mint.
        uint256[] memory amounts = factoryReader.previewMintCollaterals(address(dummy), honeyToMintBM);

        assertEq(dai.allowance(address(this), address(factory)), 0);
        assertEq(usdt.allowance(address(this), address(factory)), 0);
        assertEq(dummy.allowance(address(this), address(factory)), 0);

        for (uint256 i = 0; i < numAssets; i++) {
            address asset = factory.registeredAssets(i);
            if (asset == address(dummy)) {
                dummyToUseForMint = amounts[i];
            }
            uint256 balance = ERC20(asset).balanceOf(address(this));
            if (balance < amounts[i]) {
                MockAsset(asset).mint(address(this), amounts[i] - balance);
            }
            ERC20(asset).approve(address(factory), amounts[i]);
        }

        uint256 mintedHoneys = factory.mint(address(dummy), dummyToUseForMint, receiver, true);

        assertApproxEqAbs(dai.allowance(address(this), address(factory)), 0, 1e2);
        assertApproxEqAbs(usdt.allowance(address(this), address(factory)), 0, 1);
        assertApproxEqAbs(dummy.allowance(address(this), address(factory)), 0, 1e3);

        uint256 daiShares = daiVault.balanceOf(address(factory));
        uint256 usdtShares = usdtVault.balanceOf(address(factory));
        uint256 dummyShares = dummyVault.balanceOf(address(factory));

        weights = factory.getWeights();

        // Accept a very small variation during the mint in basket mode. At max the variation should be 0.000001
        // respect of the initial weight ratio of 0.333333333333333333
        for (uint256 i = 0; i < numAssets; i++) {
            assertApproxEqAbs(weights[i], initialWeightRatio, 0.000001e18);
        }

        assertApproxEqAbs(initialHoneyMintForDai + (mintedHoneys * initialWeightRatio / 1e18), daiShares, 0.000001e18);
        assertApproxEqAbs(
            initialHoneyMintForUsdt + (mintedHoneys * initialWeightRatio / 1e18), usdtShares, 0.000001e18
        );
        assertApproxEqAbs(
            initialHoneyMintForDummy + (mintedHoneys * initialWeightRatio / 1e18), dummyShares, 0.000001e18
        );
    }

    function testFuzz_mint_WhenBasketModeIsEnabledAndAllAssetsAreDepeggedOrBadCollateral(uint256 honeyToMintBM)
        external
    {
        uint256 initialDaiToMint = daiBalance / 2;
        uint256 usdtToMint = initialDaiToMint / 1e12;
        uint256 dummyToMint = initialDaiToMint * 1e2;

        uint256 initialWeightRatio = uint256(1e18) / 3;

        honeyToMintBM = _bound(honeyToMintBM, 1, 1e30);
        uint256 dummyToUseForMint = (honeyToMintBM * 1e18) / dummyMintRate * 1e2;

        // Deposit reference collateral and another asset in 33/33/33 ratio
        uint256 initialHoneyMintForDai = _factoryMint(dai, initialDaiToMint, receiver, false);
        uint256 initialHoneyMintForUsdt = _factoryMint(usdt, usdtToMint, receiver, false);
        uint256 initialHoneyMintForDummy = _factoryMint(dummy, dummyToMint, receiver, false);

        uint256 numAssets = factory.numRegisteredAssets();
        uint256[] memory weights = factory.getWeights();

        for (uint256 i = 0; i < numAssets; i++) {
            assertEq(weights[i], initialWeightRatio);
        }

        // Depeg all the asset to ensure that the basket mode is enabled
        vm.startPrank(manager);
        factory.setCollateralAssetStatus(address(dai), true);
        factory.setCollateralAssetStatus(address(usdt), true);
        factory.setCollateralAssetStatus(address(dummy), true);
        vm.stopPrank();

        assertTrue(factory.isBasketModeEnabled(true));
        // Get previews minted honeys and the amount required of each asset required to mint.
        uint256[] memory amounts = factoryReader.previewMintCollaterals(address(dummy), honeyToMintBM);

        for (uint256 i = 0; i < numAssets; i++) {
            address asset = factory.registeredAssets(i);
            if (asset == address(dummy)) {
                dummyToUseForMint = amounts[i];
            }

            uint256 balance = ERC20(asset).balanceOf(address(this));
            if (balance < amounts[i]) {
                MockAsset(asset).mint(address(this), amounts[i] - balance);
            }
            ERC20(asset).approve(address(factory), amounts[i]);
        }

        uint256 mintedHoneys = factory.mint(address(dummy), dummyToUseForMint, receiver, true);

        assertApproxEqAbs(dai.allowance(address(this), address(factory)), 0, 1e2);
        assertApproxEqAbs(usdt.allowance(address(this), address(factory)), 0, 1);
        assertApproxEqAbs(dummy.allowance(address(this), address(factory)), 0, 1e3);

        uint256 daiShares = daiVault.balanceOf(address(factory));
        uint256 usdtShares = usdtVault.balanceOf(address(factory));
        uint256 dummyShares = dummyVault.balanceOf(address(factory));

        weights = factory.getWeights();

        // Accept a very small variation during the mint in basket mode. At max the variation should be 0.000001
        // respect of the initial weight ratio of 0.333333333333333333
        for (uint256 i = 0; i < numAssets; i++) {
            assertApproxEqAbs(weights[i], initialWeightRatio, 0.000001e18);
        }

        // Ensure that the overall honey minted for DAI matches the
        assertApproxEqAbs(initialHoneyMintForDai + (mintedHoneys * initialWeightRatio / 1e18), daiShares, 0.000001e18);
        assertApproxEqAbs(
            initialHoneyMintForUsdt + (mintedHoneys * initialWeightRatio / 1e18), usdtShares, 0.000001e18
        );
        assertApproxEqAbs(
            initialHoneyMintForDummy + (mintedHoneys * initialWeightRatio / 1e18), dummyShares, 0.000001e18
        );
    }

    function test_mint_WhenBasketModeIsEnabledAndAVaultIsPaused() external {
        uint256 daiToMint = daiBalance / 2;
        uint256 usdtToMint = daiToMint / 1e12;
        uint256 dummyToMint = daiToMint * 1e2;

        uint256 initialWeightRatio = uint256(1e18) / 3;

        uint256 honeyToMintBM = 50e18;
        uint256 usdtToUseForMint = (honeyToMintBM * 1e18) / usdtMintRate * 1e2;

        // Deposit reference collateral and another asset in 33/33/33 ratio
        _factoryMint(dai, daiToMint, receiver, false);
        _factoryMint(usdt, usdtToMint, receiver, false);
        _factoryMint(dummy, dummyToMint, receiver, false);

        // Depeg all the asset to ensure that the basket mode is enabled
        _depegFeed(daiFeed, PEG_OFFSET, DepegDirection.OverOneDollar);
        _depegFeed(usdtFeed, PEG_OFFSET, DepegDirection.OverOneDollar);
        _depegFeed(dummyFeed, PEG_OFFSET, DepegDirection.UnderOneDollar);

        assertTrue(factory.isBasketModeEnabled(true));

        uint256 numAssets = factory.numRegisteredAssets();
        {
            uint256[] memory weights = factory.getWeights();

            for (uint256 i = 0; i < numAssets; i++) {
                assertEq(weights[i], initialWeightRatio);
            }
        }

        // Pause the dummy vault
        vm.prank(pauser);
        factory.pauseVault(address(dummy));

        // Get previews minted honeys and the amount required of each asset required to mint.
        uint256[] memory amounts = factoryReader.previewMintCollaterals(address(dummy), honeyToMintBM);

        // Assert that the required amount of Dummy is zero:
        for (uint256 i = 0; i < numAssets; i++) {
            address asset = factory.registeredAssets(i);
            if (asset == address(dummy)) {
                assertEq(amounts[i], 0);
                break;
            }
        }

        // User don't adjust the dummy value passing a value greater than zero
        // Mint should fail because dummy has weight zero.
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.ZeroWeight.selector, address(dummy)));
        factory.mint(address(dummy), honeyToMintBM, receiver, true);

        {
            for (uint256 i = 0; i < numAssets; i++) {
                address asset = factory.registeredAssets(i);
                if (asset == address(dummy)) {
                    continue;
                }
                // Check expected amount of tokens used to mint:
                if (asset == address(usdt)) {
                    usdtToUseForMint = amounts[i];
                    assertEq(amounts[i], 25e6 * 1e18 / factory.mintRates(asset));
                } else {
                    // Assert Dai amount
                    assertEq(amounts[i], 25e18 * 1e18 / factory.mintRates(asset));
                }

                uint256 balance = ERC20(asset).balanceOf(address(this));
                if (balance < amounts[i]) {
                    MockAsset(asset).mint(address(this), amounts[i] - balance);
                }
                ERC20(asset).approve(address(factory), amounts[i]);
            }
        }

        {
            // Mint in basket mode:
            uint256 mintedHoneys = factory.mint(address(usdt), usdtToUseForMint, receiver, true);

            uint256 daiShares = daiVault.balanceOf(address(factory));
            uint256 usdtShares = usdtVault.balanceOf(address(factory));
            uint256 dummyShares = dummyVault.balanceOf(address(factory));

            // Assumption: 100% of fees goes to the PoL fee collector:
            assertEq((daiToMint * daiMintRate / 1e18) + (mintedHoneys / 2), daiShares);
            assertEq((usdtToMint * usdtMintRate / 1e18) * 1e12 + (mintedHoneys / 2), usdtShares);
            assertEq((dummyToMint * dummyMintRate / 1e18) / 1e2, dummyShares);
        }

        {
            uint256[] memory weights = factory.getWeights();
            for (uint256 i = 0; i < numAssets; i++) {
                if (factory.registeredAssets(i) == address(dummy)) {
                    assertLt(weights[i], initialWeightRatio);
                } else {
                    assertGt(weights[i], initialWeightRatio);
                }
            }
        }
    }

    function testFuzz_redeem_failsWithUnregisteredAsset(uint128 _honeyAmount) external {
        MockUSDT usdtNew = new MockUSDT(); // new unregistered usdt token instance
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssetNotRegistered.selector, address(usdtNew)));
        factory.redeem(address(usdtNew), _honeyAmount, receiver, false);
    }

    function testFuzz_redeem_failWithPausedFactory(uint128 _honeyAmount) external {
        vm.prank(pauser);
        factory.pause();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        factory.redeem(address(dai), _honeyAmount, receiver, false);
    }

    function testFuzz_redeem_failsWithInsufficientHoneys(uint256 _honeyAmount) external {
        _honeyAmount = _bound(_honeyAmount, 1, type(uint128).max);
        vm.expectRevert(ERC20.InsufficientBalance.selector);
        factory.redeem(address(dai), _honeyAmount, receiver, false);
    }

    function testFuzz_redeem_failsWithInsufficientShares(uint256 _daiToMint) external {
        _daiToMint = _bound(_daiToMint, 100, daiBalance);
        uint256 mintedHoneys = _initialMintToAParticularReceiver(_daiToMint, address(this));
        vm.prank(address(factory));
        // vaultAdmin mints honey to this address without increasing shares
        honey.mint(address(this), mintedHoneys);
        vm.expectRevert(ERC4626.RedeemMoreThanMax.selector);
        factory.redeem(address(dai), (mintedHoneys * 3) / 2, address(this), false);
    }

    function testFuzz_redeem(uint256 _honeyToRedeem) external {
        uint256 daiToMint = 100e18;
        uint256 mintedHoneys = _factoryMint(dai, daiToMint, receiver, false);

        _honeyToRedeem = _bound(_honeyToRedeem, 0, mintedHoneys);
        uint256 redeemedDai = (_honeyToRedeem * daiRedeemRate) / 1e18;
        uint256[] memory obtaineableCollaterals = factoryReader.previewRedeemCollaterals(address(dai), _honeyToRedeem);
        (uint256 daiIndex,) = _getIndexOfAsset(address(dai));
        assertEq(obtaineableCollaterals[daiIndex], redeemedDai);

        vm.prank(receiver);
        factory.redeem(address(dai), _honeyToRedeem, address(this), false);
        // minted shares and daiToMint are equal as both have same decimals i.e 1e18
        _verifyOutputOfRedeem(dai, daiVault, daiBalance, daiToMint, mintedHoneys, redeemedDai, _honeyToRedeem, 0);
    }

    function testFuzz_redeemWithLowerDecimalAsset(uint256 _honeyToRedeem) external {
        uint256 usdtToMint = 10e6; // 10 UST
        uint256 honeyOverUsdtRate = 1e12;
        uint256 mintedShares = usdtToMint * honeyOverUsdtRate;
        // upper limit is equal to minted honeys
        _honeyToRedeem = _bound(_honeyToRedeem, 0, (mintedShares * usdtMintRate) / 1e18);

        uint256 mintedHoneyForDai = _provideReferenceCollateral(usdtToMint * honeyOverUsdtRate);
        uint256 mintedHoneyForUsdt = _factoryMint(usdt, usdtToMint, receiver, false);

        uint256 redeemedUsdt = (_honeyToRedeem * usdtRedeemRate) / 1e18 / honeyOverUsdtRate;

        uint256[] memory obtaineableCollaterals = factoryReader.previewRedeemCollaterals(address(usdt), _honeyToRedeem);
        (uint256 usdtIndex,) = _getIndexOfAsset(address(usdt));
        assertEq(obtaineableCollaterals[usdtIndex], redeemedUsdt);

        vm.prank(receiver);
        factory.redeem(address(usdt), _honeyToRedeem, address(this), false);
        _verifyOutputOfRedeem(
            usdt,
            usdtVault,
            usdtBalance,
            usdtToMint,
            mintedHoneyForUsdt,
            redeemedUsdt,
            _honeyToRedeem,
            mintedHoneyForDai
        );
    }

    function testFuzz_redeemWithHigherDecimalAsset(uint256 _honeyToRedeem) external {
        uint256 dummyToMint = 10e20; // 10 dummy
        // 1e20 wei DUMMY ~ 1e18 wei Honey -> 0.9e18 wei Honey
        uint256 dummyOverHoneyRate = 1e2;
        // upper limit is equal to minted honeys
        _honeyToRedeem = _bound(_honeyToRedeem, 0, ((dummyToMint / dummyOverHoneyRate) * dummyMintRate) / 1e18);

        uint256 redeemedDummy = ((_honeyToRedeem * dummyRedeemRate) / 1e18) * dummyOverHoneyRate;
        uint256 mintedHoneyForDai = _provideReferenceCollateral(dummyToMint / dummyOverHoneyRate);
        uint256 mintedHoneyForDummy = _factoryMint(dummy, dummyToMint, receiver, false);

        uint256[] memory obtaineableCollaterals =
            factoryReader.previewRedeemCollaterals(address(dummy), _honeyToRedeem);
        (uint256 dummyIndex,) = _getIndexOfAsset(address(dummy));
        assertEq(obtaineableCollaterals[dummyIndex], redeemedDummy);

        vm.prank(receiver);
        factory.redeem(address(dummy), _honeyToRedeem, address(this), false);

        _verifyOutputOfRedeem(
            dummy,
            dummyVault,
            dummyBalance,
            dummyToMint,
            mintedHoneyForDummy,
            redeemedDummy,
            _honeyToRedeem,
            mintedHoneyForDai
        );
    }

    function testFuzz_redeem_WhenBasketModeIsEnabledAssetWithWeightZero(uint256 honeyToRedeem) external {
        uint256 mintedHoneys = _factoryMint(dai, daiBalance, address(this), false);
        honeyToRedeem = _bound(honeyToRedeem, 1e18, mintedHoneys);
        assertEq(dai.balanceOf(address(this)), 0);
        uint256 daiSharesPre = daiBalance * daiMintRate / 1e18;
        assertEq(daiVault.balanceOf(address(factory)), daiSharesPre);

        _forceBasketMode();
        // There is no usdt deposited into the factory
        // The weight of USDT is zero
        assertEq(usdtVault.balanceOf(address(factory)), 0);
        assertEq(usdt.balanceOf(address(this)), usdtBalance);
        uint256[] memory weights = factory.getWeights();
        assertEq(weights[0], 1e18);
        assertEq(weights[1], 0);

        factory.redeem(address(usdt), honeyToRedeem, address(this), true);

        assertEq(dai.balanceOf(address(this)), honeyToRedeem * daiRedeemRate / 1e18);
        assertEq(usdt.balanceOf(address(this)), usdtBalance);
        _assertEqVaultBalance(address(dai), daiSharesPre - honeyToRedeem);
    }

    function testFuzz_redeem_WhenBasketModeIsEnabled(
        uint256 daiToMint,
        uint256 usdtToMint,
        uint256 dummyToMint,
        uint256 honeyToRedeem,
        uint256 assetToUse
    )
        external
    {
        daiToMint = _bound(daiToMint, 1e12, daiBalance);
        usdtToMint = _bound(usdtToMint, 0.000001e6, daiToMint / 1e12);
        dummyToMint =
            _bound(dummyToMint, 0.00000001e20, daiToMint * 1e2 > dummyBalance ? dummyBalance : daiToMint * 1e2);

        uint256 mintedHoneysForDai = _factoryMint(dai, daiToMint, address(this), false);
        uint256 mintedHoneysForUsdt = _factoryMint(usdt, usdtToMint, address(this), false);
        uint256 mintedHoneysForDummy = _factoryMint(dummy, dummyToMint, address(this), false);
        uint256 totalHoney = mintedHoneysForDai + mintedHoneysForUsdt + mintedHoneysForDummy;
        // Establish the invariants properties and for each one define a test.
        honeyToRedeem = _bound(honeyToRedeem, 1, totalHoney - 1e11);
        uint256 index = _bound(assetToUse, 0, 2);
        address asset = factory.registeredAssets(index);

        _forceBasketMode();

        uint256[] memory weightsPre = factory.getWeights();

        uint256[] memory redemedAmount = factory.redeem(asset, honeyToRedeem, address(this), true);

        {
            assertEq(dai.balanceOf(address(this)), daiBalance - daiToMint + redemedAmount[0]);
            assertEq(usdt.balanceOf(address(this)), usdtBalance - usdtToMint + redemedAmount[1]);
            assertEq(dummy.balanceOf(address(this)), dummyBalance - dummyToMint + redemedAmount[2]);
        }

        uint256[] memory weightsPost = factory.getWeights();
        for (uint256 i = 0; i < weightsPre.length; i++) {
            if (totalHoney == honeyToRedeem) {
                assertEq(weightsPost[i], 0);
            } else {
                assertApproxEqAbs(weightsPost[i], weightsPre[i], 0.001e18); // 0.001%
            }
        }
    }

    function test_redeem_failsWhenVaultIsPaused() external {
        _factoryMint(dai, 100e18, address(this), false);
        vm.prank(pauser);
        factory.pauseVault(address(dai));

        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.VaultPaused.selector, address(dai)));
        factory.redeem(address(dai), 50e18, receiver, false);
    }

    function test_redeem_WhenBasketModeIsEnabledAndAVaultIsPaused() public {
        // Mint honey with a ratio of 33/33/33.
        uint256 initialDaiToMint = 100e18;
        uint256 initialUsdtToMint = 100e6;
        uint256 initialDummyToMint = 100e20;

        _factoryMint(dai, initialDaiToMint, address(this), false);
        _factoryMint(usdt, initialUsdtToMint, address(this), false);
        _factoryMint(dummy, initialDummyToMint, address(this), false);

        _depegFeed(dummyFeed, PEG_OFFSET + 1e10, DepegDirection.UnderOneDollar);

        assertTrue(factory.isBasketModeEnabled(false));

        vm.prank(pauser);
        factory.pauseVault(address(dummy));

        uint256 numAsset = factory.numRegisteredAssets();

        uint256 honeyToRedeem = 50e18;

        uint256[] memory redeemPreviewedAmounts = new uint256[](numAsset);
        // know it is in basket mode, so asset is ignored
        redeemPreviewedAmounts = factoryReader.previewRedeemCollaterals(address(0), honeyToRedeem);

        {
            for (uint256 i = 0; i < numAsset; i++) {
                address asset = factory.registeredAssets(i);
                if (asset == address(dummy)) {
                    assertEq(redeemPreviewedAmounts[i], 0);
                    continue;
                }
                uint256 redeemRate = factory.redeemRates(asset);
                uint256 decimals = MockAsset(asset).decimals();
                uint256 assetAmount = ((honeyToRedeem / 2) * redeemRate) / 1e18 / 10 ** (18 - decimals);
                assertEq(redeemPreviewedAmounts[i], assetAmount);
            }

            uint256 currentDaiBalance = MockAsset(dai).balanceOf(address(this));
            uint256 currentUsdtBalance = MockAsset(usdt).balanceOf(address(this));
            uint256 currentDummyBalance = MockAsset(dummy).balanceOf(address(this));

            assertEq(currentDaiBalance, daiBalance - initialDaiToMint);
            assertEq(currentUsdtBalance, usdtBalance - initialUsdtToMint);
            assertEq(currentDummyBalance, dummyBalance - initialDummyToMint);
        }

        uint256[] memory redemedAmounts = factory.redeem(address(dummy), honeyToRedeem, address(this), true);

        {
            for (uint256 i = 0; i < numAsset; i++) {
                assertEq(redemedAmounts[i], redeemPreviewedAmounts[i]);
            }
        }

        {
            uint256 i = 0;
            uint256 currentDaiBalance = MockAsset(dai).balanceOf(address(this));
            uint256 currentUsdtBalance = MockAsset(usdt).balanceOf(address(this));
            uint256 currentDummyBalance = MockAsset(dummy).balanceOf(address(this));

            assertEq(currentDaiBalance, daiBalance - initialDaiToMint + redemedAmounts[i++]);
            assertEq(currentUsdtBalance, usdtBalance - initialUsdtToMint + redemedAmounts[i++]);
            assertEq(currentDummyBalance, dummyBalance - initialDummyToMint + redemedAmounts[i++]);
        }
    }

    function test_exceedsRelativeCapWhenRedeemOfAPausedVaultMoveWeightsUponThePausedCollateral() external {
        test_redeem_WhenBasketModeIsEnabledAndAVaultIsPaused();

        pyth.setData(dummyFeed, 1e8, uint64(31_155), int32(-8), block.timestamp);

        vm.prank(manager);
        factory.unpauseVault(address(dummy));

        assertFalse(factory.isBasketModeEnabled(false));
        dummy.mint(address(this), 1e20);
        dummy.approve(address(factory), 1e20);

        // It should revert due to RelativeCap because the amount stored on the dummy collateral vault
        // is greather than the ones of the reference collateral.
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.ExceedRelativeCap.selector));
        factory.mint(address(dummy), 1e20, address(this), false);

        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.ExceedRelativeCap.selector));
        factory.redeem(address(dai), 1e18, address(this), false);

        vm.startPrank(manager);
        // Increase relativeCap threshold to 200%
        factory.setRelativeCap(address(dummy), 2e18);
        factory.setRelativeCap(address(usdt), 2e18);
        vm.stopPrank();

        factory.mint(address(dummy), 1e20, address(this), false);

        factory.redeem(address(dai), 1e18, address(this), false);
    }

    function test_liquidate_failsIfLiquidationIsNotEnabled() external {
        vm.prank(governance);
        factory.setLiquidationEnabled(false);

        vm.expectRevert(IHoneyErrors.LiquidationDisabled.selector);
        factory.liquidate(address(dai), address(usdt), 100e18);
    }

    function test_liquidate_failsWhenBadCollateralIsNotRegistered() external {
        MockUSDT usdtNew = new MockUSDT(); // new unregistered usdt token instance
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssetNotRegistered.selector, address(usdtNew)));
        factory.liquidate(address(usdtNew), address(dai), 100e18);
    }

    function test_liquidate_failsWhenBadCollateralIsNotRegisteredAsBadCollateral() external {
        vm.prank(governance);
        factory.setLiquidationEnabled(true);

        // new unregistered usdt token instance
        vm.expectRevert(IHoneyErrors.AssetIsNotBadCollateral.selector);
        factory.liquidate(address(usdt), address(dai), 100e18);
    }

    function test_liquidate_failsIfGoodCollateralIsNotRegistered() external {
        MockUSDT usdtNew = new MockUSDT(); // new unregistered usdt token instance
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssetNotRegistered.selector, address(usdtNew)));
        factory.liquidate(address(usdt), address(usdtNew), 100e18);
    }

    function test_liquidate_failsIfGoodCollateralIsBadCollateral() external {
        vm.prank(manager);
        factory.setCollateralAssetStatus(address(usdt), true);

        // new unregistered usdt token instance
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssetIsBadCollateral.selector, address(usdt)));
        factory.liquidate(address(dai), address(usdt), 100e18);
    }

    function test_liquidate_failsIfReferenceCollateralIsBadCollateral() external {
        vm.prank(governance);
        factory.setLiquidationEnabled(true);

        vm.prank(manager);
        factory.setCollateralAssetStatus(address(dai), true);

        vm.expectRevert(IHoneyErrors.LiquidationWithReferenceCollateral.selector);
        factory.liquidate(address(dai), address(usdt), 100e18);
    }

    function test_liquidate_failsWithNoAllowance() external {
        vm.prank(governance);
        factory.setLiquidationEnabled(true);

        uint256 daiToProvide = 100e18;
        dai.approve(address(factory), daiToProvide - 1);

        vm.prank(manager);
        factory.setCollateralAssetStatus(address(usdt), true);

        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        factory.liquidate(address(usdt), address(dai), daiToProvide);
    }

    function test_liquidate_WhenThereIsNoSufficientBadCollateral() public {
        vm.prank(governance);
        factory.setLiquidationEnabled(true);

        uint256 daiToMint = 100e18;
        _factoryMint(dai, daiToMint, receiver, false);
        uint256 usdtToMint = 50e6;
        _factoryMint(usdt, usdtToMint, receiver, false);

        // LiquidationRate is zero and the price of the two assets is the same
        uint256 daiToProvide = 100e18;
        dai.approve(address(factory), daiToProvide);

        vm.prank(manager);
        factory.setCollateralAssetStatus(address(usdt), true);

        assertEq(dai.balanceOf(address(this)), daiBalance - daiToMint);
        assertEq(usdt.balanceOf(address(this)), usdtBalance - usdtToMint);

        _assertEqVaultBalance(address(dai), daiToMint * daiMintRate / 1e18);
        _assertEqVaultBalance(address(usdt), usdtToMint * usdtMintRate / 1e18);

        uint256 usdtToObtain = 50e6 * usdtMintRate / 1e18;
        uint256 daiToBeTaken = 50e18 * daiMintRate / 1e18;

        uint256 usdtObtained = factory.liquidate(address(usdt), address(dai), daiToProvide);

        assertEq(usdtObtained, usdtToObtain);
        assertEq(dai.balanceOf(address(this)), daiBalance - daiToMint - daiToBeTaken);
        assertEq(usdt.balanceOf(address(this)), usdtBalance - usdtToMint + usdtToObtain);

        _assertEqVaultBalance(address(usdt), (usdtToMint * usdtMintRate / 1e18) - usdtToObtain);
        _assertEqVaultBalance(address(dai), (daiToMint * daiMintRate / 1e18) + daiToBeTaken);
    }

    function testFuzz_liquidate_failsWhenGoodAmountIsSoSmallToRoundBadAmountToZero(
        uint256 daiToMint,
        uint256 usdtToMint,
        uint256 pegOffset,
        uint256 liquidationRate,
        uint256 daiToProvide
    )
        external
    {
        uint256 maxRoundingErrorDecimal = dai.decimals() - usdt.decimals() - 2;

        vm.prank(governance);
        factory.setLiquidationEnabled(true);

        daiToMint = _bound(daiToMint, 1e18, type(uint128).max);
        _initialMint(daiToMint);
        daiToProvide = _bound(daiToProvide, 1, 10 ** maxRoundingErrorDecimal);
        dai.mint(address(this), daiToProvide);
        daiBalance = daiBalance + daiToMint;
        assertEq(dai.balanceOf(address(this)), daiBalance - daiToMint + daiToProvide);

        usdtToMint = _bound(usdtToMint, 1e6, daiToMint / 10 ** 12);
        usdt.mint(address(this), usdtToMint);
        _factoryMint(usdt, usdtToMint, receiver, false);
        usdtBalance = usdtBalance + usdtToMint;
        assertEq(usdt.balanceOf(address(this)), usdtBalance - usdtToMint);

        // Depeg the usdt asset
        pegOffset = _bound(pegOffset, PEG_OFFSET + 0.1e18, 1e18 - 0.1e18);
        _depegFeed(usdtFeed, pegOffset, DepegDirection.UnderOneDollar);

        vm.prank(manager);
        factory.setCollateralAssetStatus(address(usdt), true);

        liquidationRate = _bound(liquidationRate, 0, 0.5e18);
        vm.prank(governance);
        factory.setLiquidationRate(address(usdt), liquidationRate);

        {
            uint256 daiFeesToPoL = dai.balanceOf(polFeeCollector);
            _assertEqVaultBalance(address(dai), daiToMint - daiFeesToPoL);

            uint256 usdtFeesToPoL = usdt.balanceOf(polFeeCollector);
            _assertEqVaultBalance(address(usdt), usdtToMint - usdtFeesToPoL);
        }

        dai.approve(address(factory), daiToProvide);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.ZeroAmount.selector));
        factory.liquidate(address(usdt), address(dai), daiToProvide);
    }

    function testFuzz_liquidate_WhenBadCollateralDepeg(
        uint256 daiToMint,
        uint256 usdtToMint,
        uint256 pegOffset,
        uint256 liquidationRate,
        uint256 daiToProvide,
        bool depegOver
    )
        public
    {
        vm.prank(governance);
        factory.setLiquidationEnabled(true);
        // Mint and deposit DAI:
        daiToMint = _bound(daiToMint, 1e18, type(uint128).max);
        _initialMint(daiToMint);
        daiBalance = daiBalance + daiToMint;
        // Mint DAI used for liquidation:
        daiToProvide = _bound(daiToProvide, 1e18, type(uint128).max);
        dai.mint(address(this), daiToProvide);
        uint256 daiBalancePre = daiBalance - daiToMint + daiToProvide;
        assertEq(dai.balanceOf(address(this)), daiBalancePre);

        // Mint and deposit USDT:
        usdtToMint = _bound(usdtToMint, 1e6, daiToMint / 10 ** 12);
        usdt.mint(address(this), usdtToMint);
        _factoryMint(usdt, usdtToMint, receiver, false);
        usdtBalance = usdtBalance + usdtToMint;
        uint256 usdtBalancePre = usdtBalance - usdtToMint;
        assertEq(usdt.balanceOf(address(this)), usdtBalancePre);

        // Check factory pre-conditions:
        {
            uint256 daiFeesToPoL = dai.balanceOf(polFeeCollector);
            _assertEqVaultBalance(address(dai), daiToMint - daiFeesToPoL);

            uint256 usdtFeesToPoL = usdt.balanceOf(polFeeCollector);
            _assertEqVaultBalance(address(usdt), usdtToMint - usdtFeesToPoL);
        }

        // Depeg the USDT asset:
        pegOffset = _bound(pegOffset, PEG_OFFSET + 0.1e18, 1e18 - 0.1e18);
        DepegDirection direction = (depegOver) ? DepegDirection.OverOneDollar : DepegDirection.UnderOneDollar;
        _depegFeed(usdtFeed, pegOffset, direction);
        vm.prank(manager);
        factory.setCollateralAssetStatus(address(usdt), true);

        // Set liquidation rate:
        liquidationRate = _bound(liquidationRate, 0, 0.5e18);
        vm.prank(governance);
        factory.setLiquidationRate(address(usdt), liquidationRate);

        // Estimated I/O:
        uint256 usdtToObtain = 0;
        uint256 daiEffectiveUsed = daiToProvide;
        {
            uint256 usdtPrice = oracle.getPrice(address(usdt)).price;
            uint256 daiPrice = oracle.getPrice(address(dai)).price;
            usdtToObtain = (daiToProvide * daiPrice / usdtPrice) * (1e18 + liquidationRate) / 1e18;
            uint256 usdtSharesAvailable = usdtVault.balanceOf(address(factory));
            if (usdtToObtain > usdtSharesAvailable) {
                daiEffectiveUsed = (usdtSharesAvailable * usdtPrice / daiPrice) * 1e18 / (1e18 + liquidationRate);
                usdtToObtain = usdtSharesAvailable / 1e12;
            } else {
                usdtToObtain = usdtToObtain / 1e12;
            }
        }

        // Liquidate:
        dai.approve(address(factory), daiToProvide);
        factory.liquidate(address(usdt), address(dai), daiToProvide);

        // Check post-conditions:
        {
            assertFalse(daiEffectiveUsed == 0 && usdtToObtain > 0);
            assertApproxEqAbs(dai.balanceOf(address(this)), daiBalancePre - daiEffectiveUsed, 1e2);
            assertEq(usdt.balanceOf(address(this)), usdtBalancePre + usdtToObtain);

            uint256 daiFeesToPoL = dai.balanceOf(polFeeCollector);
            _assertEqVaultBalance(address(dai), daiToMint + daiEffectiveUsed - daiFeesToPoL);

            uint256 usdtFeesToPoL = usdt.balanceOf(polFeeCollector);
            _assertEqVaultBalance(address(usdt), usdtToMint - usdtFeesToPoL - usdtToObtain);
        }
    }

    function testFuzz_liquidate_failsWhenExceedsRelativeCap(
        uint256 daiToMint,
        uint256 dummyToMint,
        uint256 usdtToProvide
    )
        external
    {
        vm.prank(governance);
        factory.setLiquidationEnabled(true);

        daiToMint = _bound(daiToMint, 1e18, daiBalance);
        uint256 usdtToMint = daiToMint / 10 ** 12;
        dummyToMint = _bound(dummyToMint, 1e20, dummyBalance > daiToMint * 1e2 ? daiToMint * 1e2 : dummyBalance);
        usdtToProvide = _bound(usdtToProvide, 0.1e6, usdtBalance - usdtToMint);

        _factoryMint(dai, daiToMint, address(this), false);
        _factoryMint(usdt, usdtToMint, address(this), false);
        _factoryMint(dummy, dummyToMint, address(this), false);

        vm.prank(manager);
        factory.setCollateralAssetStatus(address(dummy), true);

        usdt.approve(address(factory), usdtToProvide);
        vm.expectRevert(IHoneyErrors.ExceedRelativeCap.selector);
        factory.liquidate(address(dummy), address(usdt), usdtToProvide);
    }

    function test_recapitalize_failsIfAssetIsNotRegistered() external {
        MockUSDT usdtNew = new MockUSDT(); // new unregistered usdt token instance
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssetNotRegistered.selector, address(usdtNew)));
        factory.recapitalize(address(usdtNew), 100e6);
    }

    function test_recapitalize_failsIfBadAsset() external {
        vm.prank(manager);
        factory.setCollateralAssetStatus(address(usdt), true);

        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssetIsBadCollateral.selector, address(usdt)));
        factory.recapitalize(address(usdt), 100e6);
    }

    function test_recapitalize_failsForInsufficientAllowance() external {
        _initialMint(100e18);

        vm.prank(governance);
        factory.setRecapitalizeBalanceThreshold(address(dai), 200e18);

        dai.approve(address(factory), 99e18);
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        factory.recapitalize(address(dai), 100e18);
    }

    function testFuzz_recapitalize_failsWhenExceedsGlobalCap(uint256 usdtToMint) external {
        uint256 daiToMint = 100e18;
        usdtToMint = _bound(usdtToMint, 1e6, 98e6);

        _provideReferenceCollateral(daiToMint);
        _factoryMint(usdt, usdtToMint, receiver, false);

        assertEq(daiVault.balanceOf(address(factory)), daiToMint * daiMintRate / 1e18);
        assertEq(usdtVault.balanceOf(address(factory)), usdtToMint * 10 ** 12 * usdtMintRate / 1e18);

        vm.prank(governance);
        factory.setRecapitalizeBalanceThreshold(address(dai), 101e18);

        uint256 daiWeight = daiToMint * 1e18 / (daiToMint + usdtVault.convertToShares(usdtToMint));
        vm.prank(manager);
        factory.setGlobalCap(daiWeight);

        dai.approve(address(factory), 1e18);
        vm.expectRevert(IHoneyErrors.ExceedGlobalCap.selector);
        factory.recapitalize(address(dai), 1e18);
    }

    function testFuzz_recapitalize_failsWhenExceedRelativeCap(
        uint256 daiToMint,
        uint256 usdtToRecapitalize
    )
        external
    {
        daiToMint = _bound(daiToMint, 1e18, daiBalance);
        uint256 usdtToMint = daiToMint / 10 ** 12;
        usdtToRecapitalize = _bound(usdtToRecapitalize, 1e6, usdtBalance - usdtToMint);

        _factoryMint(dai, daiToMint, address(this), false);
        _factoryMint(usdt, usdtToMint, address(this), false);

        vm.prank(governance);
        factory.setRecapitalizeBalanceThreshold(address(usdt), usdtToMint + usdtToRecapitalize);

        usdt.approve(address(factory), usdtToRecapitalize);
        vm.expectRevert(IHoneyErrors.ExceedRelativeCap.selector);
        factory.recapitalize(address(usdt), usdtToRecapitalize);
    }

    function testFuzz_recapitalize_failsWhenTargetBalanceIsNotSet(uint256 usdtToRecapitalize) external {
        uint256 MINIMUM_RECAPITALIZE_SHARES = factory.minSharesToRecapitalize();
        usdtToRecapitalize = _bound(usdtToRecapitalize, MINIMUM_RECAPITALIZE_SHARES / 1e12, type(uint160).max);
        usdt.approve(address(factory), usdtToRecapitalize);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.RecapitalizeNotNeeded.selector, address(usdt)));
        factory.recapitalize(address(usdt), usdtToRecapitalize);
    }

    function testFuzz_recapitalize_failsWhenUserProvideAmountLessThanTheMinimumAllowed(uint256 usdtToRecapitalize)
        external
    {
        uint256 MINIMUM_RECAPITALIZE_SHARES = factory.minSharesToRecapitalize();
        usdtToRecapitalize = _bound(usdtToRecapitalize, 0, MINIMUM_RECAPITALIZE_SHARES / 1e12 - 1);

        // Require recapitalization:
        assertEq(usdtVault.balanceOf(address(factory)), 0);
        vm.prank(governance);
        factory.setRecapitalizeBalanceThreshold(address(usdt), MINIMUM_RECAPITALIZE_SHARES / 1e12);
        assertGt(factory.recapitalizeBalanceThreshold(address(usdt)), 0);

        // Recapitalize:
        usdt.approve(address(factory), usdtToRecapitalize);
        vm.expectRevert(
            abi.encodeWithSelector(IHoneyErrors.InsufficientRecapitalizeAmount.selector, usdtToRecapitalize)
        );
        factory.recapitalize(address(usdt), usdtToRecapitalize);
    }

    function testFuzz_recapitalize(uint256 daiToMint, uint256 daiToRecapitalize) external {
        daiToMint = _bound(daiToMint, 1e18, daiBalance);
        // Min shares to recapitalize is 1e18, which is exactly 1 dai token (18 decimals)
        daiToRecapitalize = _bound(daiToRecapitalize, factory.minSharesToRecapitalize(), type(uint128).max);

        dai.mint(address(this), daiToRecapitalize);

        uint256 mintedHoneysForDai = _factoryMint(dai, daiToMint, receiver, false);
        assertEq(honey.balanceOf(address(receiver)), mintedHoneysForDai);

        vm.prank(governance);
        factory.setRecapitalizeBalanceThreshold(address(dai), daiToMint + daiToRecapitalize);

        dai.approve(address(factory), daiToRecapitalize);
        factory.recapitalize(address(dai), daiToRecapitalize);
        assertEq(daiVault.balanceOf(address(factory)), mintedHoneysForDai + daiToRecapitalize);
        assertEq(honey.balanceOf(address(receiver)), mintedHoneysForDai);
        assertEq(dai.balanceOf(address(this)), daiBalance - daiToMint);
    }

    function test_redeem() public {
        uint256 daiToMint = 100e18;
        uint256 usdtToMint = 100e6;
        uint256 mintedHoneysForDai = _factoryMint(dai, daiToMint, address(this), false);

        uint256 mintedHoneysForUsdt = _factoryMint(usdt, usdtToMint, address(this), false);
        uint256 redeemedUsdt = (mintedHoneysForUsdt * usdtRedeemRate) / 1e30;
        uint256[] memory obtaineableCollaterals =
            factoryReader.previewRedeemCollaterals(address(usdt), mintedHoneysForUsdt);
        (uint256 usdtIndex,) = _getIndexOfAsset(address(usdt));
        assertEq(obtaineableCollaterals[usdtIndex], redeemedUsdt);
        assertEq(honey.balanceOf(address(this)), mintedHoneysForDai + mintedHoneysForUsdt);
        assertEq(usdt.balanceOf(address(this)), usdtBalance - usdtToMint);

        vm.prank(address(this));
        vm.expectEmit();
        emit IHoneyFactory.HoneyRedeemed(
            address(this), address(this), address(usdt), redeemedUsdt / 1, mintedHoneysForUsdt
        );
        factory.redeem(address(usdt), mintedHoneysForUsdt, address(this), false);

        assertEq(usdt.balanceOf(address(this)), usdtBalance - usdtToMint + redeemedUsdt);
        assertEq(honey.balanceOf(address(this)), mintedHoneysForDai);
    }

    function test_redeem_failsWhenReferenceCollateralIsRedeemedAndExceedsRelativeCapOnOtherAssets() public {
        // Mint the same quantity of shares for all assets
        uint256 daiToMint = 100e18;
        uint256 usdtToMint = 100e6;
        uint256 dummyToMint = 100e20;

        _factoryMint(dai, daiToMint, address(this), false);
        _factoryMint(usdt, usdtToMint, address(this), false);
        _factoryMint(dummy, dummyToMint, address(this), false);

        // Actually the basket mode is disabled, so the caps are checked.
        assertFalse(factory.isBasketModeEnabled(false));

        // The relative cap is exceeded
        vm.expectRevert(IHoneyErrors.ExceedRelativeCap.selector);
        factory.redeem(address(dai), 2e18, address(this), false);
    }

    function test_redeem_failsWhenExceedsGlobalCap() external {
        uint256 daiToMint = 100e18;
        uint256 usdtToMint = 100e6;
        uint256 dummyToMint = 100e20;

        _factoryMint(dai, daiToMint, address(this), false);
        _factoryMint(usdt, usdtToMint, address(this), false);
        _factoryMint(dummy, dummyToMint, address(this), false);

        // now weights are 1/3
        assertEq(factory.getWeights()[0], uint256(1e18) / 3);

        vm.prank(manager);
        factory.setGlobalCap(0.45e18);

        // Remove a collateral in order to move the weights of an asset greater than 0.45

        uint256 honeyToRedeem = 80e18;

        vm.expectRevert(IHoneyErrors.ExceedGlobalCap.selector);
        factory.redeem(address(usdt), honeyToRedeem, address(this), false);
    }

    function test_setFeeReceiver_failsWithoutAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), DEFAULT_ADMIN_ROLE
            )
        );
        factory.setFeeReceiver(receiver);
    }

    function test_setFeeReceiver_failsWithZeroAddress() external {
        vm.prank(governance);
        vm.expectRevert(IHoneyErrors.ZeroAddress.selector);
        factory.setFeeReceiver(address(0));
    }

    function test_setFeeReceiver() external {
        address newReceiver = makeAddr("newReceiver");
        testFuzz_setFeeReceiver(newReceiver);
    }

    function testFuzz_setFeeReceiver(address _receiver) public {
        vm.assume(_receiver != address(0));
        vm.expectEmit();
        emit VaultAdmin.FeeReceiverSet(_receiver);
        vm.prank(governance);
        factory.setFeeReceiver(_receiver);
        assertEq(factory.feeReceiver(), _receiver);
    }

    function test_setPOLFeeCollector_failsWithoutAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), DEFAULT_ADMIN_ROLE
            )
        );
        factory.setPOLFeeCollector(polFeeCollector);
    }

    function test_setPOLFeeCollector_failsWithZeroAddress() external {
        vm.prank(governance);
        vm.expectRevert(IHoneyErrors.ZeroAddress.selector);
        factory.setPOLFeeCollector(address(0));
    }

    function test_setPOLFeeCollector() external {
        address newPOLFeeCollector = makeAddr("newPOLFeeCollector");
        testFuzz_setPOLFeeCollector(newPOLFeeCollector);
    }

    function testFuzz_setPOLFeeCollector(address _polFeeCollector) public {
        vm.assume(_polFeeCollector != address(0));
        vm.expectEmit();
        emit VaultAdmin.POLFeeCollectorSet(_polFeeCollector);
        vm.prank(governance);
        factory.setPOLFeeCollector(_polFeeCollector);
        assertEq(factory.polFeeCollector(), _polFeeCollector);
    }

    function test_setCollateralAssetStatus_failsWithoutManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), MANAGER_ROLE
            )
        );
        factory.setCollateralAssetStatus(address(dai), true);
    }

    function test_setCollateralAssetStatus_failsWithUnregisteredAsset() external {
        MockUSDT usdtNew = new MockUSDT(); // new unregistered usdt token instance
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssetNotRegistered.selector, address(usdtNew)));
        factory.setCollateralAssetStatus(address(usdtNew), true);
    }

    function test_setCollateralAssetStatus() public {
        vm.prank(manager);
        vm.expectEmit();
        emit VaultAdmin.CollateralAssetStatusSet(address(dai), true);
        factory.setCollateralAssetStatus(address(dai), true);
        assertEq(factory.isBadCollateralAsset(address(dai)), true);
    }

    function testFuzz_withdrawFee_failsWithAssetNotRegistered() external {
        address usdtNew = address(new MockUSDT()); // new unregistered usdt token instance
        vm.prank(feeReceiver);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssetNotRegistered.selector, usdtNew));
        factory.withdrawFee(usdtNew, feeReceiver);
    }

    function test_withdrawFee_WithZeroCollectedFee() external {
        // Should not revert
        assertEq(factory.collectedFees(feeReceiver, address(dai)), 0);
        factory.withdrawFee(address(dai), feeReceiver);
        assertEq(dai.balanceOf(feeReceiver), 0);
    }

    function test_WithdrawFee_TestEvent() external {
        uint256 usdtToMint = 100e6; // 100 USDT

        vm.prank(governance);
        factory.setPOLFeeCollectorFeeRate(0.5e18);

        _provideReferenceCollateral(daiBalance);
        uint256 mintedHoneys = _factoryMint(usdt, usdtToMint, receiver, false);

        uint256 usdtVaultTotalFeeShares = usdtToMint * 10 ** 12 - mintedHoneys;

        uint256 feeReceiverFeeShares = usdtVaultTotalFeeShares * (1e18 - factory.polFeeCollectorFeeRate()) / 1e18;
        assertEq(factory.collectedFees(feeReceiver, address(usdt)), feeReceiverFeeShares);
        uint256 feeReceiverUSDT = feeReceiverFeeShares / 10 ** 12;
        vm.expectEmit();
        emit VaultAdmin.CollectedFeeWithdrawn(address(usdt), feeReceiver, feeReceiverFeeShares, feeReceiverUSDT);
        factory.withdrawFee(address(usdt), feeReceiver);
        assertEq(usdt.balanceOf(feeReceiver), feeReceiverUSDT);
    }

    function testFuzz_withdrawFee(uint256 _daiToMint) public {
        vm.prank(governance);
        factory.setPOLFeeCollectorFeeRate(0.5e18);
        assertEq(factory.polFeeCollectorFeeRate(), 0.5e18);

        assertEq(factory.collectedFees(feeReceiver, address(dai)), 0);
        assertEq(dai.balanceOf(feeReceiver), 0);

        _daiToMint = _bound(_daiToMint, 0, daiBalance);
        uint256 mintedHoneys = _initialMint(_daiToMint);
        uint256 daiTotalFee = _daiToMint - mintedHoneys;
        uint256 polFeeCollectorFee = daiTotalFee * factory.polFeeCollectorFeeRate() / 1e18;
        uint256 receiverFees = daiTotalFee - polFeeCollectorFee;

        assertEq(dai.balanceOf(feeReceiver), 0);
        assertEq(factory.collectedFees(feeReceiver, address(dai)), receiverFees);
        // This will withdraw all dai fee for feeReceiver
        factory.withdrawFee(address(dai), feeReceiver);

        // fee receiver should have the DAI equal to daiFeeToWithdraw in his balance
        assertEq(dai.balanceOf(feeReceiver), receiverFees);
        assertEq(factory.collectedFees(feeReceiver, address(dai)), 0);
    }

    function test_CollectedFees() external {
        testFuzz_CollectedFeesWithDifferentFeeRate(98e16, 100e18);
    }

    function testFuzz_CollectedFeesWithDifferentFeeRate(uint256 _polFeeCollectorFeeRate, uint256 daiToMint) public {
        _polFeeCollectorFeeRate = _bound(_polFeeCollectorFeeRate, 0, 1e18);
        daiToMint = _bound(daiToMint, 0, daiBalance);
        testFuzz_setPOLFeeCollectorFeeRate(_polFeeCollectorFeeRate);
        uint256 polFeesBefore = dai.balanceOf(polFeeCollector);
        uint256 mintedHoneys = _factoryMint(dai, daiToMint, receiver, false);
        // Dai and Honey have both 18 decimals
        uint256 daiTotalFee = daiToMint - mintedHoneys;
        uint256 polFeeCollectorFee = (daiTotalFee * _polFeeCollectorFeeRate) / 1e18;
        uint256 feeReceiverFee = daiTotalFee - polFeeCollectorFee;
        assertEq(factory.collectedFees(feeReceiver, address(dai)), feeReceiverFee);
        uint256 polFeesAfter = dai.balanceOf(polFeeCollector);
        assertEq(polFeesAfter - polFeesBefore, polFeeCollectorFee);
    }

    function testFuzz_withdrawAllFee(uint256 _daiToMint) external {
        _daiToMint = _bound(_daiToMint, 0, daiBalance);
        uint256 mintedHoneys = _initialMint(_daiToMint);
        uint256 daiTotalFee = _daiToMint - mintedHoneys;
        uint256 feeReceiverFee = daiTotalFee * (1e18 - factory.polFeeCollectorFeeRate()) / 1e18;
        assertEq(dai.balanceOf(feeReceiver), 0);
        // There is no need for approval as factory holds the shares of fees.
        factory.withdrawAllFees(feeReceiver);
        assertEq(dai.balanceOf(feeReceiver), feeReceiverFee);
        assertEq(daiVault.balanceOf(feeReceiver), 0);
        assertEq(factory.collectedFees(feeReceiver, address(dai)), 0);
    }

    function test_pauseVault_failsWithoutPauser() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), PAUSER_ROLE
            )
        );
        factory.pauseVault(address(dai));
    }

    function test_pauseVault() external {
        vm.prank(pauser);
        factory.pauseVault(address(dai));
        assertEq(daiVault.paused(), true);
    }

    function test_unpauseVault_failsWithoutManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), MANAGER_ROLE
            )
        );
        factory.unpauseVault(address(dai));
    }

    function test_unpauseVault() external {
        vm.prank(pauser);
        factory.pauseVault(address(dai));
        vm.prank(manager);
        factory.unpauseVault(address(dai));
        assertEq(daiVault.paused(), false);
    }

    function test_factoryPause_failsWithoutPauser() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), PAUSER_ROLE
            )
        );
        factory.pause();
    }

    function test_factoryUnPause_failsWithoutManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), MANAGER_ROLE
            )
        );
        factory.unpause();
    }

    function test_factoryPause_failsWhenAlreadyPaused() external {
        vm.startPrank(pauser);
        factory.pause();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        factory.pause();
        vm.stopPrank();
    }

    function test_factoryUnPause_failsWhenAlreadyUnpaused() external {
        vm.prank(manager);
        vm.expectRevert(PausableUpgradeable.ExpectedPause.selector);
        factory.unpause();
    }

    function test_factoryPause() external {
        vm.prank(pauser);
        factory.pause();
        assertEq(factory.paused(), true);
    }

    function test_factoryUnpause() external {
        vm.prank(pauser);
        factory.pause();
        vm.prank(manager);
        factory.unpause();
        assertEq(factory.paused(), false);
    }

    function test_IntegrationTest() external {
        uint256 daiToMint = 100e18;
        // mint honey with 100 dai
        uint256 honeyToMint = _factoryMint(dai, daiToMint, address(this), false);
        for (uint256 i = 0; i < 10; i++) {
            factory.redeem(address(dai), honeyToMint / 10, address(this), false);
            if (i == 5) {
                // change redeem rate to 1e18
                vm.prank(manager);
                factory.setRedeemRate(address(dai), 98e16);
                // change polFeeCollectorFeeRate to 0
                vm.prank(governance);
                factory.setPOLFeeCollectorFeeRate(0);
            }
        }
        // redeem rest of the honey
        uint256 remainingHoney = honeyToMint - (honeyToMint / 10) * 10;
        factory.redeem(address(dai), remainingHoney, address(this), false);
        // at this point shares should be of fees only
        assertEq(
            daiVault.balanceOf(address(factory)),
            factory.collectedFees(feeReceiver, address(dai)) + factory.collectedFees(polFeeCollector, address(dai))
        );
        factory.withdrawAllFees(feeReceiver);
        factory.withdrawAllFees(polFeeCollector);
        // factory should not have any shares of daiVault left.
        assertEq(daiVault.balanceOf(address(factory)), 0);
    }

    function testFuzz_InflationAttack(uint256 _daiToMint) external {
        _daiToMint = _bound(_daiToMint, 1, (type(uint160).max - daiBalance) / 2);
        address attacker = makeAddr("attacker");
        // Attacker donates DAI to the vault to change the exchange rate.
        dai.mint(attacker, 2 * _daiToMint);
        vm.prank(attacker);
        dai.transfer(address(daiVault), _daiToMint);
        assertEq(dai.balanceOf(address(daiVault)), _daiToMint); // assets
        assertEq(daiVault.totalSupply(), 0); // shares
        // assets/shares exchange rate = 1 when there is no shares in the vault.
        assertEq(daiVault.convertToShares(_daiToMint), _daiToMint);

        vm.startPrank(attacker);
        dai.approve(address(daiVault), _daiToMint);
        // Attacker cannot mint shares, so no inflation attacks happen.
        vm.expectRevert(IHoneyErrors.NotFactory.selector);
        daiVault.deposit(_daiToMint, address(this));
        vm.stopPrank();
        // If inflation attacks happen, the exchange rate will be 0.5.
        assertFalse(dai.balanceOf(address(daiVault)) == 2 * _daiToMint); // assets
        assertFalse(daiVault.totalSupply() == _daiToMint); // shares
        assertFalse(daiVault.convertToShares(_daiToMint) == _daiToMint / 2); // assets/shares exchange rate = 0.5
        // As inflation attacks do not happen, the exchange rate is still 1.
        assertEq(dai.balanceOf(address(daiVault)), _daiToMint); // assets
        assertEq(daiVault.totalSupply(), 0); // shares
        assertEq(daiVault.convertToShares(_daiToMint), _daiToMint); // assets/shares exchange rate = 1

        // Attacker mints Honey with DAI to increase the total supply of shares.
        vm.startPrank(attacker);
        _factoryMint(dai, _daiToMint, address(this), false);
        vm.stopPrank();

        assertEq(dai.balanceOf(address(daiVault)), _daiToMint + _daiToMint * daiMintRate / 1e18); // vault assets
        assertEq(daiVault.totalSupply(), _daiToMint * daiMintRate / 1e18); // shares
        _assertEqVaultBalance(address(dai), _daiToMint * daiMintRate / 1e18);
    }

    // ToDo: Add for Basket Mode Enabled
    function testFuzz_PreviewRequiredCollateral(uint128 _mintedHoneys) external {
        uint256 shareReq = (uint256(_mintedHoneys) * 1e18) / daiMintRate;
        uint256[] memory requiredCollateral = factoryReader.previewMintCollaterals(address(dai), _mintedHoneys);
        assertEq(requiredCollateral[0], shareReq);
    }

    function testFuzz_PreviewRequiredCollateralReturnsAllZeroWhenBasketModeIsEnabledWithoutAnyDeposit(
        uint256 _mintedHoneys
    )
        external
    {
        _forceBasketMode();
        uint256[] memory requiredCollateral = factoryReader.previewMintCollaterals(address(dai), _mintedHoneys);

        for (uint256 i = 0; i < requiredCollateral.length; i++) {
            assertEq(requiredCollateral[i], 0);
        }
    }

    function testFuzz_PreviewRequiredCollateralWhenBasketModeIsEnabled(
        uint256 daiToMint,
        uint256 usdtToMint,
        uint256 dummyToMint,
        uint256 _mintedHoneys
    )
        external
    {
        daiToMint = _bound(daiToMint, 1e18, daiBalance);
        usdtToMint = _bound(usdtToMint, 1e6, daiToMint / 10 ** 12);

        uint256 dummyUpperBound = daiToMint * 1e2 > dummyBalance ? dummyBalance : daiToMint * 1e2;
        dummyToMint = _bound(dummyToMint, 1e20, dummyUpperBound);

        uint256[] memory percentages = new uint256[](3);
        {
            uint256[] memory mintedHoneys = new uint256[](3);
            mintedHoneys[0] = _initialMint(daiToMint);
            mintedHoneys[1] = _factoryMint(usdt, usdtToMint, receiver, false);
            mintedHoneys[2] = _factoryMint(dummy, dummyToMint, receiver, false);

            uint256 totalMintedHoneys = mintedHoneys[0] + mintedHoneys[1] + mintedHoneys[2];

            percentages[0] = mintedHoneys[0] * 1e18 / totalMintedHoneys;
            percentages[1] = mintedHoneys[1] * 1e18 / totalMintedHoneys;
            percentages[2] = mintedHoneys[2] * 1e18 / totalMintedHoneys;
        }

        _forceBasketMode();

        _mintedHoneys = _bound(_mintedHoneys, 0, type(uint128).max);
        uint256[][] memory requiredCollaterals = new uint256[][](3);

        requiredCollaterals[0] = factoryReader.previewMintCollaterals(address(dai), _mintedHoneys);
        requiredCollaterals[1] = factoryReader.previewMintCollaterals(address(usdt), _mintedHoneys);
        requiredCollaterals[2] = factoryReader.previewMintCollaterals(address(dummy), _mintedHoneys);

        for (uint256 i = 0; i < requiredCollaterals.length; i++) {
            uint8 previewAssetDecimals = ERC20(factory.registeredAssets(i)).decimals();
            uint256 previewAssetDeltaToWad =
                previewAssetDecimals > 18 ? previewAssetDecimals - 18 : 18 - previewAssetDecimals;

            for (uint256 j = 0; j < requiredCollaterals[i].length; j++) {
                address collateralAsset = factory.registeredAssets(j);
                uint256 mintRate = factory.mintRates(collateralAsset);
                uint8 collateralAssetDecimals = ERC20(collateralAsset).decimals();

                // Calculate the required collateral amount in the specific asset's units
                uint256 requiredAmount = ((_mintedHoneys * 1e18) / mintRate) * percentages[j] / 1e18;
                requiredAmount = Utils.changeDecimals(requiredAmount, 18, collateralAssetDecimals);

                // Calculate delta tolerance for approximation
                uint256 deltaTolerance = previewAssetDecimals > collateralAssetDecimals
                    ? 10 ** (previewAssetDecimals - collateralAssetDecimals)
                    : (
                        previewAssetDecimals == collateralAssetDecimals
                            ? 10 ** previewAssetDeltaToWad
                            : 10 ** (collateralAssetDecimals - previewAssetDecimals)
                    );

                assertApproxEqAbs(requiredCollaterals[i][j], requiredAmount, deltaTolerance);
            }
        }
    }

    function testFuzz_PreviewHoneyToRedeem(uint64 _redeemedDai) external {
        uint256 redeemedHoneys = (daiVault.previewWithdraw(_redeemedDai) * 1e18) / daiRedeemRate;
        (, uint256 honeyToRedeem) = factoryReader.previewRedeemHoney(address(dai), _redeemedDai);
        assertEq(honeyToRedeem, redeemedHoneys);
    }

    function test_TransferOwnershipOfBeaconFailsIfNotOwner() public {
        address newAddress = makeAddr("newAddress");
        UpgradeableBeacon beacon = UpgradeableBeacon(factory.beacon());
        vm.expectRevert(UpgradeableBeacon.Unauthorized.selector);
        beacon.transferOwnership(newAddress);
    }

    function test_TransferOwnershipOfBeaconFailsIfZeroAddress() public {
        UpgradeableBeacon beacon = UpgradeableBeacon(factory.beacon());
        vm.expectRevert(UpgradeableBeacon.NewOwnerIsZeroAddress.selector);
        vm.prank(governance);
        beacon.transferOwnership(address(0));
    }

    function test_TransferOwnershipOfBeacon() public {
        address newAddress = makeAddr("newAddress");
        UpgradeableBeacon beacon = UpgradeableBeacon(factory.beacon());
        vm.prank(governance);
        beacon.transferOwnership(newAddress);
        assertEq(beacon.owner(), newAddress);
    }

    function test_UpgradeBeaconProxyImplFailsIfNotOwner() public {
        address newImplementation = address(new MockVault());
        UpgradeableBeacon beacon = UpgradeableBeacon(factory.beacon());
        // implementation update of the beacon fails as caller is not the owner.
        vm.expectRevert(UpgradeableBeacon.Unauthorized.selector);
        beacon.upgradeTo(newImplementation);
    }

    function test_UpgradeBeaconProxyToFaultyVault() public {
        address newImplementation = address(new FaultyVault());
        UpgradeableBeacon beacon = UpgradeableBeacon(factory.beacon());
        vm.startPrank(governance);
        beacon.upgradeTo(newImplementation);
        assertEq(beacon.implementation(), newImplementation);
        // Due to storage collision, asset will fetch the name instead of the asset address.
        assertNotEq(FaultyVault(address(daiVault)).asset(), address(dai));
        address oldImplementation = address(new CollateralVault());
        beacon.upgradeTo(oldImplementation);
        assertEq(beacon.implementation(), oldImplementation);
        // After downgrading the implementation, asset will fetch the correct asset address.
        assertEq(daiVault.asset(), address(dai));
    }

    function test_UpgradeBeaconProxy() public returns (address beacon) {
        address newImplementation = address(new MockVault());
        // update the implementation of the beacon
        beacon = factory.beacon();
        vm.prank(governance);
        // update the implementation of the beacon
        UpgradeableBeacon(beacon).upgradeTo(newImplementation);
        // check the new implementation of the beacon
        assertEq(UpgradeableBeacon(beacon).implementation(), newImplementation);
        assertEq(MockVault(address(daiVault)).VERSION(), 2);
        // no storage collision, asset will fetch the correct asset address.
        assertEq(daiVault.asset(), address(dai));
        assertEq(MockVault(address(daiVault)).isNewImplementation(), true);
    }

    function test_UpgradeAndDowngradeOfBeaconProxy() public {
        address beacon = test_UpgradeBeaconProxy();
        // downgrade the implementation of the beacon
        address oldImplementation = address(new CollateralVault());
        vm.prank(governance);
        UpgradeableBeacon(beacon).upgradeTo(oldImplementation);
        assertEq(UpgradeableBeacon(beacon).implementation(), oldImplementation);
        // Call will revert as old implementation does not have isNewImplementation function.
        vm.expectRevert();
        MockVault(address(daiVault)).isNewImplementation();
    }

    function test_UpgradeBeaconProxyOfPausedCollateralVault() public {
        vm.prank(pauser);
        factory.pauseVault(address(dai));

        test_UpgradeBeaconProxy();
        // Dai vault has been paused before the upgrade, so it should remain paused after the upgrade
        assertTrue(daiVault.paused());
        assertFalse(usdtVault.paused());
    }

    function test_GrantPauserRoleFailsIfNotManager() external {
        address newPauser = makeAddr("newPauser");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, governance, factory.MANAGER_ROLE()
            )
        );
        vm.prank(governance);
        // Will fail even with DEFAULT_ADMIN_ROLE as MANAGER_ROLE is the role admin of PAUSER_ROLE.
        // Hence only MANAGER_ROLE can grant PAUSER_ROLE.
        factory.grantRole(PAUSER_ROLE, newPauser);
    }

    function test_RevokePauserRoleFailsIfNotManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, governance, factory.MANAGER_ROLE()
            )
        );
        vm.prank(governance);
        factory.revokeRole(PAUSER_ROLE, pauser);
    }

    function test_GrantPauserRoleWithNewManager() external {
        address newManager = makeAddr("newManager");
        address newPauser = makeAddr("newPauser");
        vm.prank(governance);
        factory.grantRole(MANAGER_ROLE, newManager);
        // New manager can grant PAUSER_ROLE
        vm.prank(newManager);
        factory.grantRole(PAUSER_ROLE, newPauser);
        // Test if new pauser can pause the factory
        vm.prank(newPauser);
        factory.pause();
        assertEq(factory.paused(), true);
    }

    // NOTE: the previous implementation of _isCappedGlobal was blocking a valid mint
    // because it checked the weights of all the collateral assets. It has been fixed since then.
    // NOTE: since the above mentioned fix has been implemented, we also added some enforcement
    // to the setGlobalCap; hence this test may have became obsolete.
    function test_LoweredGlobalCapDoesNotBlockMintWithOtherAssets() public {
        _factoryMint(dai, 40e18, msg.sender, false);
        _factoryMint(usdt, 40e6, msg.sender, false);
        _factoryMint(dummy, 20e20, msg.sender, false);

        vm.prank(manager);
        factory.setGlobalCap(0.4e18);

        vm.prank(manager);
        factory.setRelativeCap(address(usdt), 1.2e18);

        usdt.approve(address(factory), 1e6);
        vm.expectRevert(IHoneyErrors.ExceedGlobalCap.selector);
        factory.mint(address(usdt), 1e6, msg.sender, false);

        _factoryMint(dummy, 20e20, msg.sender, false);
    }

    // NOTE: the previous implementation of _isCappedGlobal was blocking the redeems
    // when a user frontrunned the decrease of global cap.
    function test_LoweredGlobalCapDoesNotBlockRedeem() public {
        _factoryMint(dai, 4e18, address(this), false);
        _factoryMint(usdt, 3e6, address(this), false);
        _factoryMint(dummy, 3e20, address(this), false);

        // Set the starting global cap to 50%
        vm.prank(manager);
        factory.setGlobalCap(0.5e18);

        // Frontrunning transaction to mint more token2 to be between 40% and 50% of the total weight
        _factoryMint(usdt, 1e6, address(this), false);

        // Reduce the global cap to 40%
        vm.prank(manager);
        factory.setGlobalCap(0.4e18);

        // Try to mint for an asset that's below the global cap (and it's the reference asset) to reduce the weight of
        // token2
        // This was reverting due to exceeding the global cap
        _factoryMint(dai, 1, address(this), false);

        // Try to redeem for token2 to get below the global cap
        // This was reverting due to exceeding the global cap
        factory.redeem(address(usdt), 0.8e18, address(this), false);
    }

    function test_withdrawFeeDenialOfService() public {
        // Set PoL fee rate to a low amount to have fees go to feeReceiver
        vm.prank(governance);
        factory.setPOLFeeCollectorFeeRate(1e18 / 10);

        dai.approve(address(factory), dai.balanceOf(address(this)));
        usdt.approve(address(factory), usdt.balanceOf(address(this)));

        // Mint initial tokens
        factory.mint(address(dai), 200e18, address(this), false);
        factory.mint(address(usdt), 10e6, address(this), false);

        // Accumulate fees by repeatedly minting and redeeming
        for (uint256 i = 0; i < 100; i++) {
            factory.mint(address(usdt), 1e6, address(this), false);
            factory.redeem(address(usdt), 1e6, address(this), false);
        }

        // Mark Token 2 as bad collateral to bypass checks
        vm.prank(manager);
        factory.setCollateralAssetStatus(address(usdt), true);

        // Attempt to redeem the entire supply of shares for token 2
        uint256 totalSupply = usdtVault.totalSupply();

        // Scratch storage for next expectRevert
        uint256 redeemedShares = totalSupply * usdtRedeemRate / 1e18;
        uint256 polFees = (totalSupply - redeemedShares) / 10;
        uint256 expectedSharesPostOperation = totalSupply - polFees - redeemedShares;
        uint256 expectedAssetsPostOperation = usdtVault.convertToAssets(expectedSharesPostOperation);

        vm.expectRevert(
            abi.encodeWithSelector(
                IHoneyErrors.InsufficientAssets.selector, expectedAssetsPostOperation, expectedSharesPostOperation
            )
        );
        factory.redeem(address(usdt), totalSupply, address(this), false);

        // Fees can still be withdrawn
        factory.withdrawFee(address(usdt), feeReceiver);
    }

    function test_SetCustodyInfo() public {
        // reverts if not default admin
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), factory.DEFAULT_ADMIN_ROLE()
            )
        );
        factory.setCustodyInfo(address(usdt), true, address(this));

        vm.prank(governance);
        // reverts if not registered asset
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssetNotRegistered.selector, address(this)));
        factory.setCustodyInfo(address(this), true, address(this));

        // set the custody info
        address custody = _setCustodyInfo(usdt, address(usdtVault));
        (bool isCustodyVault, address custodyAddress) = usdtVault.custodyInfo();
        assertTrue(isCustodyVault);
        assertEq(custodyAddress, custody);
    }

    function test__MintInCustody() public {
        address custody = _setCustodyInfo(dai, address(daiVault));
        // mints 100 dai
        test_mint();
        uint256 polFeePercentage = factory.polFeeCollectorFeeRate();
        uint256 feeShares = 100e18 - (100e18 * 0.99e18) / 1e18; // mint rate is 0.99e18
        uint256 polFeeCollectorShares = feeShares * polFeePercentage / 1e18;
        // amount of dai in custody should be 100e18 - (pol feeShares) as pol fee shares are instantly redeemed.
        assertEq(dai.balanceOf(address(daiVault)), 0);
        assertEq(dai.balanceOf(custody), 100e18 - polFeeCollectorShares);
    }

    function test_RedeemInCustody() public {
        address custody = _setCustodyInfo(usdt, address(usdtVault));
        test_redeem();
        // there wont be any usdt in the custody as all is redeemed.
        assertEq(usdt.balanceOf(custody), 0);
    }

    function test_LiquidationInCustody() public {
        _setCustodyInfo(usdt, address(usdtVault));
        testFuzz_liquidate_WhenBadCollateralDepeg(1e18, 1e6, 0.5e18, 0.1e18, 1e18, true);
    }

    function test_liquidate_WhenThereIsNoSufficientBadCollateralInCustody() public {
        _setCustodyInfo(usdt, address(usdtVault));
        test_liquidate_WhenThereIsNoSufficientBadCollateral();
    }

    function test_GlobalCapLowering_InCustody() public {
        _setCustodyInfo(usdt, address(usdtVault));
        test_LoweredGlobalCapDoesNotBlockMintWithOtherAssets();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          INTERNAL                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _setCustodyInfo(ERC20 asset, address assetVault) internal returns (address custodyAddress) {
        custodyAddress = makeAddr("custodyAddress");
        vm.prank(custodyAddress);
        asset.approve(address(assetVault), type(uint256).max);
        vm.prank(governance);
        factory.setCustodyInfo(address(asset), true, custodyAddress);
    }

    function _predictVaultAddress(address asset) internal view returns (address) {
        address beacon = factory.beacon();
        bytes32 salt;
        assembly ("memory-safe") {
            mstore(0, asset)
            salt := keccak256(0, 0x20)
        }
        return LibClone.predictDeterministicAddressERC1967BeaconProxy(beacon, salt, address(factory));
    }

    function _initialMint(uint256 _daiToMint) internal returns (uint256 mintedHoneys) {
        mintedHoneys = _initialMintToAParticularReceiver(_daiToMint, receiver);
    }

    function _initialMintToAParticularReceiver(
        uint256 _daiToMint,
        address _receiver
    )
        internal
        returns (uint256 mintedHoneys)
    {
        dai.mint(address(this), _daiToMint);
        mintedHoneys = _factoryMint(dai, _daiToMint, _receiver, false);
    }

    function _verifyOutputOfMint(
        ERC20 _token,
        CollateralVault _tokenVault,
        uint256 _tokenBal,
        uint256 _tokenToMint,
        uint256 _mintedHoneys
    )
        internal
    {
        // Assumption: 100% fees transferred to the PoL collector
        uint256 honeyShares = _tokenVault.convertToShares(_tokenToMint);
        uint256 mintedHoney = honeyShares * factory.mintRates(address(_token)) / 1e18;
        uint256 fees = _tokenVault.convertToAssets(honeyShares - mintedHoney);

        assertEq(_token.balanceOf(address(this)), _tokenBal - _tokenToMint);
        assertEq(_token.balanceOf(polFeeCollector), fees);
        assertEq(_token.balanceOf(address(_tokenVault)), _tokenToMint - fees);

        assertEq(honey.balanceOf(receiver), _mintedHoneys);

        _assertEqVaultBalance(address(_token), _tokenToMint - fees);
    }

    function _verifyOutputOfRedeem(
        ERC20 _token,
        CollateralVault _tokenVault,
        uint256 _tokenBal,
        uint256 _tokenToMint,
        uint256 _mintedHoney,
        uint256 _redeemedToken, // preview
        uint256 _honeyToRedeem,
        uint256 existingHoney
    )
        internal
    {
        uint256 polFees = _token.balanceOf(address(polFeeCollector));

        assertEq(_token.balanceOf(address(_tokenVault)), _tokenToMint - _redeemedToken - polFees);
        assertEq(_token.balanceOf(address(this)), _tokenBal - _tokenToMint + _redeemedToken);

        assertEq(honey.balanceOf(receiver), existingHoney + _mintedHoney - _honeyToRedeem);
        assertEq(honey.totalSupply(), existingHoney + _mintedHoney - _honeyToRedeem);

        _assertEqVaultBalance(address(_token), _tokenToMint - _redeemedToken - polFees);
    }

    function _factoryMint(
        ERC20 asset,
        uint256 amount,
        address receiver_,
        bool expectBasketMode
    )
        internal
        returns (uint256 mintedHoneys)
    {
        asset.approve(address(factory), amount);
        mintedHoneys = factory.mint(address(asset), amount, receiver_, expectBasketMode);
    }

    function _provideReferenceCollateral(uint256 amount) internal returns (uint256 mintedHoneys) {
        mintedHoneys = _factoryMint(dai, amount, receiver, false);
    }

    function _depegFeed(bytes32 feed, uint256 pegOffset, DepegDirection direction) internal {
        if (pegOffset <= PEG_OFFSET) {
            pegOffset = PEG_OFFSET + 0.001e18;
        }
        int64 depegPrice;
        if (direction == DepegDirection.UnderOneDollar) {
            depegPrice = int64(uint64((1e18 - pegOffset) / 10 ** 10));
        } else {
            depegPrice = int64(uint64((1e18 + pegOffset) / 10 ** 10));
        }
        pyth.setData(feed, depegPrice, uint64(31_155), int32(-8), block.timestamp);
    }

    function _forceBasketMode() internal {
        vm.prank(manager);
        factory.setForcedBasketMode(true);
    }

    // Perform assertEq by handling share's rounding issues:
    function _assertEqVaultBalance(address asset, uint256 tokenAmount) internal {
        CollateralVault vault = factory.vaults(asset);
        ERC20 token = ERC20(vault.asset());
        uint8 decimals = token.decimals();
        uint256 deltaDecimals = (decimals <= 18) ? (18 - decimals) : (decimals - 18);
        uint256 delta = 10 ** (deltaDecimals + 1);

        // assertEq(token.balanceOf(address(vault)), tokenAmount);
        assertApproxEqAbs(vault.balanceOf(address(factory)), vault.convertToShares(tokenAmount), delta);
    }

    function _getIndexOfAsset(address asset) internal view returns (uint256 index, bool found) {
        uint256 num = factory.numRegisteredAssets();
        address[] memory collaterals = new address[](num);
        for (uint256 i = 0; i < num; i++) {
            collaterals[i] = factory.registeredAssets(i);
        }

        found = false;
        for (uint256 i = 0; i < num; i++) {
            if (collaterals[i] == asset) {
                found = true;
                index = i;
                break;
            }
        }
    }
}
