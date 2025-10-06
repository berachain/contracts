// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC721Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { WBERA } from "src/WBERA.sol";
import { MockERC20 } from "../mock/token/MockERC20.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { IPOLErrors } from "src/pol/interfaces/IPOLErrors.sol";
import { WBERAStakerVault } from "src/pol/WBERAStakerVault.sol";
import { IWBERAStakerVault } from "src/pol/interfaces/IWBERAStakerVault.sol";
import { WBERAStakerVaultWithdrawalRequest } from "src/pol/WBERAStakerVaultWithdrawalRequest.sol";
import { IWBERAStakerVaultWithdrawalRequest } from "src/pol/interfaces/IWBERAStakerVaultWithdrawalRequest.sol";

contract WBERAStakerVaultTest is Test, Create2Deployer {
    using SafeTransferLib for address;

    // Allow contract to receive ETH
    receive() external payable { }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONTRACTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    WBERAStakerVault public vault;
    WBERA public wbera;
    WBERAStakerVaultWithdrawalRequest public withdrawals721;

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

        // Deploy implementations
        WBERAStakerVault vaultImplementation = new WBERAStakerVault();
        WBERAStakerVaultWithdrawalRequest withdrawalRequestImplementation = new WBERAStakerVaultWithdrawalRequest();

        // Deploy proxy
        vault = WBERAStakerVault(payable(deployProxyWithCreate2(address(vaultImplementation), 0)));
        withdrawals721 = WBERAStakerVaultWithdrawalRequest(
            payable(deployProxyWithCreate2(address(withdrawalRequestImplementation), 0))
        );

        // Initialize
        vault.initialize(governance);
        withdrawals721.initialize(governance, address(vault));
        vm.prank(governance);
        vault.setWithdrawalRequests721(address(withdrawals721));
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

    function _legacyWithdrawWithAllowanceToCharlie() internal returns (uint256 shares) {
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);
        uint256 withdrawAmount = HALF_DEPOSIT;
        uint256 expectedShares = vault.previewWithdraw(withdrawAmount);
        vm.prank(alice);
        vault.approve(bob, expectedShares);
        vm.prank(bob);
        shares = vault.withdraw(withdrawAmount, charlie, alice);
    }

    function _queueWithdrawWithAllowanceToCharlie() internal returns (uint256 requestId, uint256 shares) {
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);
        uint256 withdrawAmount = HALF_DEPOSIT;
        uint256 expectedShares = vault.previewWithdraw(withdrawAmount);
        vm.prank(alice);
        vault.approve(bob, expectedShares);
        vm.prank(bob);
        (shares, requestId) = vault.queueWithdraw(withdrawAmount, charlie, alice);
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

    function _legacyWithdrawWBERA(
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

    function _legacyRedeemWBERA(
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

    function _legacyCompleteWithdrawal(address user, bool isNative) internal {
        vm.prank(user);
        vault.completeWithdrawal(isNative);
    }

    function _legacyAdvanceTimeAndCompleteWithdrawal(address user, bool isNative) internal {
        vm.warp(block.timestamp + WITHDRAWAL_COOLDOWN);
        _legacyCompleteWithdrawal(user, isNative);
    }

    function _legacyAssertWithdrawalRequest(
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

    function _legacyAssertWithdrawalRequestCleared(address user) internal view {
        (uint256 assets, uint256 shares, uint256 requestTime, address owner, address receiver) =
            vault.withdrawalRequests(user);

        assertEq(assets, 0);
        assertEq(shares, 0);
        assertEq(requestTime, 0);
        assertEq(owner, address(0));
        assertEq(receiver, address(0));
    }

    function _queueWithdrawWBERA(
        address user,
        uint256 assets,
        address receiver,
        address owner
    )
        internal
        returns (uint256 shares, uint256 requestId)
    {
        vm.prank(user);
        (shares, requestId) = vault.queueWithdraw(assets, receiver, owner);
    }

    function _queueRedeemWBERA(
        address user,
        uint256 shares,
        address receiver,
        address owner
    )
        internal
        returns (uint256 assets, uint256 requestId)
    {
        vm.prank(user);
        (assets, requestId) = vault.queueRedeem(shares, receiver, owner);
    }

    function _completeWithdrawal(address user, bool isNative, uint256 requestId) internal {
        vm.prank(user);
        vault.completeWithdrawal(isNative, requestId);
    }

    function _advanceTimeAndCompleteWithdrawal(address user, bool isNative, uint256 requestId) internal {
        vm.warp(block.timestamp + WITHDRAWAL_COOLDOWN);
        _completeWithdrawal(user, isNative, requestId);
    }

    function _assertWithdrawalRequest(
        uint256 requestId,
        uint256 expectedAssets,
        uint256 expectedShares,
        uint256 expectedTime,
        address expectedOwner,
        address expectedReceiver
    )
        internal
        view
    {
        IWBERAStakerVaultWithdrawalRequest.WithdrawalRequest memory req = vault.getERC721WithdrawalRequest(requestId);
        assertEq(req.assets, expectedAssets);
        assertEq(req.shares, expectedShares);
        assertEq(req.requestTime, expectedTime);
        assertEq(req.owner, expectedOwner);
        assertEq(req.receiver, expectedReceiver);
    }

    function _assertWithdrawalRequestCleared(uint256 requestId) internal view {
        IWBERAStakerVaultWithdrawalRequest.WithdrawalRequest memory req = vault.getERC721WithdrawalRequest(requestId);
        assertEq(req.assets, 0);
        assertEq(req.shares, 0);
        assertEq(req.requestTime, 0);
        assertEq(req.owner, address(0));
        assertEq(req.receiver, address(0));
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

    function test_receiveFailsIfNotWBERA() public {
        vm.expectRevert(IPOLErrors.UnauthorizedETHTransfer.selector);
        (bool success,) = address(vault).call{ value: 1 ether }("");
        success; // Suppress unused variable warning
    }

    function test_receive() public {
        vm.deal(address(wbera), 1 ether);
        vm.prank(address(wbera));
        (bool success,) = address(vault).call{ value: 1 ether }("");
        assertTrue(success);
        assertEq(address(vault).balance, 1 ether);
    }

    function test_setWithdrawalRequests721FailsIfNotGovernance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), DEFAULT_ADMIN_ROLE
            )
        );
        vault.setWithdrawalRequests721(address(withdrawals721));
    }

    function test_setWithdrawalRequests721FailsIfZeroAddress() public {
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        vault.setWithdrawalRequests721(address(0));
    }

    function test_setWithdrawalRequests721() public {
        address newWithdrawals721 = makeAddr("newWithdrawals721");
        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit IWBERAStakerVault.WithdrawalRequests721Updated(address(withdrawals721), newWithdrawals721);
        vault.setWithdrawalRequests721(newWithdrawals721);
        assertEq(address(vault.withdrawalRequests721()), newWithdrawals721);
    }

    function test_getUserERC721WithdrawalRequestCount() public {
        // initial state
        assertEq(vault.getUserERC721WithdrawalRequestCount(alice), 0);
        // deposit some WBERA
        _depositWBERA(alice, DEPOSIT_AMOUNT * 2, alice);
        _queueWithdrawWBERA(alice, DEPOSIT_AMOUNT, alice, alice);
        assertEq(vault.getUserERC721WithdrawalRequestCount(alice), 1);
        _queueWithdrawWBERA(alice, DEPOSIT_AMOUNT, alice, alice);
        assertEq(vault.getUserERC721WithdrawalRequestCount(alice), 2);
    }

    function test_getERC721WithdrawalRequestIds() public {
        // initial state
        assertEq(vault.getERC721WithdrawalRequestIds(alice).length, 0);
        // deposit some WBERA
        _depositNative(alice, DEPOSIT_AMOUNT * 5, alice);
        // queue some withdrawals
        (, uint256 requestId) = _queueWithdrawWBERA(alice, DEPOSIT_AMOUNT, alice, alice);
        (, uint256 requestId2) = _queueRedeemWBERA(alice, DEPOSIT_AMOUNT, alice, alice);
        (, uint256 requestId3) = _queueRedeemWBERA(alice, DEPOSIT_AMOUNT, alice, alice);

        assertEq(vault.getERC721WithdrawalRequestIds(alice).length, 3);
        uint256[] memory ids = vault.getERC721WithdrawalRequestIds(alice);
        assertEq(ids[0], requestId);
        assertEq(ids[1], requestId2);
        assertEq(ids[2], requestId3);
    }

    function test_getERC721WithdrawalRequestIDs_WithPagination() public {
        // initial state
        assertEq(vault.getERC721WithdrawalRequestIds(alice).length, 0);
        // deposit some WBERA
        _depositNative(alice, DEPOSIT_AMOUNT * 5, alice);
        // queue some withdrawals
        (, uint256 requestId) = _queueWithdrawWBERA(alice, DEPOSIT_AMOUNT, alice, alice);
        (, uint256 requestId2) = _queueWithdrawWBERA(alice, DEPOSIT_AMOUNT, alice, alice);
        (, uint256 requestId3) = _queueWithdrawWBERA(alice, DEPOSIT_AMOUNT, alice, alice);
        (, uint256 requestId4) = _queueWithdrawWBERA(alice, DEPOSIT_AMOUNT, alice, alice);
        (, uint256 requestId5) = _queueWithdrawWBERA(alice, DEPOSIT_AMOUNT, alice, alice);

        assertEq(vault.getERC721WithdrawalRequestIds(alice).length, 5);
        uint256[] memory ids = vault.getERC721WithdrawalRequestIds(alice, 0, 5);
        assertEq(ids[0], requestId);
        assertEq(ids[1], requestId2);
        assertEq(ids[2], requestId3);
        assertEq(ids[3], requestId4);
        assertEq(ids[4], requestId5);
        uint256[] memory ids2 = vault.getERC721WithdrawalRequestIds(alice, 1, 3);
        assertEq(ids2[0], requestId2);
        assertEq(ids2[1], requestId3);
        assertEq(ids2[2], requestId4);
        uint256[] memory ids3 = vault.getERC721WithdrawalRequestIds(alice, 2, 2);
        assertEq(ids3[0], requestId3);
        assertEq(ids3[1], requestId4);
        uint256[] memory ids4 = vault.getERC721WithdrawalRequestIds(alice, 3, 2);
        assertEq(ids4[0], requestId4);
        assertEq(ids4[1], requestId5);
        uint256[] memory ids5 = vault.getERC721WithdrawalRequestIds(alice, 4, 1);
        assertEq(ids5[0], requestId5);
        uint256[] memory ids6 = vault.getERC721WithdrawalRequestIds(alice, 5, 1);
        assertEq(ids6.length, 0); // Should return empty array for out-of-bounds offset
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

    function test_legacyWithdraw() public {
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

        _legacyAssertWithdrawalRequest(alice, withdrawAmount, expectedShares, block.timestamp, alice, alice);
    }

    function test_withdraw() public {
        // Setup: Alice deposits
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);

        // Test: Alice withdraws
        uint256 withdrawAmount = HALF_DEPOSIT;
        uint256 expectedShares = vault.previewWithdraw(withdrawAmount);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IWBERAStakerVault.WithdrawalRequested(alice, alice, alice, withdrawAmount, expectedShares);

        (uint256 shares, uint256 requestId) = vault.queueWithdraw(withdrawAmount, alice, alice);

        assertEq(shares, expectedShares);
        assertEq(vault.balanceOf(alice), DEPOSIT_AMOUNT - expectedShares);
        assertEq(vault.reservedAssets(), withdrawAmount);
        assertEq(vault.totalAssets(), DEPOSIT_AMOUNT - withdrawAmount);

        _assertWithdrawalRequest(requestId, withdrawAmount, expectedShares, block.timestamp, alice, alice);
    }

    function test_legacyWithdrawToOtherReceiver() public {
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);

        uint256 withdrawAmount = HALF_DEPOSIT;
        _legacyWithdrawWBERA(alice, withdrawAmount, bob, alice);

        _legacyAssertWithdrawalRequest(
            alice, withdrawAmount, vault.previewWithdraw(withdrawAmount), block.timestamp, alice, bob
        );
    }

    function test_withdrawToOtherReceiver() public {
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);

        uint256 withdrawAmount = HALF_DEPOSIT;
        (, uint256 requestId) = _queueWithdrawWBERA(alice, withdrawAmount, bob, alice);

        _assertWithdrawalRequest(
            requestId, withdrawAmount, vault.previewWithdraw(withdrawAmount), block.timestamp, alice, bob
        );
    }

    function test_legacyWithdrawWithAllowance() public {
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

        _legacyAssertWithdrawalRequest(bob, withdrawAmount, expectedShares, block.timestamp, alice, charlie);
    }

    function test_legacyWithdrawFailsIfPaused() public {
        // deposit wbera to alice
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);
        _pauseVault();
        // withdraw should revert with paused error
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vault.withdraw(HALF_DEPOSIT, alice, alice);
    }

    function test_legacyRedeemFailsIfPaused() public {
        // deposit wbera to alice
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);
        _pauseVault();
        // redeem should revert with paused error
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vault.redeem(HALF_DEPOSIT, alice, alice);
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

        (uint256 shares, uint256 requestId) = vault.queueWithdraw(withdrawAmount, charlie, alice);

        assertEq(shares, expectedShares);
        assertEq(vault.balanceOf(alice), DEPOSIT_AMOUNT - expectedShares);
        assertEq(vault.reservedAssets(), withdrawAmount);
        assertEq(vault.allowance(alice, bob), 0);

        _assertWithdrawalRequest(requestId, withdrawAmount, expectedShares, block.timestamp, alice, charlie);
    }

    function test_legacyRedeem() public {
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

        _legacyAssertWithdrawalRequest(alice, expectedAssets, redeemShares, block.timestamp, alice, alice);
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

        (uint256 assets, uint256 requestId) = vault.queueRedeem(redeemShares, alice, alice);

        assertEq(assets, expectedAssets);
        assertEq(vault.balanceOf(alice), shares - redeemShares);
        assertEq(vault.reservedAssets(), expectedAssets);
        assertEq(vault.totalAssets(), DEPOSIT_AMOUNT - expectedAssets);

        _assertWithdrawalRequest(requestId, expectedAssets, redeemShares, block.timestamp, alice, alice);
    }

    function test_legacyRedeemToOtherReceiver() public {
        uint256 shares = _depositWBERA(alice, DEPOSIT_AMOUNT, alice);

        uint256 redeemShares = shares / 2;
        _legacyRedeemWBERA(alice, redeemShares, bob, alice);

        _legacyAssertWithdrawalRequest(
            alice, vault.previewRedeem(redeemShares), redeemShares, block.timestamp, alice, bob
        );
    }

    function test_redeemToOtherReceiver() public {
        uint256 shares = _depositWBERA(alice, DEPOSIT_AMOUNT, alice);

        uint256 redeemShares = shares / 2;
        (, uint256 requestId) = _queueRedeemWBERA(alice, redeemShares, bob, alice);

        _assertWithdrawalRequest(
            requestId, vault.previewRedeem(redeemShares), redeemShares, block.timestamp, alice, bob
        );
    }

    function test_legacyRedeemWithAllowance() public {
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

        _legacyAssertWithdrawalRequest(bob, expectedAssets, redeemShares, block.timestamp, alice, charlie);
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

        (uint256 assets, uint256 requestId) = vault.queueRedeem(redeemShares, charlie, alice);

        assertEq(assets, expectedAssets);
        assertEq(vault.balanceOf(alice), aliceShares - redeemShares);
        assertEq(vault.reservedAssets(), expectedAssets);
        assertEq(vault.allowance(alice, bob), 0);

        _assertWithdrawalRequest(requestId, expectedAssets, redeemShares, block.timestamp, alice, charlie);
    }

    function test_legacyWithdrawWithInsufficientAllowance() public {
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
        vault.queueWithdraw(withdrawAmount, charlie, alice);
    }

    function test_legacyCompleteWithdrawalFailsIfPaused() public {
        _pauseVault();
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vault.completeWithdrawal(false);
    }

    function test_completeWithdrawalFailsIfPaused() public {
        _pauseVault();
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vault.completeWithdrawal(false, 0);
    }

    function test_legacyCompleteWithdrawalByDifferentCaller() public {
        // Setup: request queued by Bob on behalf of Alice to Charlie
        _legacyWithdrawWithAllowanceToCharlie();

        // Advance time beyond cooldown
        vm.warp(block.timestamp + WITHDRAWAL_COOLDOWN + 1);

        uint256 charlieWBERABefore = wbera.balanceOf(charlie);
        vm.prank(bob);
        vault.completeWithdrawal(false);
        assertEq(wbera.balanceOf(charlie), charlieWBERABefore + HALF_DEPOSIT);
        assertEq(vault.reservedAssets(), 0);
        _legacyAssertWithdrawalRequestCleared(bob);
    }

    function test_completeWithdrawalByDifferentCaller() public {
        // Setup: request queued by Bob on behalf of Alice to Charlie
        (uint256 requestId,) = _queueWithdrawWithAllowanceToCharlie();

        // Advance time beyond cooldown
        vm.warp(block.timestamp + WITHDRAWAL_COOLDOWN + 1);

        uint256 charlieWBERABefore = wbera.balanceOf(charlie);
        vm.prank(bob);
        vault.completeWithdrawal(false, requestId);
        assertEq(wbera.balanceOf(charlie), charlieWBERABefore + HALF_DEPOSIT);
        assertEq(vault.reservedAssets(), 0);
        _assertWithdrawalRequestCleared(requestId);
    }

    function test_legacyCompleteWithdrawalByDifferentCallerNative() public {
        _legacyWithdrawWithAllowanceToCharlie();
        vm.warp(block.timestamp + WITHDRAWAL_COOLDOWN + 1);
        uint256 charlieETHBefore = charlie.balance;
        uint256 bobETHBefore = bob.balance;
        vm.prank(bob);
        vault.completeWithdrawal(true);
        assertEq(charlie.balance, charlieETHBefore + HALF_DEPOSIT);
        assertEq(bob.balance, bobETHBefore);
        assertEq(vault.reservedAssets(), 0);
        _legacyAssertWithdrawalRequestCleared(bob);
    }

    function test_completeWithdrawalByDifferentCallerNative() public {
        (uint256 requestId,) = _queueWithdrawWithAllowanceToCharlie();
        vm.warp(block.timestamp + WITHDRAWAL_COOLDOWN + 1);
        uint256 charlieETHBefore = charlie.balance;
        uint256 bobETHBefore = bob.balance;
        vm.prank(bob);
        vault.completeWithdrawal(true, requestId);
        assertEq(charlie.balance, charlieETHBefore + HALF_DEPOSIT);
        assertEq(bob.balance, bobETHBefore);
        assertEq(vault.reservedAssets(), 0);
        _assertWithdrawalRequestCleared(requestId);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                COMPLETE WITHDRAWAL TESTS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_legacyCompleteWithdrawal_WBERA() public {
        // Setup: Alice deposits and withdraws
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);

        uint256 withdrawAmount = HALF_DEPOSIT;
        uint256 shares = _legacyWithdrawWBERA(alice, withdrawAmount, alice, alice);

        // Test: Complete withdrawal
        uint256 aliceWBERABefore = wbera.balanceOf(alice);

        vm.warp(block.timestamp + WITHDRAWAL_COOLDOWN);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IWBERAStakerVault.WithdrawalCompleted(alice, alice, alice, withdrawAmount, shares);

        vault.completeWithdrawal(false);

        assertEq(wbera.balanceOf(alice), aliceWBERABefore + withdrawAmount);
        assertEq(vault.reservedAssets(), 0);

        _legacyAssertWithdrawalRequestCleared(alice);
    }

    function test_completeWithdrawal_WBERA() public {
        // Setup: Alice deposits and withdraws
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);

        uint256 withdrawAmount = HALF_DEPOSIT;
        (uint256 shares, uint256 requestId) = _queueWithdrawWBERA(alice, withdrawAmount, alice, alice);

        // Test: Complete withdrawal
        uint256 aliceWBERABefore = wbera.balanceOf(alice);

        vm.warp(block.timestamp + WITHDRAWAL_COOLDOWN);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IWBERAStakerVault.WithdrawalCompleted(alice, alice, alice, withdrawAmount, shares);

        vault.completeWithdrawal(false, requestId);

        assertEq(wbera.balanceOf(alice), aliceWBERABefore + withdrawAmount);
        assertEq(vault.reservedAssets(), 0);

        _assertWithdrawalRequestCleared(requestId);
    }

    function test_legacyCompleteWithdrawal_Native() public {
        // Setup: Alice deposits and withdraws
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);

        uint256 withdrawAmount = HALF_DEPOSIT;
        uint256 shares = _legacyWithdrawWBERA(alice, withdrawAmount, alice, alice);

        // Test: Complete withdrawal as native
        uint256 aliceETHBefore = alice.balance;

        vm.warp(block.timestamp + WITHDRAWAL_COOLDOWN);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IWBERAStakerVault.WithdrawalCompleted(alice, alice, alice, withdrawAmount, shares);

        vault.completeWithdrawal(true);

        assertEq(alice.balance, aliceETHBefore + withdrawAmount);
        assertEq(vault.reservedAssets(), 0);

        _legacyAssertWithdrawalRequestCleared(alice);
    }

    function test_completeWithdrawal_Native() public {
        // Setup: Alice deposits and withdraws
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);

        uint256 withdrawAmount = HALF_DEPOSIT;
        (uint256 shares, uint256 requestId) = _queueWithdrawWBERA(alice, withdrawAmount, alice, alice);

        // Test: Complete withdrawal as native
        uint256 aliceETHBefore = alice.balance;

        vm.warp(block.timestamp + WITHDRAWAL_COOLDOWN);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IWBERAStakerVault.WithdrawalCompleted(alice, alice, alice, withdrawAmount, shares);

        vault.completeWithdrawal(true, requestId);

        assertEq(alice.balance, aliceETHBefore + withdrawAmount);
        assertEq(vault.reservedAssets(), 0);

        _assertWithdrawalRequestCleared(requestId);
    }

    function test_legacyCompleteWithdrawalFailsIfNotRequested() public {
        // Non-existent requestId should revert with ERC721NonexistentToken
        vm.prank(alice);
        vm.expectRevert(IPOLErrors.WithdrawalNotRequested.selector);
        vault.completeWithdrawal(false);
    }

    function test_completeWithdrawalFailsIfNotRequested() public {
        // Non-existent requestId should revert with ERC721NonexistentToken
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 0));
        vault.completeWithdrawal(false, 0);
    }

    function test_legacyCompleteWithdrawalFailsIfNotReady() public {
        // Setup: Alice deposits and withdraws
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);
        _legacyWithdrawWBERA(alice, HALF_DEPOSIT, alice, alice);

        // Test: Try to complete before cooldown
        vm.prank(alice);
        vm.expectRevert(IPOLErrors.WithdrawalNotReady.selector);
        vault.completeWithdrawal(false);
    }

    function test_completeWithdrawalFailsIfNotReady() public {
        // Setup: Alice deposits and withdraws
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);
        (, uint256 requestId) = _queueWithdrawWBERA(alice, HALF_DEPOSIT, alice, alice);

        // Test: Try to complete before cooldown
        vm.prank(alice);
        vm.expectRevert(IPOLErrors.WithdrawalNotReady.selector);
        vault.completeWithdrawal(false, requestId);
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
        (uint256 shares, uint256 requestId) = _queueWithdrawWBERA(alice, 15e18, alice, alice);
        assertApproxEqAbs(shares, 7.5e18, ROUNDING_TOLERANCE);
        assertApproxEqAbs(vault.balanceOf(alice), 2.5e18, ROUNDING_TOLERANCE);

        // Complete withdrawal
        uint256 aliceWBERABefore = wbera.balanceOf(alice);
        _advanceTimeAndCompleteWithdrawal(alice, false, requestId);

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

        (, uint256 requestId) = _queueWithdrawWBERA(alice, withdrawAmount, alice, alice);

        assertEq(vault.reservedAssets(), withdrawAmount);
        assertEq(vault.totalAssets(), depositAmount - withdrawAmount);

        // Complete withdrawal
        uint256 aliceETHBefore = alice.balance;
        _advanceTimeAndCompleteWithdrawal(alice, true, requestId);

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

        // Test: first request
        _queueWithdrawWBERA(alice, HALF_DEPOSIT, alice, alice);

        // Now multiple requests per user are allowed (via NFTs). Ensure second request succeeds and creates another id
        vm.prank(alice);
        (uint256 expectedShares2, uint256 requestId2) = vault.queueWithdraw(QUARTER_DEPOSIT, alice, alice);
        assertEq(expectedShares2, vault.previewWithdraw(QUARTER_DEPOSIT));
        // request exists
        IWBERAStakerVaultWithdrawalRequest.WithdrawalRequest memory req2 = vault.getERC721WithdrawalRequest(requestId2);
        assertEq(req2.assets, QUARTER_DEPOSIT);
    }

    function test_withdrawAfterCompletingPreviousRequest() public {
        // Setup: Alice deposits
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);

        // Test: First withdrawal request
        uint256 firstWithdrawAmount = QUARTER_DEPOSIT;
        (, uint256 requestId1) = _queueWithdrawWBERA(alice, firstWithdrawAmount, alice, alice);

        // Complete first withdrawal
        _advanceTimeAndCompleteWithdrawal(alice, false, requestId1);

        // Now Alice can make another withdrawal request
        uint256 secondWithdrawAmount = QUARTER_DEPOSIT;
        uint256 expectedShares = vault.previewWithdraw(secondWithdrawAmount);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit IWBERAStakerVault.WithdrawalRequested(alice, alice, alice, secondWithdrawAmount, expectedShares);

        (uint256 secondShares, uint256 requestId2) = vault.queueWithdraw(secondWithdrawAmount, alice, alice);

        assertEq(secondShares, expectedShares);
        _assertWithdrawalRequest(requestId2, secondWithdrawAmount, expectedShares, block.timestamp, alice, alice);
    }

    function test_redeemAfterPendingWithdrawRequestReverts() public {
        // Setup: Alice deposits
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);

        // Test: First make a withdraw request
        _queueWithdrawWBERA(alice, HALF_DEPOSIT, alice, alice);

        // Multiple requests per user now allowed; queue another redeem should succeed and mint another NFT
        vm.prank(alice);
        (uint256 expectedAssets2, uint256 requestId2) = vault.queueRedeem(QUARTER_DEPOSIT, alice, alice);
        assertEq(expectedAssets2, vault.previewRedeem(QUARTER_DEPOSIT));
        IWBERAStakerVaultWithdrawalRequest.WithdrawalRequest memory req2 = vault.getERC721WithdrawalRequest(requestId2);
        assertEq(req2.shares, QUARTER_DEPOSIT);
    }

    function test_withdrawAfterPendingRedeemRequestReverts() public {
        // Setup: Alice deposits
        uint256 shares = _depositWBERA(alice, DEPOSIT_AMOUNT, alice);

        // Test: First make a redeem request
        _queueRedeemWBERA(alice, shares / 2, alice, alice);

        // Multiple requests per user now allowed; queue another withdraw should succeed and mint another NFT
        vm.prank(alice);
        (uint256 expectedShares2, uint256 requestId2) = vault.queueWithdraw(QUARTER_DEPOSIT, alice, alice);
        assertEq(expectedShares2, vault.previewWithdraw(QUARTER_DEPOSIT));
        IWBERAStakerVaultWithdrawalRequest.WithdrawalRequest memory req2 = vault.getERC721WithdrawalRequest(requestId2);
        assertEq(req2.assets, QUARTER_DEPOSIT);
    }

    function test_totalAssetsWithReservedAssets() public {
        // Setup: Alice and Bob deposit
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);
        _depositWBERA(bob, DEPOSIT_AMOUNT, bob);

        _assertVaultState(20e18, 20e18, 0);
        assertEq(wbera.balanceOf(address(vault)), 20e18);

        // Test: Alice withdraws 5e18
        (, uint256 requestId) = _queueWithdrawWBERA(alice, 5e18, alice, alice);

        _assertVaultState(15e18, 15e18, 5e18);
        assertEq(wbera.balanceOf(address(vault)), 20e18);

        // After Alice completes withdrawal
        _advanceTimeAndCompleteWithdrawal(alice, false, requestId);

        _assertVaultState(15e18, 15e18, 0);
        assertEq(wbera.balanceOf(address(vault)), 15e18);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   CANCEL WITHDRAWAL TESTS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_cancelQueuedWithdrawal() public {
        // Setup: Alice deposits and queues a withdrawal
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);
        (uint256 originalShares, uint256 requestId) = _queueWithdrawWBERA(alice, DEPOSIT_AMOUNT / 2, alice, alice);

        // Cache state before cancellation
        uint256 aliceSharesBefore = vault.balanceOf(alice);
        uint256 reservedAssetsBefore = vault.reservedAssets();
        uint256 totalSharesBefore = vault.totalSupply();

        uint256 expectedNewShares = vault.previewDeposit(DEPOSIT_AMOUNT / 2);

        // Test: Cancel the withdrawal request
        vm.expectEmit(true, true, true, true);
        emit IWBERAStakerVault.WithdrawalCancelled(
            alice,
            alice,
            DEPOSIT_AMOUNT / 2, // assets
            originalShares, // shares that were burnt during queuing
            expectedNewShares // new shares to be minted
        );
        vm.prank(alice);
        vault.cancelQueuedWithdrawal(requestId);

        // Verify state changes
        assertEq(vault.balanceOf(alice), aliceSharesBefore + expectedNewShares, "Alice should receive new shares");
        assertEq(
            vault.reservedAssets(), reservedAssetsBefore - (DEPOSIT_AMOUNT / 2), "Reserved assets should decrease"
        );
        assertEq(vault.totalSupply(), totalSharesBefore + expectedNewShares, "Total supply should increase");

        // Verify the NFT was burned (should revert with ERC721NonexistentToken)
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, requestId));
        IERC721(address(withdrawals721)).ownerOf(requestId);

        // Verify alice no longer has any withdrawal requests
        assertEq(vault.getUserERC721WithdrawalRequestCount(alice), 0);
    }

    function test_cancelQueuedWithdrawalFailsIfNotOwner() public {
        // Setup: Alice deposits and queues a withdrawal
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);
        (, uint256 requestId) = _queueWithdrawWBERA(alice, DEPOSIT_AMOUNT / 2, alice, alice);

        // Test: Bob tries to cancel Alice's withdrawal request
        vm.expectRevert(IPOLErrors.OnlyNFTOwnerAllowed.selector);
        vm.prank(bob);
        vault.cancelQueuedWithdrawal(requestId);
    }

    function test_cancelQueuedWithdrawalFailsIfPaused() public {
        // Setup: Alice deposits and queues a withdrawal
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);
        (, uint256 requestId) = _queueWithdrawWBERA(alice, DEPOSIT_AMOUNT / 2, alice, alice);

        // Pause the vault
        vm.prank(pauser);
        vault.pause();

        // Test: Try to cancel when paused
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vm.prank(alice);
        vault.cancelQueuedWithdrawal(requestId);
    }

    function test_cancelQueuedWithdrawalFailsIfRequestDoesNotExist() public {
        // Test: Try to cancel a non-existent request
        uint256 nonExistentRequestId = 999;

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, nonExistentRequestId));
        vm.prank(alice);
        vault.cancelQueuedWithdrawal(nonExistentRequestId);
    }

    function test_cancelQueuedWithdrawalMultipleRequests() public {
        // Setup: Alice deposits and queues multiple withdrawals
        _depositWBERA(alice, DEPOSIT_AMOUNT * 3, alice);
        (, uint256 requestId1) = _queueWithdrawWBERA(alice, DEPOSIT_AMOUNT / 6, alice, alice);
        (, uint256 requestId2) = _queueWithdrawWBERA(alice, DEPOSIT_AMOUNT, alice, alice);
        (, uint256 requestId3) = _queueWithdrawWBERA(alice, DEPOSIT_AMOUNT / 6, alice, alice);

        // Verify alice has 3 requests
        assertEq(vault.getERC721WithdrawalRequestIds(alice).length, 3);

        // Cache state before cancellation
        uint256 aliceSharesBefore = vault.balanceOf(alice);
        uint256 reservedAssetsBefore = vault.reservedAssets();

        // Test: Cancel the middle request
        vm.prank(alice);
        vault.cancelQueuedWithdrawal(requestId2);

        // Verify state changes
        uint256 expectedNewShares = vault.previewDeposit(DEPOSIT_AMOUNT);
        assertEq(vault.balanceOf(alice), aliceSharesBefore + expectedNewShares, "Alice should receive new shares");
        assertEq(vault.reservedAssets(), reservedAssetsBefore - (DEPOSIT_AMOUNT), "Reserved assets should decrease");

        // Verify alice now has 2 requests (the other two should still exist)
        assertEq(vault.getERC721WithdrawalRequestIds(alice).length, 2);

        // Verify the remaining requests are still valid
        uint256[] memory remainingIds = vault.getERC721WithdrawalRequestIds(alice);
        assertEq(remainingIds[0], requestId1);
        assertEq(remainingIds[1], requestId3);
    }

    function test_cancelQueuedWithdrawalAfterAutoCompounding() public {
        // Setup: Alice deposits
        _depositWBERA(alice, DEPOSIT_AMOUNT, alice);

        // Queue withdrawal at initial 1:1 ratio
        (uint256 sharesBurnt, uint256 requestId) = _queueWithdrawWBERA(alice, DEPOSIT_AMOUNT / 2, alice, alice);

        // Simulate auto-compounding (increases asset value)
        _simulateAutoCompounding(DEPOSIT_AMOUNT / 2); // Adds 5e18 assets

        // Now the vault has more assets, so previewDeposit will return fewer shares for same asset amount
        uint256 aliceSharesBefore = vault.balanceOf(alice);
        uint256 expectedNewShares = vault.previewDeposit(DEPOSIT_AMOUNT / 2);

        // Cancel the withdrawal - should mint new shares based on current ratio
        vm.prank(alice);
        vault.cancelQueuedWithdrawal(requestId);

        // sharesBurnt should be greater than expectedNewShares because of auto-compounding
        assertGt(sharesBurnt, expectedNewShares);

        // Verify alice got the correct amount of new shares based on current exchange rate
        assertEq(
            vault.balanceOf(alice),
            aliceSharesBefore + expectedNewShares,
            "Alice should receive new shares at current rate"
        );

        // Verify the new shares are worth the original asset amount
        uint256 newSharesValue = vault.convertToAssets(expectedNewShares);
        assertApproxEqAbs(
            newSharesValue, DEPOSIT_AMOUNT / 2, ROUNDING_TOLERANCE, "New shares should be worth original asset amount"
        );
    }

    function test_queueWithdrawReentrancyAttackPrevented() public {
        // Deploy the malicious contract
        MaliciousReentrantContract attacker = new MaliciousReentrantContract(vault, wbera);

        // Fund the attacker contract with WBERA
        vm.deal(address(attacker), 2 ether);
        vm.prank(address(attacker));
        wbera.deposit{ value: 2 ether }();

        // Transfer WBERA to attacker
        vm.prank(address(attacker));
        wbera.transfer(address(attacker), 2 ether);

        // Approve vault to spend attacker's WBERA
        vm.prank(address(attacker));
        wbera.approve(address(vault), 2 ether);

        // Attacker deposits initial amount
        vm.prank(address(attacker));
        vault.deposit(1 ether, address(attacker));

        // Capture initial state
        uint256 initialReservedAssets = vault.reservedAssets();
        uint256 initialAttackerShares = vault.balanceOf(address(attacker));

        // Execute the reentrancy attack - should fail
        vm.prank(address(attacker));
        vm.expectRevert(); // Should revert with ReentrancyGuardReentrantCall
        attacker.attack();

        // Verify the attack was prevented
        uint256 finalReservedAssets = vault.reservedAssets();
        uint256 finalAttackerShares = vault.balanceOf(address(attacker));
        uint256 attackerRequestCount = vault.getUserERC721WithdrawalRequestCount(address(attacker));

        // State should be unchanged since the attack was prevented
        assertEq(finalReservedAssets, initialReservedAssets, "Reserved assets should be unchanged");
        assertEq(finalAttackerShares, initialAttackerShares, "Attacker shares should be unchanged");
        assertEq(attackerRequestCount, 0, "No withdrawal requests should be created");
    }

    function test_queueRedeemReentrancyAttackPrevented() public {
        // Deploy the malicious contract for queueRedeem attack
        MaliciousReentrantContract attacker = new MaliciousReentrantContract(vault, wbera);

        // Fund the attacker contract with WBERA
        vm.deal(address(attacker), 2 ether);
        vm.prank(address(attacker));
        wbera.deposit{ value: 2 ether }();

        // Transfer WBERA to attacker
        vm.prank(address(attacker));
        wbera.transfer(address(attacker), 2 ether);

        // Approve vault to spend attacker's WBERA
        vm.prank(address(attacker));
        wbera.approve(address(vault), 2 ether);

        // Attacker deposits initial amount
        vm.prank(address(attacker));
        vault.deposit(1 ether, address(attacker));

        // Capture initial state
        uint256 initialReservedAssets = vault.reservedAssets();
        uint256 initialAttackerShares = vault.balanceOf(address(attacker));

        // Execute the reentrancy attack via queueRedeem - should now fail
        vm.prank(address(attacker));
        vm.expectRevert(); // Should revert with ReentrancyGuardReentrantCall
        attacker.attackViaQueueRedeem();

        // Verify the attack was prevented
        uint256 finalReservedAssets = vault.reservedAssets();
        uint256 finalAttackerShares = vault.balanceOf(address(attacker));
        uint256 attackerRequestCount = vault.getUserERC721WithdrawalRequestCount(address(attacker));

        // State should be unchanged since the attack was prevented
        assertEq(finalReservedAssets, initialReservedAssets, "Reserved assets should be unchanged");
        assertEq(finalAttackerShares, initialAttackerShares, "Attacker shares should be unchanged");
        assertEq(attackerRequestCount, 0, "No withdrawal requests should be created");
    }
}

