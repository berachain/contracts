// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { WETH } from "solady/src/tokens/WETH.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { IPOLErrors } from "src/pol/interfaces/IPOLErrors.sol";
import { WBERAStakerVault } from "src/pol/WBERAStakerVault.sol";
import { IWBERAStakerVault } from "src/pol/interfaces/IWBERAStakerVault.sol";
import { WBERA } from "src/WBERA.sol";
import { MockERC20 } from "../mock/token/MockERC20.sol";

contract WBERAStakerVaultTest is Test, Create2Deployer {
    using SafeTransferLib for address;

    // Allow contract to receive ETH
    receive() external payable { }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONTRACTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    WBERAStakerVault public vault;
    WBERA public wbera;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       TEST ACCOUNTS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public governance = makeAddr("governance");
    address public manager = makeAddr("manager");
    address public pauser = makeAddr("pauser");

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    uint256 public constant WITHDRAWAL_COOLDOWN = 7 days;
    uint256 public constant INITIAL_BALANCE = 100e18;
    uint256 public constant DEPOSIT_AMOUNT = 10e18;
    uint256 public constant HALF_DEPOSIT = DEPOSIT_AMOUNT / 2;
    uint256 public constant QUARTER_DEPOSIT = DEPOSIT_AMOUNT / 4;
    uint256 public constant REWARD_AMOUNT = 5e18;
    uint256 public constant ROUNDING_TOLERANCE = 1;
    uint256 public constant FUZZ_ROUNDING_TOLERANCE = 100;

    // Role constants
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           SETUP                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function setUp() public {
        _deployContracts();
        _setupRoles();
        _setupUserBalances();
    }

    function _deployContracts() internal {
        // Deploy WBERA mock at the correct address
        wbera = WBERA(payable(0x6969696969696969696969696969696969696969));
        deployCodeTo("WBERA.sol", address(wbera));

        // Deploy vault implementation
        WBERAStakerVault implementation = new WBERAStakerVault();

        // Deploy proxy
        vault = WBERAStakerVault(payable(deployProxyWithCreate2(address(implementation), 0)));

        // Initialize vault
        vault.initialize(governance);
    }

    function _setupRoles() internal {
        vm.startPrank(governance);
        vault.grantRole(MANAGER_ROLE, manager);
        vm.stopPrank();

        vm.startPrank(manager);
        vault.grantRole(PAUSER_ROLE, pauser);
        vm.stopPrank();
    }

    function _setupUserBalances() internal {
        // Setup initial ETH balances
        vm.deal(alice, INITIAL_BALANCE);
        vm.deal(bob, INITIAL_BALANCE);
        vm.deal(charlie, INITIAL_BALANCE);

        // Setup WBERA balances
        vm.deal(address(wbera), INITIAL_BALANCE);
        vm.prank(address(wbera));
        wbera.deposit{ value: INITIAL_BALANCE }();

        // Distribute WBERA to users
        vm.startPrank(address(wbera));
        wbera.transfer(alice, INITIAL_BALANCE / 3);
        wbera.transfer(bob, INITIAL_BALANCE / 3);
        wbera.transfer(charlie, INITIAL_BALANCE / 3);
        vm.stopPrank();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      HELPER FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _expectAccessControlRevert(address user, bytes32 role) internal {
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, role));
    }

    function _simulateAutoCompounding(uint256 amount) internal {
        // Simulate auto-compounding by sending WBERA directly to vault
        vm.deal(address(vault), amount);
        vm.prank(address(vault));
        wbera.deposit{ value: amount }();
    }

    function _depositWBERA(address user, uint256 amount, address receiver) internal returns (uint256 shares) {
        vm.startPrank(user);
        wbera.approve(address(vault), amount);
        shares = vault.deposit(amount, receiver);
        vm.stopPrank();
    }

    function _depositNative(address user, uint256 amount, address receiver) internal returns (uint256 shares) {
        vm.prank(user);
        shares = vault.depositNative{ value: amount }(amount, receiver);
    }

    function _withdrawWBERA(
        address user,
        uint256 assets,
        address receiver,
        address owner
    )
        internal
        returns (uint256 shares)
    {
        vm.prank(user);
        shares = vault.withdraw(assets, receiver, owner);
    }

    function _redeemShares(
        address user,
        uint256 shares,
        address receiver,
        address owner
    )
        internal
        returns (uint256 assets)
    {
        vm.prank(user);
        assets = vault.redeem(shares, receiver, owner);
    }

    function _completeWithdrawal(address user, bool isNative) internal {
        vm.prank(user);
        vault.completeWithdrawal(isNative);
    }

    function _advanceTimeAndCompleteWithdrawal(address user, bool isNative) internal {
        vm.warp(block.timestamp + WITHDRAWAL_COOLDOWN);
        _completeWithdrawal(user, isNative);
    }

    function _assertWithdrawalRequest(
        address user,
        uint256 expectedAssets,
        uint256 expectedShares,
        uint256 expectedTime,
        address expectedOwner,
        address expectedReceiver
    )
        internal
        view
    {
        (uint256 assets, uint256 shares, uint256 requestTime, address owner, address receiver) =
            vault.withdrawalRequests(user);

        assertEq(assets, expectedAssets);
        assertEq(shares, expectedShares);
        assertEq(requestTime, expectedTime);
        assertEq(owner, expectedOwner);
        assertEq(receiver, expectedReceiver);
    }

    function _assertWithdrawalRequestCleared(address user) internal view {
        (uint256 assets,,,,) = vault.withdrawalRequests(user);
        assertEq(assets, 0);
    }

    function _assertVaultState(
        uint256 expectedTotalAssets,
        uint256 expectedTotalSupply,
        uint256 expectedReservedAssets
    )
        internal
        view
    {
        assertEq(vault.totalAssets(), expectedTotalAssets);
        assertEq(vault.totalSupply(), expectedTotalSupply);
        assertEq(vault.reservedAssets(), expectedReservedAssets);
    }

    function _pauseVault() internal {
        vm.prank(pauser);
        vault.pause();
    }

    function _unpauseVault() internal {
        vm.prank(manager);
        vault.unpause();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    INITIALIZATION TESTS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_initialization() public view {
        assertEq(vault.name(), "POL Staked WBERA");
        assertEq(vault.symbol(), "sWBERA");
        assertEq(vault.decimals(), 18);
        assertEq(vault.asset(), address(wbera));
        assertEq(vault.WITHDRAWAL_COOLDOWN(), WITHDRAWAL_COOLDOWN);
        assertTrue(vault.hasRole(DEFAULT_ADMIN_ROLE, governance));
    }

    function test_initializationWithZeroAddress() public {
        WBERAStakerVault implementation = new WBERAStakerVault();
        WBERAStakerVault newVault = WBERAStakerVault(payable(deployProxyWithCreate2(address(implementation), 0)));

        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        newVault.initialize(address(0));
    }

    function test_cannotInitializeTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vault.initialize(governance);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      ERC4626 DEPOSIT TESTS                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_deposit() public {
        uint256 expectedShares = vault.previewDeposit(DEPOSIT_AMOUNT);
        uint256 aliceWBERABefore = wbera.balanceOf(alice);

        vm.startPrank(alice);
        wbera.approve(address(vault), DEPOSIT_AMOUNT);

        vm.expectEmit(true, true, true, true);
        emit IERC4626.Deposit(alice, alice, DEPOSIT_AMOUNT, expectedShares);

        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, alice);
        vm.stopPrank();

        assertEq(shares, expectedShares);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalSupply(), shares);
        assertEq(vault.totalAssets(), DEPOSIT_AMOUNT);
        assertEq(wbera.balanceOf(alice), aliceWBERABefore - DEPOSIT_AMOUNT);
        assertEq(wbera.balanceOf(address(vault)), DEPOSIT_AMOUNT);
    }

    function test_depositToOtherReceiver() public {
        uint256 shares = _depositWBERA(alice, DEPOSIT_AMOUNT, bob);

        assertEq(vault.balanceOf(bob), shares);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_depositFailsWhenPaused() public {
        _pauseVault();

        vm.startPrank(alice);
        wbera.approve(address(vault), DEPOSIT_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vault.deposit(DEPOSIT_AMOUNT, alice);
        vm.stopPrank();
    }

    function test_mint() public {
        uint256 sharesToMint = 10e18;
        uint256 assetsNeeded = vault.previewMint(sharesToMint);

        vm.startPrank(alice);
        wbera.approve(address(vault), assetsNeeded);

        vm.expectEmit(true, true, true, true);
        emit IERC4626.Deposit(alice, alice, assetsNeeded, sharesToMint);

        uint256 assets = vault.mint(sharesToMint, alice);
        vm.stopPrank();

        assertEq(assets, assetsNeeded);
        assertEq(vault.balanceOf(alice), sharesToMint);
        assertEq(vault.totalSupply(), sharesToMint);
    }

    function test_mintFailsWhenPaused() public {
        _pauseVault();

        vm.startPrank(alice);
        wbera.approve(address(vault), DEPOSIT_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vault.mint(10e18, alice);
        vm.stopPrank();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    NATIVE DEPOSIT TESTS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_depositNative() public {
        uint256 aliceETHBefore = alice.balance;
        uint256 expectedShares = vault.previewDeposit(DEPOSIT_AMOUNT);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IERC4626.Deposit(alice, alice, DEPOSIT_AMOUNT, expectedShares);

        uint256 shares = vault.depositNative{ value: DEPOSIT_AMOUNT }(DEPOSIT_AMOUNT, alice);

        assertEq(shares, expectedShares);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalSupply(), shares);
        assertEq(vault.totalAssets(), DEPOSIT_AMOUNT);
        assertEq(alice.balance, aliceETHBefore - DEPOSIT_AMOUNT);
        assertEq(wbera.balanceOf(address(vault)), DEPOSIT_AMOUNT);
    }

    function test_depositNativeToOtherReceiver() public {
        uint256 shares = _depositNative(alice, DEPOSIT_AMOUNT, bob);

        assertEq(vault.balanceOf(bob), shares);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_depositNativeFailsWithMismatchedValue() public {
        vm.prank(alice);
        vm.expectRevert(IPOLErrors.InsufficientNativeValue.selector);
        vault.depositNative{ value: DEPOSIT_AMOUNT - 1 }(DEPOSIT_AMOUNT, alice);
    }

    function test_depositNativeFailsWhenPaused() public {
        _pauseVault();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vault.depositNative{ value: DEPOSIT_AMOUNT }(DEPOSIT_AMOUNT, alice);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    WITHDRAWAL TESTS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_withdraw() public {
        // Setup: Alice deposits
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);

        // Test: Alice withdraws
        uint256 withdrawAmount = HALF_DEPOSIT;
        uint256 expectedShares = vault.previewWithdraw(withdrawAmount);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IWBERAStakerVault.WithdrawalRequested(alice, alice, alice, withdrawAmount, expectedShares);

        uint256 shares = vault.withdraw(withdrawAmount, alice, alice);

        assertEq(shares, expectedShares);
        assertEq(vault.balanceOf(alice), DEPOSIT_AMOUNT - expectedShares);
        assertEq(vault.reservedAssets(), withdrawAmount);
        assertEq(vault.totalAssets(), DEPOSIT_AMOUNT - withdrawAmount);

        _assertWithdrawalRequest(alice, withdrawAmount, expectedShares, block.timestamp, alice, alice);
    }

    function test_withdrawToOtherReceiver() public {
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);

        uint256 withdrawAmount = HALF_DEPOSIT;
        _withdrawWBERA(alice, withdrawAmount, bob, alice);

        _assertWithdrawalRequest(
            alice, withdrawAmount, vault.previewWithdraw(withdrawAmount), block.timestamp, alice, bob
        );
    }

    function test_withdrawWithAllowance() public {
        // Setup: Alice deposits and approves Bob
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);

        uint256 withdrawAmount = HALF_DEPOSIT;
        uint256 expectedShares = vault.previewWithdraw(withdrawAmount);

        vm.prank(alice);
        vault.approve(bob, expectedShares);

        assertEq(vault.allowance(alice, bob), expectedShares);

        // Test: Bob withdraws on behalf of Alice
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit IWBERAStakerVault.WithdrawalRequested(bob, charlie, alice, withdrawAmount, expectedShares);

        uint256 shares = vault.withdraw(withdrawAmount, charlie, alice);

        assertEq(shares, expectedShares);
        assertEq(vault.balanceOf(alice), DEPOSIT_AMOUNT - expectedShares);
        assertEq(vault.reservedAssets(), withdrawAmount);
        assertEq(vault.allowance(alice, bob), 0);

        _assertWithdrawalRequest(bob, withdrawAmount, expectedShares, block.timestamp, alice, charlie);
    }

    function test_redeem() public {
        // Setup: Alice deposits
        uint256 shares = _depositWBERA(alice, DEPOSIT_AMOUNT, alice);

        // Test: Alice redeems
        uint256 redeemShares = shares / 2;
        uint256 expectedAssets = vault.previewRedeem(redeemShares);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IWBERAStakerVault.WithdrawalRequested(alice, alice, alice, expectedAssets, redeemShares);

        uint256 assets = vault.redeem(redeemShares, alice, alice);

        assertEq(assets, expectedAssets);
        assertEq(vault.balanceOf(alice), shares - redeemShares);
        assertEq(vault.reservedAssets(), expectedAssets);
        assertEq(vault.totalAssets(), DEPOSIT_AMOUNT - expectedAssets);

        _assertWithdrawalRequest(alice, expectedAssets, redeemShares, block.timestamp, alice, alice);
    }

    function test_redeemToOtherReceiver() public {
        uint256 shares = _depositWBERA(alice, DEPOSIT_AMOUNT, alice);

        uint256 redeemShares = shares / 2;
        _redeemShares(alice, redeemShares, bob, alice);

        _assertWithdrawalRequest(alice, vault.previewRedeem(redeemShares), redeemShares, block.timestamp, alice, bob);
    }

    function test_redeemWithAllowance() public {
        // Setup: Alice deposits and approves Bob
        uint256 aliceShares = _depositWBERA(alice, DEPOSIT_AMOUNT, alice);

        uint256 redeemShares = aliceShares / 2;

        vm.prank(alice);
        vault.approve(bob, redeemShares);

        assertEq(vault.allowance(alice, bob), redeemShares);

        // Test: Bob redeems on behalf of Alice
        uint256 expectedAssets = vault.previewRedeem(redeemShares);

        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit IWBERAStakerVault.WithdrawalRequested(bob, charlie, alice, expectedAssets, redeemShares);

        uint256 assets = vault.redeem(redeemShares, charlie, alice);

        assertEq(assets, expectedAssets);
        assertEq(vault.balanceOf(alice), aliceShares - redeemShares);
        assertEq(vault.reservedAssets(), expectedAssets);
        assertEq(vault.allowance(alice, bob), 0);

        _assertWithdrawalRequest(bob, expectedAssets, redeemShares, block.timestamp, alice, charlie);
    }

    function test_withdrawWithInsufficientAllowance() public {
        // Setup: Alice deposits and approves Bob small amount
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);

        uint256 smallAllowance = 1e18;
        vm.prank(alice);
        vault.approve(bob, smallAllowance);

        // Test: Bob tries to withdraw more than allowed
        uint256 withdrawAmount = HALF_DEPOSIT;

        vm.prank(bob);
        vm.expectRevert(); // Should revert with insufficient allowance
        vault.withdraw(withdrawAmount, charlie, alice);
    }

    function test_completeWithdrawalFailsIfPaused() public {
        _pauseVault();
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vault.completeWithdrawal(false);
    }

    function test_completeWithdrawalByDifferentCaller() public {
        // Setup: Alice deposits and Bob withdraws on behalf of Alice
        test_withdrawWithAllowance();

        // Test: Bob completes the withdrawal
        uint256 charlieWBERABefore = wbera.balanceOf(charlie);

        vm.warp(block.timestamp + WITHDRAWAL_COOLDOWN);

        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit IWBERAStakerVault.WithdrawalCompleted(bob, charlie, alice, HALF_DEPOSIT, HALF_DEPOSIT);
        vault.completeWithdrawal(false);

        assertEq(wbera.balanceOf(charlie), charlieWBERABefore + HALF_DEPOSIT);
        assertEq(vault.reservedAssets(), 0);

        _assertWithdrawalRequestCleared(bob);
    }

    function test_completeWithdrawalByDifferentCallerNative() public {
        // Setup: Alice deposits and Bob withdraws on behalf of Alice to Charlie
        test_withdrawWithAllowance();

        // Test: Bob completes the withdrawal as native - Charlie should receive ETH, not Bob
        uint256 charlieETHBefore = charlie.balance;
        uint256 bobETHBefore = bob.balance;

        vm.warp(block.timestamp + WITHDRAWAL_COOLDOWN);

        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit IWBERAStakerVault.WithdrawalCompleted(bob, charlie, alice, HALF_DEPOSIT, HALF_DEPOSIT);
        vault.completeWithdrawal(true); // Native withdrawal

        // Charlie (receiver) should get the ETH, not Bob (caller)
        assertEq(charlie.balance, charlieETHBefore + HALF_DEPOSIT);
        assertEq(bob.balance, bobETHBefore); // Bob's balance unchanged
        assertEq(vault.reservedAssets(), 0);

        _assertWithdrawalRequestCleared(bob);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                COMPLETE WITHDRAWAL TESTS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_completeWithdrawal_WBERA() public {
        // Setup: Alice deposits and withdraws
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);

        uint256 withdrawAmount = HALF_DEPOSIT;
        uint256 shares = _withdrawWBERA(alice, withdrawAmount, alice, alice);

        // Test: Complete withdrawal
        uint256 aliceWBERABefore = wbera.balanceOf(alice);

        vm.warp(block.timestamp + WITHDRAWAL_COOLDOWN);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IWBERAStakerVault.WithdrawalCompleted(alice, alice, alice, withdrawAmount, shares);

        vault.completeWithdrawal(false);

        assertEq(wbera.balanceOf(alice), aliceWBERABefore + withdrawAmount);
        assertEq(vault.reservedAssets(), 0);

        _assertWithdrawalRequestCleared(alice);
    }

    function test_completeWithdrawal_Native() public {
        // Setup: Alice deposits and withdraws
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);

        uint256 withdrawAmount = HALF_DEPOSIT;
        uint256 shares = _withdrawWBERA(alice, withdrawAmount, alice, alice);

        // Test: Complete withdrawal as native
        uint256 aliceETHBefore = alice.balance;

        vm.warp(block.timestamp + WITHDRAWAL_COOLDOWN);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IWBERAStakerVault.WithdrawalCompleted(alice, alice, alice, withdrawAmount, shares);

        vault.completeWithdrawal(true);

        assertEq(alice.balance, aliceETHBefore + withdrawAmount);
        assertEq(vault.reservedAssets(), 0);

        _assertWithdrawalRequestCleared(alice);
    }

    function test_completeWithdrawalFailsIfNotRequested() public {
        vm.prank(alice);
        vm.expectRevert(IPOLErrors.WithdrawalNotRequested.selector);
        vault.completeWithdrawal(false);
    }

    function test_completeWithdrawalFailsIfNotReady() public {
        // Setup: Alice deposits and withdraws
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);
        _withdrawWBERA(alice, HALF_DEPOSIT, alice, alice);

        // Test: Try to complete before cooldown
        vm.prank(alice);
        vm.expectRevert(IPOLErrors.WithdrawalNotReady.selector);
        vault.completeWithdrawal(false);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                 AUTO-COMPOUNDING TESTS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_autoCompounding() public {
        // Setup: Alice and Bob deposit
        uint256 aliceShares = _depositWBERA(alice, DEPOSIT_AMOUNT, alice);
        uint256 bobShares = _depositWBERA(bob, DEPOSIT_AMOUNT, bob);

        // Initial state: 20 WBERA total, 20 shares total, 1:1 ratio
        _assertVaultState(20e18, 20e18, 0);
        assertEq(vault.convertToAssets(1e18), 1e18);

        // Test: Simulate auto-compounding
        _simulateAutoCompounding(10e18);

        // Now: 30 WBERA total, 20 shares total, 1.5:1 ratio
        _assertVaultState(30e18, 20e18, 0);
        assertApproxEqAbs(vault.convertToAssets(1e18), 1.5e18, ROUNDING_TOLERANCE);

        // Alice's and Bob's shares are now worth ~15 WBERA each
        assertApproxEqAbs(vault.convertToAssets(aliceShares), 15e18, ROUNDING_TOLERANCE);
        assertApproxEqAbs(vault.convertToAssets(bobShares), 15e18, ROUNDING_TOLERANCE);

        // Charlie deposits 15 WBERA and should get 10 shares
        uint256 charlieShares = _depositWBERA(charlie, 15e18, charlie);

        assertEq(charlieShares, 10e18);
        _assertVaultState(45e18, 30e18, 0);
    }

    function test_autoCompoundingWithWithdrawal() public {
        // Setup: Alice deposits and auto-compounding occurs
        uint256 aliceShares = _depositWBERA(alice, DEPOSIT_AMOUNT, alice);
        _simulateAutoCompounding(10e18);

        // Alice's shares are now worth ~20 WBERA
        assertApproxEqAbs(vault.convertToAssets(aliceShares), 20e18, ROUNDING_TOLERANCE);

        // Test: Alice withdraws 15 WBERA
        uint256 shares = _withdrawWBERA(alice, 15e18, alice, alice);
        assertApproxEqAbs(shares, 7.5e18, ROUNDING_TOLERANCE);
        assertApproxEqAbs(vault.balanceOf(alice), 2.5e18, ROUNDING_TOLERANCE);

        // Complete withdrawal
        uint256 aliceWBERABefore = wbera.balanceOf(alice);
        _advanceTimeAndCompleteWithdrawal(alice, false);

        assertEq(wbera.balanceOf(alice), aliceWBERABefore + 15e18);
        assertApproxEqAbs(vault.convertToAssets(vault.balanceOf(alice)), 5e18, 2);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    ADMIN FUNCTION TESTS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_recoverERC20() public {
        MockERC20 testToken = new MockERC20();
        uint256 amount = 1000e18;
        testToken.mint(address(vault), amount);

        uint256 governanceBalanceBefore = testToken.balanceOf(governance);

        vm.prank(governance);
        vault.recoverERC20(address(testToken), amount);

        assertEq(testToken.balanceOf(governance), governanceBalanceBefore + amount);
        assertEq(testToken.balanceOf(address(vault)), 0);
    }

    function test_recoverERC20FailsIfNotAdmin() public {
        MockERC20 testToken = new MockERC20();

        vm.prank(alice);
        _expectAccessControlRevert(alice, DEFAULT_ADMIN_ROLE);
        vault.recoverERC20(address(testToken), 1000e18);
    }

    function test_recoverERC20FailsIfWBERA() public {
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.CannotRecoverStakingToken.selector);
        vault.recoverERC20(address(wbera), 1000e18);
    }

    function test_pause() public {
        vm.prank(pauser);
        vault.pause();
        assertTrue(vault.paused());
    }

    function test_pauseFailsIfNotPauser() public {
        vm.prank(alice);
        _expectAccessControlRevert(alice, PAUSER_ROLE);
        vault.pause();
    }

    function test_unpause() public {
        _pauseVault();

        vm.prank(manager);
        vault.unpause();
        assertFalse(vault.paused());
    }

    function test_unpauseFailsIfNotManager() public {
        _pauseVault();

        vm.prank(alice);
        _expectAccessControlRevert(alice, MANAGER_ROLE);
        vault.unpause();
    }

    function test_authorizeUpgradeFailsIfNotAdmin() public {
        WBERAStakerVault newImplementation = new WBERAStakerVault();

        vm.prank(alice);
        _expectAccessControlRevert(alice, DEFAULT_ADMIN_ROLE);
        vault.upgradeToAndCall(address(newImplementation), "");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     FUZZ TESTS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function testFuzz_depositAndWithdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 1e18, 50e18);
        withdrawAmount = bound(withdrawAmount, 1e18, depositAmount);

        // Setup
        vm.deal(alice, depositAmount);

        // Test: Deposit and withdraw
        uint256 shares = _depositNative(alice, depositAmount, alice);

        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalAssets(), depositAmount);

        _withdrawWBERA(alice, withdrawAmount, alice, alice);

        assertEq(vault.reservedAssets(), withdrawAmount);
        assertEq(vault.totalAssets(), depositAmount - withdrawAmount);

        // Complete withdrawal
        uint256 aliceETHBefore = alice.balance;
        _advanceTimeAndCompleteWithdrawal(alice, true);

        assertEq(alice.balance, aliceETHBefore + withdrawAmount);
        assertEq(vault.reservedAssets(), 0);
    }

    function testFuzz_autoCompounding(uint256 initialDeposit, uint256 rewardAmount) public {
        initialDeposit = bound(initialDeposit, 1e18, 50e18);
        rewardAmount = bound(rewardAmount, 1e18, 50e18);

        // Setup
        vm.deal(alice, initialDeposit);

        // Test: Initial deposit
        uint256 shares = _depositNative(alice, initialDeposit, alice);

        uint256 initialShareValue = vault.convertToAssets(shares);
        assertEq(initialShareValue, initialDeposit);

        // Auto-compound
        _simulateAutoCompounding(rewardAmount);

        uint256 newShareValue = vault.convertToAssets(shares);
        assertApproxEqAbs(newShareValue, initialDeposit + rewardAmount, FUZZ_ROUNDING_TOLERANCE);

        // Verify total assets increased
        assertEq(vault.totalAssets(), initialDeposit + rewardAmount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    EDGE CASE TESTS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_multipleWithdrawalRequestsFromSameUserReverts() public {
        // Setup: Alice deposits
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);

        // Test: First withdrawal request should succeed
        _withdrawWBERA(alice, HALF_DEPOSIT, alice, alice);

        // Second withdrawal request should revert
        vm.prank(alice);
        vm.expectRevert(IPOLErrors.WithdrawalAlreadyRequested.selector);
        vault.withdraw(QUARTER_DEPOSIT, alice, alice);
    }

    function test_withdrawAfterCompletingPreviousRequest() public {
        // Setup: Alice deposits
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);

        // Test: First withdrawal request
        uint256 firstWithdrawAmount = QUARTER_DEPOSIT;
        _withdrawWBERA(alice, firstWithdrawAmount, alice, alice);

        // Complete first withdrawal
        _advanceTimeAndCompleteWithdrawal(alice, false);

        // Now Alice can make another withdrawal request
        uint256 secondWithdrawAmount = QUARTER_DEPOSIT;
        uint256 expectedShares = vault.previewWithdraw(secondWithdrawAmount);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IWBERAStakerVault.WithdrawalRequested(alice, alice, alice, secondWithdrawAmount, expectedShares);

        uint256 secondShares = vault.withdraw(secondWithdrawAmount, alice, alice);

        assertEq(secondShares, expectedShares);
        _assertWithdrawalRequest(alice, secondWithdrawAmount, expectedShares, block.timestamp, alice, alice);
    }

    function test_redeemAfterPendingWithdrawRequestReverts() public {
        // Setup: Alice deposits
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);

        // Test: First make a withdraw request
        _withdrawWBERA(alice, HALF_DEPOSIT, alice, alice);

        // Then try to redeem - should revert
        vm.prank(alice);
        vm.expectRevert(IPOLErrors.WithdrawalAlreadyRequested.selector);
        vault.redeem(QUARTER_DEPOSIT, alice, alice);
    }

    function test_withdrawAfterPendingRedeemRequestReverts() public {
        // Setup: Alice deposits
        uint256 shares = _depositWBERA(alice, DEPOSIT_AMOUNT, alice);

        // Test: First make a redeem request
        _redeemShares(alice, shares / 2, alice, alice);

        // Then try to withdraw - should revert
        vm.prank(alice);
        vm.expectRevert(IPOLErrors.WithdrawalAlreadyRequested.selector);
        vault.withdraw(QUARTER_DEPOSIT, alice, alice);
    }

    function test_totalAssetsWithReservedAssets() public {
        // Setup: Alice and Bob deposit
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);
        _depositWBERA(bob, DEPOSIT_AMOUNT, bob);

        _assertVaultState(20e18, 20e18, 0);
        assertEq(wbera.balanceOf(address(vault)), 20e18);

        // Test: Alice withdraws 5e18
        _withdrawWBERA(alice, 5e18, alice, alice);

        _assertVaultState(15e18, 15e18, 5e18);
        assertEq(wbera.balanceOf(address(vault)), 20e18);

        // After Alice completes withdrawal
        _advanceTimeAndCompleteWithdrawal(alice, false);

        _assertVaultState(15e18, 15e18, 0);
        assertEq(wbera.balanceOf(address(vault)), 15e18);
    }
}
