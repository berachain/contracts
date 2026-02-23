// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ERC20 } from "solady/src/tokens/ERC20.sol";
import { ERC4626 } from "solady/src/tokens/ERC4626.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { CollateralVault } from "src/honey/CollateralVault.sol";
import { HoneyBaseTest, VaultAdmin } from "./HoneyBase.t.sol";
import { IHoneyErrors } from "src/honey/IHoneyErrors.sol";
import { IHoneyFactory } from "src/honey/IHoneyFactory.sol";
import { HoneyFactoryPythWrapper } from "src/honey/HoneyFactoryPythWrapper.sol";
import { MockUSDT, MockDummy, MockAsset } from "@mock/honey/MockAssets.sol";

contract HoneyFactoryPythWrapperTest is HoneyBaseTest {
    HoneyFactoryPythWrapper factoryWrapper;
    bytes[] empty;
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

        factoryWrapper = new HoneyFactoryPythWrapper(address(factory), address(pyth), address(factoryReader));
        vm.stopPrank();
    }

    function testFuzz_mint_failsWithUnregisteredAsset(uint32 _usdtToMint) external {
        MockUSDT usdtNew = new MockUSDT(); // new unregistered usdt token instance
        usdtNew.mint(address(this), _usdtToMint);
        usdtNew.approve(address(factoryWrapper), _usdtToMint);

        vm.prank(governance);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssetNotRegistered.selector, address(usdtNew)));
        factoryWrapper.mint(empty, address(usdtNew), _usdtToMint, receiver, false);
    }

    function test_mint_failsWithBadCollateralAsset() external {
        // sets dai as bad collateral asset.
        test_setCollateralAssetStatus();

        dai.approve(address(factoryWrapper), 100e18);

        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssetIsBadCollateral.selector, address(dai)));
        factoryWrapper.mint(empty, address(dai), 100e18, receiver, false);
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

    function test_mint() external {
        uint256 _daiToMint = 100e18;
        uint256 mintedHoneys = (_daiToMint * daiMintRate) / 1e18;
        dai.approve(address(factoryWrapper), _daiToMint);

        vm.expectEmit();
        emit IHoneyFactory.HoneyMinted(address(factoryWrapper), receiver, address(dai), _daiToMint, mintedHoneys);
        mintedHoneys = factoryWrapper.mint(empty, address(dai), _daiToMint, receiver, false);
    }

    function test_mint_failsIfDepositAssetWithZeroWeightWhenBasketModeIsEnabled() external {
        uint256 usdtToMint = 100e6;
        // Deposit reference collateral
        _initialMint(100e18);
        _forceBasketMode();

        usdt.approve(address(factoryWrapper), usdtToMint);
        // The assumption is: Basket mode ensures the distribution of the weight of the assets
        // If the weight of the deposit asset is zero, the minting should fail
        // because it move upon a specific direction the distribution of the collateral
        // making the distribution changed.
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.ZeroWeight.selector, address(usdt)));
        factoryWrapper.mint(empty, address(usdt), usdtToMint, receiver, true);
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

        assertEq(dai.allowance(address(this), address(factoryWrapper)), 0);
        assertEq(usdt.allowance(address(this), address(factoryWrapper)), 0);
        assertEq(dummy.allowance(address(this), address(factoryWrapper)), 0);

        for (uint256 i = 0; i < numAssets; i++) {
            address asset = factory.registeredAssets(i);
            if (asset == address(dummy)) {
                dummyToUseForMint = amounts[i];
            }
            uint256 balance = ERC20(asset).balanceOf(address(this));
            if (balance < amounts[i]) {
                MockAsset(asset).mint(address(this), amounts[i] - balance);
            }
            ERC20(asset).approve(address(factoryWrapper), amounts[i]);
        }

        uint256 mintedHoneys = factoryWrapper.mint(empty, address(dummy), dummyToUseForMint, receiver, true);

        assertApproxEqAbs(dai.allowance(address(this), address(factoryWrapper)), 0, 1e2);
        assertApproxEqAbs(usdt.allowance(address(this), address(factoryWrapper)), 0, 1);
        assertApproxEqAbs(dummy.allowance(address(this), address(factoryWrapper)), 0, 1e3);

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
            ERC20(asset).approve(address(factoryWrapper), amounts[i]);
        }

        uint256 mintedHoneys = factoryWrapper.mint(empty, address(dummy), dummyToUseForMint, receiver, true);

        assertApproxEqAbs(dai.allowance(address(this), address(factoryWrapper)), 0, 1e2);
        assertApproxEqAbs(usdt.allowance(address(this), address(factoryWrapper)), 0, 1);
        assertApproxEqAbs(dummy.allowance(address(this), address(factoryWrapper)), 0, 1e3);

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
        factoryWrapper.mint(empty, address(dummy), honeyToMintBM, receiver, true);

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
                    // see HoneyFactoryReader.sol#L62 for +1 reason
                    uint256 expectedAmount = 25e18 * 1e18 / factory.mintRates(asset) + 1;
                    assertEq(amounts[i], expectedAmount);
                }

                uint256 balance = ERC20(asset).balanceOf(address(this));
                if (balance < amounts[i]) {
                    MockAsset(asset).mint(address(this), amounts[i] - balance);
                }
                ERC20(asset).approve(address(factoryWrapper), amounts[i]);
            }
        }

        {
            // Mint in basket mode:
            uint256 mintedHoneys = factoryWrapper.mint(empty, address(usdt), usdtToUseForMint, receiver, true);

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

    function testFuzz_redeem_failsWithUnregisteredAsset(uint256 _honeyAmount) external {
        uint256 mintedHoney = _factoryMint(dai, daiBalance, address(this), false);
        _honeyAmount = _bound(_honeyAmount, 1, mintedHoney);

        honey.approve(address(factoryWrapper), _honeyAmount);
        MockUSDT usdtNew = new MockUSDT(); // new unregistered usdt token instance
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssetNotRegistered.selector, address(usdtNew)));
        factoryWrapper.redeem(empty, address(usdtNew), _honeyAmount, receiver, false);
    }

    function testFuzz_redeem_failWithPausedFactory(uint256 _honeyAmount) external {
        uint256 mintedHoney = _factoryMint(dai, daiBalance, address(this), false);
        _honeyAmount = _bound(_honeyAmount, 1, mintedHoney);

        vm.prank(pauser);
        factory.pause();

        honey.approve(address(factoryWrapper), _honeyAmount);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        factoryWrapper.redeem(empty, address(dai), _honeyAmount, receiver, false);
    }

    function testFuzz_redeem_failsWithInsufficientHoneys(uint256 _honeyAmount) external {
        uint256 mintedHoney = _factoryMint(dai, daiBalance, address(this), false);
        _honeyAmount = _bound(_honeyAmount, mintedHoney + 1, type(uint128).max);

        honey.approve(address(factoryWrapper), _honeyAmount);
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        factoryWrapper.redeem(empty, address(dai), _honeyAmount, receiver, false);
    }

    function testFuzz_redeem_failsWithInsufficientShares(uint256 _daiToMint) external {
        _daiToMint = _bound(_daiToMint, 100, daiBalance);
        uint256 mintedHoneys = _initialMintToAParticularReceiver(_daiToMint, address(this));
        vm.prank(address(factory));
        // vaultAdmin mints honey to this address without increasing shares
        honey.mint(address(this), mintedHoneys);
        honey.approve(address(factoryWrapper), (mintedHoneys * 3) / 2);
        vm.expectRevert(ERC4626.RedeemMoreThanMax.selector);
        factoryWrapper.redeem(empty, address(dai), (mintedHoneys * 3) / 2, address(this), false);
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
        honey.approve(address(factoryWrapper), _honeyToRedeem);

        vm.prank(receiver);
        factoryWrapper.redeem(empty, address(dai), _honeyToRedeem, address(this), false);
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
        honey.approve(address(factoryWrapper), _honeyToRedeem);

        vm.prank(receiver);
        factoryWrapper.redeem(empty, address(usdt), _honeyToRedeem, address(this), false);
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
        honey.approve(address(factoryWrapper), _honeyToRedeem);

        vm.prank(receiver);
        factoryWrapper.redeem(empty, address(dummy), _honeyToRedeem, address(this), false);

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

        honey.approve(address(factoryWrapper), honeyToRedeem);

        factoryWrapper.redeem(empty, address(usdt), honeyToRedeem, address(this), true);

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

        honey.approve(address(factoryWrapper), honeyToRedeem);

        uint256[] memory redemedAmount = factoryWrapper.redeem(empty, asset, honeyToRedeem, address(this), true);

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

    function testFuzz_redeem_refundsLeftoverHoneyInBasketMode(uint256 honeyToRedeem) external {
        // Setup: Mint with 3 assets to create a 33/33/33 weight distribution
        uint256 daiToMint = 100e18;
        uint256 usdtToMint = 100e6;
        uint256 dummyToMint = 100e20;

        _factoryMint(dai, daiToMint, address(this), false);
        _factoryMint(usdt, usdtToMint, address(this), false);
        _factoryMint(dummy, dummyToMint, address(this), false);

        uint256 totalHoney = honey.balanceOf(address(this));
        // Use amounts that are likely to cause rounding issues (not divisible by 3)
        honeyToRedeem = _bound(honeyToRedeem, 1e18, totalHoney - 1e11);

        _forceBasketMode();

        uint256 userHoneyBefore = honey.balanceOf(address(this));
        uint256 wrapperHoneyBefore = honey.balanceOf(address(factoryWrapper));
        // wrapper should start with zero honey
        assertEq(wrapperHoneyBefore, 0);

        honey.approve(address(factoryWrapper), honeyToRedeem);
        factoryWrapper.redeem(empty, address(dai), honeyToRedeem, address(this), true);

        uint256 userHoneyAfter = honey.balanceOf(address(this));
        uint256 wrapperHoneyAfter = honey.balanceOf(address(factoryWrapper));

        // The wrapper should have refunded any leftover honey - no honey should remain in wrapper
        assertEq(wrapperHoneyAfter, 0);

        // Calculate expected honey consumed (sum of what was actually burned across all assets)
        uint256[] memory weights = factory.getWeights();
        uint256 totalBurned = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            totalBurned += honeyToRedeem * weights[i] / 1e18;
        }

        // User should have their original balance minus what was actually burned
        // (any rounding leftovers are refunded)
        uint256 expectedUserHoney = userHoneyBefore - totalBurned;
        // user should receive leftover honey from rounding
        assertEq(userHoneyAfter, expectedUserHoney);

        // Verify that rounding can cause some leftover in this case
        assertLe(totalBurned, honeyToRedeem);
    }

    function test_redeem_failsWhenVaultIsPaused() external {
        _factoryMint(dai, 100e18, address(this), false);
        vm.prank(pauser);
        factory.pauseVault(address(dai));

        honey.approve(address(factoryWrapper), 50e18);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.VaultPaused.selector, address(dai)));
        factoryWrapper.redeem(empty, address(dai), 50e18, receiver, false);
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
        honey.approve(address(factoryWrapper), honeyToRedeem);
        uint256[] memory redemedAmounts =
            factoryWrapper.redeem(empty, address(dummy), honeyToRedeem, address(this), true);

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
        dummy.approve(address(factoryWrapper), 1e20);

        // It should revert due to RelativeCap because the amount stored on the dummy collateral vault
        // is greather than the ones of the reference collateral.
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.ExceedRelativeCap.selector));
        factoryWrapper.mint(empty, address(dummy), 1e20, address(this), false);

        honey.approve(address(factoryWrapper), 1e18);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.ExceedRelativeCap.selector));
        factoryWrapper.redeem(empty, address(dai), 1e18, address(this), false);

        vm.startPrank(manager);
        // Increase relativeCap threshold to 200%
        factory.setRelativeCap(address(dummy), 2e18);
        factory.setRelativeCap(address(usdt), 2e18);
        vm.stopPrank();

        factoryWrapper.mint(empty, address(dummy), 1e20, address(this), false);

        factoryWrapper.redeem(empty, address(dai), 1e18, address(this), false);
    }

    function test_liquidate_failsIfLiquidationIsNotEnabled() external {
        vm.prank(governance);
        factory.setLiquidationEnabled(false);

        usdt.approve(address(factoryWrapper), 100e6);
        vm.expectRevert(IHoneyErrors.LiquidationDisabled.selector);
        factoryWrapper.liquidate(empty, address(dai), address(usdt), 100e6);
    }

    function test_liquidate_failsWhenBadCollateralIsNotRegistered() external {
        MockUSDT usdtNew = new MockUSDT(); // new unregistered usdt token instance
        dai.approve(address(factoryWrapper), 100e18);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssetNotRegistered.selector, address(usdtNew)));
        factoryWrapper.liquidate(empty, address(usdtNew), address(dai), 100e18);
    }

    function test_liquidate_failsWhenBadCollateralIsNotRegisteredAsBadCollateral() external {
        vm.prank(governance);
        factory.setLiquidationEnabled(true);

        dai.approve(address(factoryWrapper), 100e18);
        // new unregistered usdt token instance
        vm.expectRevert(IHoneyErrors.AssetIsNotBadCollateral.selector);
        factoryWrapper.liquidate(empty, address(usdt), address(dai), 100e18);
    }

    function test_liquidate_failsIfGoodCollateralIsNotRegistered() external {
        MockUSDT usdtNew = new MockUSDT(); // new unregistered usdt token instance
        usdtNew.mint(address(this), 100e6);
        usdtNew.approve(address(factoryWrapper), 100e6);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssetNotRegistered.selector, address(usdtNew)));
        factoryWrapper.liquidate(empty, address(usdt), address(usdtNew), 100e6);
    }

    function test_liquidate_failsIfGoodCollateralIsBadCollateral() external {
        vm.prank(manager);
        factory.setCollateralAssetStatus(address(usdt), true);

        // new unregistered usdt token instance
        usdt.approve(address(factoryWrapper), 100e6);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssetIsBadCollateral.selector, address(usdt)));
        factoryWrapper.liquidate(empty, address(dai), address(usdt), 100e6);
    }

    function test_liquidate_failsIfReferenceCollateralIsBadCollateral() external {
        vm.prank(governance);
        factory.setLiquidationEnabled(true);

        vm.prank(manager);
        factory.setCollateralAssetStatus(address(dai), true);

        usdt.approve(address(factoryWrapper), 100e6);
        vm.expectRevert(IHoneyErrors.LiquidationWithReferenceCollateral.selector);
        factoryWrapper.liquidate(empty, address(dai), address(usdt), 100e6);
    }

    function test_liquidate_failsWithNoAllowance() external {
        vm.prank(governance);
        factory.setLiquidationEnabled(true);

        uint256 daiToProvide = 100e18;
        dai.approve(address(factoryWrapper), daiToProvide - 1);

        vm.prank(manager);
        factory.setCollateralAssetStatus(address(usdt), true);

        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        factoryWrapper.liquidate(empty, address(usdt), address(dai), daiToProvide);
    }

    function test_liquidate_WhenThereIsNoSufficientBadCollateral() external {
        vm.prank(governance);
        factory.setLiquidationEnabled(true);

        uint256 daiToMint = 100e18;
        _factoryMint(dai, daiToMint, receiver, false);
        uint256 usdtToMint = 50e6;
        _factoryMint(usdt, usdtToMint, receiver, false);

        // LiquidationRate is zero and the price of the two assets is the same
        uint256 daiToProvide = 100e18;
        dai.approve(address(factoryWrapper), daiToProvide);

        vm.prank(manager);
        factory.setCollateralAssetStatus(address(usdt), true);

        assertEq(dai.balanceOf(address(this)), daiBalance - daiToMint);
        assertEq(usdt.balanceOf(address(this)), usdtBalance - usdtToMint);

        _assertEqVaultBalance(address(dai), daiToMint * daiMintRate / 1e18);
        _assertEqVaultBalance(address(usdt), usdtToMint * usdtMintRate / 1e18);

        uint256 usdtToObtain = 50e6 * usdtMintRate / 1e18;
        uint256 daiToBeTaken = 50e18 * daiMintRate / 1e18;

        uint256 usdtObtained = factoryWrapper.liquidate(empty, address(usdt), address(dai), daiToProvide);

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

        dai.approve(address(factoryWrapper), daiToProvide);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.ZeroAmount.selector));
        factoryWrapper.liquidate(empty, address(usdt), address(dai), daiToProvide);
    }

    function testFuzz_liquidate_WhenBadCollateralDepeg(
        uint256 daiToMint,
        uint256 usdtToMint,
        uint256 pegOffset,
        uint256 liquidationRate,
        uint256 daiToProvide,
        bool depegOver
    )
        external
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
        dai.approve(address(factoryWrapper), daiToProvide);
        factoryWrapper.liquidate(empty, address(usdt), address(dai), daiToProvide);

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

        usdt.approve(address(factoryWrapper), usdtToProvide);
        vm.expectRevert(IHoneyErrors.ExceedRelativeCap.selector);
        factoryWrapper.liquidate(empty, address(dummy), address(usdt), usdtToProvide);
    }

    function test_recapitalize_failsIfAssetIsNotRegistered() external {
        MockUSDT usdtNew = new MockUSDT(); // new unregistered usdt token instance
        usdtNew.mint(address(this), 100e6);
        usdtNew.approve(address(factoryWrapper), 100e6);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssetNotRegistered.selector, address(usdtNew)));
        factoryWrapper.recapitalize(empty, address(usdtNew), 100e6);
    }

    function test_recapitalize_failsIfBadAsset() external {
        vm.prank(manager);
        factory.setCollateralAssetStatus(address(usdt), true);
        usdt.approve(address(factoryWrapper), 100e6);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssetIsBadCollateral.selector, address(usdt)));
        factoryWrapper.recapitalize(empty, address(usdt), 100e6);
    }

    function test_recapitalize_failsForInsufficientAllowance() external {
        _initialMint(100e18);

        vm.prank(governance);
        factory.setRecapitalizeBalanceThreshold(address(dai), 200e18);

        dai.approve(address(factoryWrapper), 99e18);
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        factoryWrapper.recapitalize(empty, address(dai), 100e18);
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

        dai.approve(address(factoryWrapper), 1e18);
        vm.expectRevert(IHoneyErrors.ExceedGlobalCap.selector);
        factoryWrapper.recapitalize(empty, address(dai), 1e18);
    }

    function testFuzz_recapitalize_failsWhenExceedRelativeCap(uint256 daiToMint, uint256 usdtToRecapitalize) external {
        daiToMint = _bound(daiToMint, 1e18, daiBalance);
        uint256 usdtToMint = daiToMint / 10 ** 12;
        usdtToRecapitalize = _bound(usdtToRecapitalize, 1e6, usdtBalance - usdtToMint);

        _factoryMint(dai, daiToMint, address(this), false);
        _factoryMint(usdt, usdtToMint, address(this), false);

        vm.prank(governance);
        factory.setRecapitalizeBalanceThreshold(address(usdt), usdtToMint + usdtToRecapitalize);

        usdt.approve(address(factoryWrapper), usdtToRecapitalize);
        vm.expectRevert(IHoneyErrors.ExceedRelativeCap.selector);
        factoryWrapper.recapitalize(empty, address(usdt), usdtToRecapitalize);
    }

    function testFuzz_recapitalize_failsWhenTargetBalanceIsNotSet(uint256 usdtToRecapitalize) external {
        uint256 MINIMUM_RECAPITALIZE_SHARES = factory.minSharesToRecapitalize();
        usdtToRecapitalize = _bound(usdtToRecapitalize, MINIMUM_RECAPITALIZE_SHARES / 1e12, type(uint160).max);
        usdt.mint(address(this), usdtToRecapitalize);
        usdt.approve(address(factoryWrapper), usdtToRecapitalize);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.RecapitalizeNotNeeded.selector, address(usdt)));
        factoryWrapper.recapitalize(empty, address(usdt), usdtToRecapitalize);
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
        usdt.approve(address(factoryWrapper), usdtToRecapitalize);
        vm.expectRevert(
            abi.encodeWithSelector(IHoneyErrors.InsufficientRecapitalizeAmount.selector, usdtToRecapitalize)
        );
        factoryWrapper.recapitalize(empty, address(usdt), usdtToRecapitalize);
    }

    function testFuzz_recapitalize(uint256 daiCollateral, uint256 daiGifted) external {
        daiCollateral = _bound(daiCollateral, 1e18, daiBalance); // 1–200
        // Min shares to recapitalize is 1e18, which is exactly 1 dai token (18 decimals)
        uint256 minSharesToRecapitalize = factory.minSharesToRecapitalize();
        uint256 minBalance = daiVault.convertToAssets(minSharesToRecapitalize);
        // Target amount to recapitalize:
        uint256 targetBalance = _bound(daiGifted, daiBalance + 1, 2 * daiBalance);
        // Amount of DAI provided for recapitalization:
        // NOTE: the upper bound exceeds the target balance (with an arbitrary
        //       amount) in order to also cover that code path.
        daiGifted = _bound(daiGifted, minBalance, targetBalance + minBalance);

        // Ensure that the executor has enough DAI for the test
        dai.mint(address(this), daiGifted);

        _factoryMint(dai, daiCollateral, receiver, false);

        vm.prank(governance);
        factory.setRecapitalizeBalanceThreshold(address(dai), targetBalance);

        uint256 vaultBalancePre = daiVault.totalAssets();
        assertLt(vaultBalancePre, targetBalance);
        uint256 missingBalance = targetBalance - vaultBalancePre;

        uint256 userBalancePre = dai.balanceOf(address(this));
        uint256 honeySupplyPre = honey.totalSupply();

        dai.approve(address(factoryWrapper), daiGifted);
        factoryWrapper.recapitalize(empty, address(dai), daiGifted);

        uint256 vaultBalancePost = daiVault.totalAssets();
        uint256 userBalancePost = dai.balanceOf(address(this));
        uint256 daiAccepted = userBalancePre - userBalancePost;
        uint256 honeySupplyPost = honey.totalSupply();

        // no honeys are minted during recapitalization
        assertEq(honeySupplyPre, honeySupplyPost);

        if (vaultBalancePre + daiGifted > targetBalance) {
            // vault balance post recapitalize equal to target balance
            assertEq(vaultBalancePost, targetBalance);
            // not all gifted dais are used
            assertLt(daiAccepted, daiGifted);
            assertEq(daiAccepted, missingBalance);
        } else if (vaultBalancePre + daiGifted == targetBalance) {
            // vault balance post recapitalize equal to target balance
            assertEq(vaultBalancePost, targetBalance);
            // all gifted dais are used
            assertEq(daiAccepted, daiGifted);
        } else {
            // vault balance post recapitalize less than target balance
            assertLt(vaultBalancePost, targetBalance);
            uint256 deficit = missingBalance - daiGifted;
            if (deficit < minBalance) {
                // not all gifted dais are used
                assertLt(daiAccepted, daiGifted);
                assertEq(daiAccepted, missingBalance - minBalance);
                assertEq(daiGifted - daiAccepted, minBalance - deficit);
                // the a-posteriori deficit equals the min amount to recapitalize
                assertEq(targetBalance - vaultBalancePost, minBalance);
            } else {
                // all gifted dais are used
                assertEq(daiAccepted, daiGifted);
            }
        }
    }

    function test_redeem() external {
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

        honey.approve(address(factoryWrapper), mintedHoneysForUsdt);

        vm.expectEmit();
        emit IHoneyFactory.HoneyRedeemed(
            address(factoryWrapper), address(this), address(usdt), redeemedUsdt / 1, mintedHoneysForUsdt
        );
        factoryWrapper.redeem(empty, address(usdt), mintedHoneysForUsdt, address(this), false);

        assertEq(usdt.balanceOf(address(this)), usdtBalance - usdtToMint + redeemedUsdt);
        assertEq(honey.balanceOf(address(this)), mintedHoneysForDai);
    }

    function test_redeem_failsWhenReferenceCollateralIsRedeemedAndExceedsRelativeCapOnOtherAssets() external {
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
        honey.approve(address(factoryWrapper), 2e18);
        vm.expectRevert(IHoneyErrors.ExceedRelativeCap.selector);
        factoryWrapper.redeem(empty, address(dai), 2e18, address(this), false);
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

    function test_setCollateralAssetStatus() public {
        vm.prank(manager);
        vm.expectEmit();
        emit VaultAdmin.CollateralAssetStatusSet(address(dai), true);
        factory.setCollateralAssetStatus(address(dai), true);
        assertEq(factory.isBadCollateralAsset(address(dai)), true);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          INTERNAL                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

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
        asset.approve(address(factoryWrapper), amount);
        mintedHoneys = factoryWrapper.mint(empty, address(asset), amount, receiver_, expectBasketMode);
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