// Malicious contract that exploits reentrancy in queueWithdraw and queueRedeem
contract MaliciousReentrantContract is IERC721Receiver {
    WBERAStakerVault private vault;
    WBERA private wbera;
    bool private attacking;
    uint256 private attackCount;
    bool private useQueueRedeem;

    constructor(WBERAStakerVault _vault, WBERA _wbera) {
        vault = _vault;
        wbera = _wbera;
    }

    function attack() external {
        require(!attacking, "Already attacking");
        attacking = true;
        attackCount = 0;
        useQueueRedeem = false;

        // Start the reentrancy attack via queueWithdraw
        vault.queueWithdraw(0.5 ether, address(this), address(this));
    }

    function attackViaQueueRedeem() external {
        require(!attacking, "Already attacking");
        attacking = true;
        attackCount = 0;
        useQueueRedeem = true;

        // Start the reentrancy attack via queueRedeem
        vault.queueRedeem(0.5 ether, address(this), address(this));
    }

    // This function will be called when the NFT is minted to this contract
    function onERC721Received(
        address, /* operator */
        address, /* from */
        uint256, /* tokenId */
        bytes calldata /* data */
    )
        external
        returns (bytes4)
    {
        // Reentrancy attack: call the appropriate function again if we haven't attacked enough times
        if (attacking && attackCount < 2) {
            attackCount++;
            if (useQueueRedeem) {
                vault.queueRedeem(0.25 ether, address(this), address(this));
            } else {
                vault.queueWithdraw(0.25 ether, address(this), address(this));
            }
        }

        return this.onERC721Received.selector;
    }

    // Fallback to receive ETH
    receive() external payable { }
}
