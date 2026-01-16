// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { BGTIncentiveFeeCollector } from "src/pol/BGTIncentiveFeeCollector.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { InfraredBeraAdapter, IInfraredBera } from "src/pol/lst/InfraredBeraAdapter.sol";
import { LSTStakerVault } from "src/pol/lst/LSTStakerVault.sol";
import { LSTStakerVaultFactory } from "src/pol/lst/LSTStakerVaultFactory.sol";
import { LSTStakerVaultFactoryDeployer } from "src/pol/lst/LSTStakerVaultFactoryDeployer.sol";
import { WBERA } from "src/WBERA.sol";
import { Salt } from "src/base/Salt.sol";

/// @notice Fork tests for the BGTIncentiveFeeCollector adding InfraredBera as an LST.
contract LSTStakerVaultInfraredBera is Create2Deployer, Test {
    WBERA wbera = WBERA(payable(0x6969696969696969696969696969696969696969));
    BGTIncentiveFeeCollector collector = BGTIncentiveFeeCollector(0x1984Baf659607Cc5f206c55BB3B00eb3E180190B);
    LSTStakerVaultFactory factory;

    address iBera = 0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5;
    address honey = 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce;
    address wberaStakerVault = 0x118D2cEeE9785eaf70C15Cd74CD84c9f8c3EeC9a;
    address safeOwner = 0xD13948F99525FB271809F45c268D72a3C00a568D;

    uint256 forkBlock = 13_360_750;

    // castb call 0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5 "convertToAssets(uint256)(uint256)" 1000000000000000000
    // --block 13360750
    // uint256 iberaRebasingValueAtFork = 1_030_285_826_962_531_082;

    // Value from rate provider is slightly bigger since it uses previewBurn (compounding yield) instead of
    // convertToAssets
    // castb call 0x776fD57Bbeb752BDeEB200310faFAe9A155C50a0 "getRate()(uint256)" --block 13360750
    uint256 iberaRebasingValueAtFork = 1_030_285_837_693_977_596;

    function setUp() public virtual {
        vm.createSelectFork("berachain");
        vm.rollFork(forkBlock);
    }

    // check all good before upgrade
    function test_claimBeforeUpgrade() public {
        uint256 svBalanceBefore = wbera.balanceOf(wberaStakerVault);
        _claimFees();
        uint256 svDeltaBalance = wbera.balanceOf(wberaStakerVault) - svBalanceBefore;

        // Check payout amount has been transferred to the Staker Vault
        assertEq(collector.payoutAmount(), svDeltaBalance);
    }

    function test_Upgrade() public {
        _upgradeCollector();

        // check if there is the lstStakerVaultsLength method
        uint256 lstStakerVaultsLength = collector.lstStakerVaultsLength();
        assertEq(lstStakerVaultsLength, 0);
    }

    function test_claimAfterUpgrade() public {
        _upgradeCollector();

        uint256 svBalanceBefore = wbera.balanceOf(wberaStakerVault);
        _claimFees();
        uint256 svDeltaBalance = wbera.balanceOf(wberaStakerVault) - svBalanceBefore;

        // Check payout amount has been transferred to the Staker Vault
        assertEq(collector.payoutAmount(), svDeltaBalance);
    }

    function test_claimSplit() public {
        // Upgrade and deploy vault for infrared bera
        _upgradeCollector();
        _deployFactory();
        address infraredVault = _addInfraredBeraStakerVault();

        // Deposit into lst staker vault
        address user = 0xB65E74f6B2C0633E30ba1bE75db818BB9522a81A;
        uint256 stakeAmount = 1e24; // 1M iBera
        _stakeLST(iBera, infraredVault, user, stakeAmount);

        // Compute expected split amounts
        uint256 mainShare;
        uint256 iberaShare;

        {
            IERC4626 mainVault = IERC4626(wberaStakerVault);
            // expected value at block: 24952954.357206464
            uint256 wberaStakeValue = mainVault.totalAssets();

            uint256 iberaStake = IERC4626(infraredVault).totalAssets();
            // expected value at block: 1030285.8269625311
            uint256 iberaStakeValue = iberaStake * iberaRebasingValueAtFork / 1e18;

            mainShare = wberaStakeValue * 1e18 / (iberaStakeValue + wberaStakeValue);
            iberaShare = iberaStakeValue * 1e18 / (iberaStakeValue + wberaStakeValue);
        }

        uint256 mainBalanceBefore = wbera.balanceOf(wberaStakerVault);
        uint256 iberaBalanceBefore = IERC20(iBera).balanceOf(infraredVault);
        uint256 payoutAmount = collector.payoutAmount();

        // iBera compounds yield before minting shares, this is why convertToShares method is off to some extent.
        // uint256 expectedPayoutIbera = IERC4626(iBera).convertToShares(wberaAmountToIbera);

        // also this is off because of the iberaRebasingValueAtFork is taken from convertToShares
        // uint256 expectedPayoutIbera = ((payoutAmount * iberaShare / 1e18) * 1e18) / iberaRebasingValueAtFork;

        uint256 wberaAmountToIbera = payoutAmount * iberaShare / 1e18;
        uint256 expectedPayoutIbera = IERC4626(iBera).previewMint(wberaAmountToIbera);

        _claimFees();

        uint256 mainDeltaBalance = wbera.balanceOf(wberaStakerVault) - mainBalanceBefore;
        uint256 iberaDeltaBalance = IERC20(iBera).balanceOf(infraredVault) - iberaBalanceBefore;
        uint256 expectedPayoutMain = payoutAmount * mainShare / 1e18;

        // Check payout amount has been split fairly between the two Staker Vaults
        assertApproxEqAbs(expectedPayoutMain, mainDeltaBalance, 1e4);
        assertApproxEqAbs(expectedPayoutIbera, iberaDeltaBalance, 1e4);
    }

    function _stakeLST(address token, address vault, address user, uint256 amount) internal {
        vm.startPrank(user);
        IERC20(token).approve(vault, amount);
        uint256 stakerShares = IERC4626(vault).deposit(amount, user);
        vm.stopPrank();

        vm.assertEq(IERC4626(vault).balanceOf(user), stakerShares);
        vm.assertEq(IERC20(token).balanceOf(vault), amount + factory.INITIAL_DEPOSIT());
    }

    function _upgradeCollector() internal {
        // deploy the new implementation of BgtIncentiveFeeCollector
        address impl = deployWithCreate2(0, type(BGTIncentiveFeeCollector).creationCode);

        // upgrade the BgtIncentiveFeeCollector implementation
        vm.prank(safeOwner);
        collector.upgradeToAndCall(impl, bytes(""));
    }

    function _claimFees() public {
        address claimer = address(0x1234);
        uint256 payoutAmount = collector.payoutAmount();
        vm.deal(claimer, payoutAmount);

        uint256 honeyBalance = IERC20(honey).balanceOf(address(collector));

        vm.startPrank(claimer);
        wbera.deposit{ value: payoutAmount }();
        wbera.approve(address(collector), payoutAmount);
        address[] memory tokensToClaim = new address[](1);
        tokensToClaim[0] = honey;
        collector.claimFees(claimer, tokensToClaim);
        vm.stopPrank();

        assertEq(0, IERC20(honey).balanceOf(address(collector)));
        assertEq(honeyBalance, IERC20(honey).balanceOf(claimer));
    }

    function _addInfraredBeraStakerVault() internal returns (address vault) {
        address adapter = address(new InfraredBeraAdapter());
        return _addIBeraLstVault(adapter);
    }

    function _addIBeraLstVault(address adapter) internal returns (address vault) {
        _provideInitialIBeraDeposit();

        vm.startPrank(safeOwner);
        LSTStakerVaultFactory.LSTAddresses memory lstAddresses = factory.createLSTStakerVaultSystem(iBera);
        collector.addLstStakerVault(lstAddresses.vault, adapter);
        vm.stopPrank();

        return lstAddresses.vault;
    }

    function _provideInitialIBeraDeposit() internal {
        uint256 initialDeposit = factory.INITIAL_DEPOSIT();
        vm.deal(safeOwner, initialDeposit * 2); // keep margin for shares conversion rate < 1

        vm.startPrank(safeOwner);
        IInfraredBera(payable(iBera)).mint{ value: initialDeposit * 2 }(safeOwner);
        IERC20(iBera).approve(address(factory), initialDeposit);
        vm.stopPrank();
    }

    function _deployFactory() internal {
        Salt memory salt = Salt({ implementation: 0, proxy: 0 });
        LSTStakerVaultFactoryDeployer deployer = new LSTStakerVaultFactoryDeployer(safeOwner, salt, 0, 0);
        factory = deployer.lstVaultFactory();
    }
}
