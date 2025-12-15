// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { IPOLErrors } from "src/pol/interfaces/IPOLErrors.sol";
import { WBERAStakerVault } from "src/pol/WBERAStakerVault.sol";
import { WBERAStakerVaultWithdrawalRequest } from "src/pol/WBERAStakerVaultWithdrawalRequest.sol";
import { POLAddressBook } from "script/pol/POLAddresses.sol";
import { ChainType } from "script/base/Chain.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract WBERAStakerVaultUpgradeTest is Test, Create2Deployer, POLAddressBook {
    IERC20 public WBERA;
    WBERAStakerVault public vault;
    WBERAStakerVaultWithdrawalRequest public withdrawals721;

    address safeOwner = 0xD13948F99525FB271809F45c268D72a3C00a568D;

    // Get a user with an open withdrawal to test the compatibility
    address public alice = 0x0877c1e5b0BafFF1A79A4F39e1333326a195dFf2;

    // Get a user with some sWBERA shares and no withdrawal initiated
    address public bob = 0x65Cf927ad9b319Ad5404E67412704ac89a88953c;

    address public wBERAHolder = 0xf6Feb2C0ce85bE768B380C96297BB49d42fE5670;

    uint256 forkBlock = 8_708_746;

    constructor() POLAddressBook(ChainType.Mainnet) {
        WBERA = IERC20(_polAddresses.wbera);
        vault = WBERAStakerVault(payable(_polAddresses.wberaStakerVault));
    }

    function setUp() public virtual {
        vm.createSelectFork("berachain");
        vm.rollFork(forkBlock);
    }

    function test_Fork() public view {
        assertEq(block.chainid, 80_094);
        assertEq(block.number, forkBlock);
        assertEq(block.timestamp, 1_754_409_603);
    }

    function test_Upgrade() public {
        // WBERAStakerVaultWithdrawalRequest
        WBERAStakerVaultWithdrawalRequest withdrawals721Impl = new WBERAStakerVaultWithdrawalRequest();
        withdrawals721 = WBERAStakerVaultWithdrawalRequest(deployProxyWithCreate2(address(withdrawals721Impl), 0));

        // Initialize
        withdrawals721.initialize(safeOwner, address(vault));

        // Upgrade WBERAStakerVault
        address newVaultImpl = deployWithCreate2(0, type(WBERAStakerVault).creationCode);
        vm.prank(safeOwner);
        vault.upgradeToAndCall(
            newVaultImpl,
            abi.encodeWithSelector(WBERAStakerVault.setWithdrawalRequests721.selector, address(withdrawals721))
        );

        assertEq(address(withdrawals721), address(vault.withdrawalRequests721()));
    }

    function test_completeOldWithdrawalsFailsIfCooldownNotPassed() public {
        test_Upgrade();
        vm.prank(alice);
        vm.expectRevert(IPOLErrors.WithdrawalNotReady.selector);
        vault.completeWithdrawal(false);
    }

    function test_coolDownPeriodSameAsOld() public {
        // check cool down period before upgrade
        uint256 coolDownPeriodBefore = vault.WITHDRAWAL_COOLDOWN();
        // upgrade
        test_Upgrade();
        assertEq(vault.WITHDRAWAL_COOLDOWN(), coolDownPeriodBefore);
        // cool down period should also be same in ERC721 contract
        assertEq(withdrawals721.WITHDRAWAL_COOLDOWN(), coolDownPeriodBefore);
    }

    /// @dev Test old withdrawal requests still work for completion.
    function test_completeOldWithdrawals() public {
        test_Upgrade();

        uint256 sWBERAbalanceBefore = vault.balanceOf(alice);
        uint256 wBERAbalanceBefore = WBERA.balanceOf(alice);
        uint256 reservedAssetsBefore = vault.reservedAssets();
        (uint256 assets,, uint256 time,,) = vault.withdrawalRequests(alice);

        vm.warp(time + vault.WITHDRAWAL_COOLDOWN());
        vm.prank(alice);
        vault.completeWithdrawal(false);

        assertEq(vault.balanceOf(alice), sWBERAbalanceBefore);
        assertEq(WBERA.balanceOf(alice), wBERAbalanceBefore + assets);
        assertEq(vault.reservedAssets(), reservedAssetsBefore - assets);
    }

    function test_completeOldWithdrawal_WithNative() public {
        test_Upgrade();
        vm.prank(alice);
        uint256 sWBERAbalanceBefore = vault.balanceOf(alice);
        uint256 wBERAbalanceBefore = WBERA.balanceOf(alice);
        uint256 nativeBalanceBefore = alice.balance;
        uint256 reservedAssetsBefore = vault.reservedAssets();
        (uint256 assets,, uint256 time,,) = vault.withdrawalRequests(alice);

        vm.warp(time + vault.WITHDRAWAL_COOLDOWN());
        vm.prank(alice);
        vault.completeWithdrawal(true);

        assertEq(vault.balanceOf(alice), sWBERAbalanceBefore);
        // wbera should be unchanged because it was native
        assertEq(WBERA.balanceOf(alice), wBERAbalanceBefore);
        assertEq(alice.balance, nativeBalanceBefore + assets);
        assertEq(vault.reservedAssets(), reservedAssetsBefore - assets);
    }

    /// @dev Test queueRedeem with request NFT
    function test_queueRedeemRequestNFT() public {
        test_Upgrade();

        uint256 sWBERAbalanceBefore = vault.balanceOf(bob);
        uint256 wBERAbalanceBefore = WBERA.balanceOf(bob);
        uint256 reservedAssetsBefore = vault.reservedAssets();

        vm.prank(bob);
        (uint256 assets, uint256 requestId) = vault.queueRedeem(sWBERAbalanceBefore, bob, bob);
        assertEq(assets, vault.previewRedeem(sWBERAbalanceBefore));
        assertEq(requestId, 0);
        assertEq(vault.balanceOf(bob), 0);
        assertEq(vault.reservedAssets(), reservedAssetsBefore + assets);

        vm.warp(block.timestamp + vault.WITHDRAWAL_COOLDOWN());
        vm.prank(bob);
        vault.completeWithdrawal(false, requestId);
        assertEq(vault.balanceOf(bob), 0);
        assertEq(WBERA.balanceOf(bob), wBERAbalanceBefore + assets);
        assertEq(vault.reservedAssets(), reservedAssetsBefore);
    }

    function test_queueWithdrawRequestNFT() public {
        test_Upgrade();

        uint256 bobBERABefore = bob.balance;
        uint256 sWBERAbalanceBefore = vault.balanceOf(bob);
        uint256 wBERAbalanceBefore = WBERA.balanceOf(bob);
        uint256 reservedAssetsBefore = vault.reservedAssets();

        uint256 assets = vault.previewRedeem(sWBERAbalanceBefore);

        vm.prank(bob);
        (uint256 shares, uint256 requestId) = vault.queueWithdraw(assets, bob, bob);
        assertEq(shares, vault.previewWithdraw(assets));
        assertEq(requestId, 0);
        assertEq(vault.balanceOf(bob), 0);
        assertEq(vault.reservedAssets(), reservedAssetsBefore + assets);

        vm.warp(block.timestamp + vault.WITHDRAWAL_COOLDOWN());
        vm.prank(bob);
        vault.completeWithdrawal(true, requestId);
        assertEq(vault.balanceOf(bob), 0);
        assertEq(WBERA.balanceOf(bob), wBERAbalanceBefore);
        assertEq(bob.balance, bobBERABefore + assets);
        assertEq(vault.reservedAssets(), reservedAssetsBefore);
    }

    function test_cancelQueuedRedeemSameExchangeRate() public {
        test_Upgrade();
        uint256 sWBERAbalanceBefore = vault.balanceOf(bob);
        uint256 reservedAssetsBefore = vault.reservedAssets();

        vm.prank(bob);
        (uint256 assets, uint256 requestId) = vault.queueRedeem(sWBERAbalanceBefore, bob, bob);
        assertEq(assets, vault.previewRedeem(sWBERAbalanceBefore));
        assertEq(requestId, 0);
        assertEq(vault.balanceOf(bob), 0);
        assertEq(vault.reservedAssets(), reservedAssetsBefore + assets);

        // cancel the withdrawal request at same exchange rate
        // at same exchange rate, the user should get back the same number of shares
        vm.prank(bob);
        vault.cancelQueuedWithdrawal(requestId);
        assertApproxEqAbs(vault.balanceOf(bob), sWBERAbalanceBefore, 1);
        assertEq(vault.reservedAssets(), reservedAssetsBefore);
    }

    function test_cancelQueuedWithdrawalDifferentExchangeRate() public {
        test_Upgrade();

        uint256 sWBERAbalanceBefore = vault.balanceOf(bob);
        uint256 reservedAssetsBefore = vault.reservedAssets();

        vm.prank(bob);
        (uint256 assets, uint256 requestId) = vault.queueRedeem(sWBERAbalanceBefore, bob, bob);
        assertEq(assets, vault.previewRedeem(sWBERAbalanceBefore));
        assertEq(requestId, 0);
        assertEq(vault.balanceOf(bob), 0);
        assertEq(vault.reservedAssets(), reservedAssetsBefore + assets);

        // send some WBERA to the vault to increase the exchange rate
        vm.prank(wBERAHolder);
        WBERA.transfer(address(vault), 1000 ether);

        // cancel the withdrawal request at increased exchange rate
        // at increased exchange rate, the user should get back less shares
        vm.prank(bob);
        vault.cancelQueuedWithdrawal(requestId);
        assertLt(vault.balanceOf(bob), sWBERAbalanceBefore);
        assertEq(vault.reservedAssets(), reservedAssetsBefore);
    }
}
