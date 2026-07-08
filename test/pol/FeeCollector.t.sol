// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { LibClone } from "solady/src/utils/LibClone.sol";
import { ERC20 } from "solady/src/tokens/ERC20.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { MockERC20 } from "@mock/token/MockERC20.sol";
import { FeeCollector } from "src/pol/FeeCollector.sol";
import { IFeeCollector, IPOLErrors } from "src/pol/interfaces/IFeeCollector.sol";
import { POLTest } from "./POL.t.sol";

contract FeeCollectorTest is POLTest {
    MockERC20 internal feeToken;

    bytes32 internal defaultAdminRole;
    bytes32 internal managerRole;
    bytes32 internal pauserRole;

    address internal manager = makeAddr("manager");
    address internal pauser = makeAddr("pauser");

    uint256 internal constant PRECISION = 1e18; // need vault PRECISION to bound amounts for `notifyRewardAmount()`

    function setUp() public override {
        super.setUp();

        feeToken = new MockERC20();
        deal(address(feeToken), address(this), 100 ether);
        deal(address(wbera), address(this), 100 ether);

        defaultAdminRole = feeCollector.DEFAULT_ADMIN_ROLE();
        managerRole = feeCollector.MANAGER_ROLE();
        pauserRole = feeCollector.PAUSER_ROLE();

        vm.prank(governance);
        feeCollector.grantRole(managerRole, manager);

        vm.prank(manager);
        feeCollector.grantRole(pauserRole, pauser);
    }

    function test_GovernanceIsOwner() public view {
        assert(feeCollector.hasRole(defaultAdminRole, governance));
    }

    function test_Initialize_FailsIfGovernanceAddrIsZero() public {
        FeeCollector feeCollectorNew = _deployNewFeeCollector();
        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        feeCollectorNew.initialize(address(0), address(wbera), address(bgtStaker), PAYOUT_AMOUNT);
    }

    function test_Initialize_FailsIfPayoutTokenAddrIsZero() public {
        FeeCollector feeCollectorNew = _deployNewFeeCollector();
        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        feeCollectorNew.initialize(governance, address(0), address(bgtStaker), PAYOUT_AMOUNT);
    }

    function test_Initialize_FailsIfRewardReceiverAddrIsZero() public {
        FeeCollector feeCollectorNew = _deployNewFeeCollector();
        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        feeCollectorNew.initialize(governance, address(wbera), address(0), PAYOUT_AMOUNT);
    }

    function test_Initialize_FailsIfPayoutAmountIsZero() public {
        FeeCollector feeCollectorNew = _deployNewFeeCollector();
        vm.expectRevert(IPOLErrors.PayoutAmountIsZero.selector);
        feeCollectorNew.initialize(governance, address(wbera), address(bgtStaker), 0);
    }

    function test_QueuePayoutAmountChange_FailsIfNotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), defaultAdminRole
            )
        );
        feeCollector.queuePayoutAmountChange(2 ether);
    }

    function test_QueuePayoutAmountChange_FailsIfZero() public {
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.PayoutAmountIsZero.selector);
        feeCollector.queuePayoutAmountChange(0);
    }

    function test_QueuePayoutAmountChange() public {
        testFuzz_QueuePayoutAmountChange(1 ether);
    }

    function testFuzz_QueuePayoutAmountChange(uint256 newPayoutAmount) public {
        newPayoutAmount = _bound(newPayoutAmount, 1, type(uint256).max);
        uint256 oldPayoutAmount = feeCollector.payoutAmount();
        vm.prank(governance);
        vm.expectEmit();
        emit IFeeCollector.QueuedPayoutAmount(newPayoutAmount, oldPayoutAmount);
        feeCollector.queuePayoutAmountChange(newPayoutAmount);
        assertEq(feeCollector.queuedPayoutAmount(), newPayoutAmount);
        // Assert payoutAmount is not updated yet
        assertEq(feeCollector.payoutAmount(), oldPayoutAmount);
    }

    function testFuzz_PayoutAmountDoesntChangeIfClaimFails(uint256 newPayoutAmount) public {
        newPayoutAmount = _bound(newPayoutAmount, 1, type(uint256).max);
        _addFees();
        testFuzz_QueuePayoutAmountChange(newPayoutAmount);
        uint256 oldPayoutAmount = feeCollector.payoutAmount();
        address[] memory feeTokens = new address[](1);
        feeTokens[0] = address(feeToken);
        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        feeCollector.claimFees(address(this), feeTokens);

        assertEq(feeCollector.payoutAmount(), oldPayoutAmount);
    }

    function testFuzz_PayoutAmountChangeAfterClaim(uint256 newPayoutAmount) public {
        newPayoutAmount = _bound(newPayoutAmount, 1, type(uint256).max);
        _addFees();
        testFuzz_QueuePayoutAmountChange(newPayoutAmount);
        uint256 oldPayoutAmount = feeCollector.payoutAmount();
        wbera.approve(address(feeCollector), oldPayoutAmount);
        address[] memory feeTokens = new address[](1);
        feeTokens[0] = address(feeToken);
        vm.expectEmit();
        emit IFeeCollector.FeesClaimed(address(this), address(this), address(feeToken), 10 ether);
        emit IFeeCollector.PayoutAmountSet(PAYOUT_AMOUNT, newPayoutAmount);
        feeCollector.claimFees(address(this), feeTokens);

        assertEq(feeToken.balanceOf(address(feeCollector)), 0);
        assertEq(feeToken.balanceOf(address(this)), 100 ether);
        assertEq(wbera.balanceOf(address(bgtStaker)), oldPayoutAmount);
        assertEq(feeCollector.payoutAmount(), newPayoutAmount);
    }

    function test_ClaimFees_FailsIfNotApproved() public {
        _addFees();
        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        address[] memory feeTokens = new address[](1);
        feeTokens[0] = address(feeToken);
        feeCollector.claimFees(address(this), feeTokens);
    }

    function test_ClaimFees_FailsIfPaused() public {
        _addFees();
        test_Pause();
        wbera.approve(address(feeCollector), 100 ether);
        address[] memory feeTokens = new address[](1);
        feeTokens[0] = address(feeToken);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        feeCollector.claimFees(address(this), feeTokens);
    }

    function test_ClaimFees() public {
        _addFees();
        wbera.approve(address(feeCollector), 100 ether);
        address[] memory feeTokens = new address[](1);
        feeTokens[0] = address(feeToken);
        vm.expectEmit();
        emit IFeeCollector.FeesClaimed(address(this), address(this), address(feeToken), 10 ether);
        feeCollector.claimFees(address(this), feeTokens);
        assertEq(feeToken.balanceOf(address(feeCollector)), 0);
        assertEq(feeToken.balanceOf(address(this)), 100 ether);
        assertEq(wbera.balanceOf(address(bgtStaker)), 1 ether);
    }

    function test_Donate_FailsIfAmountLessThanPayoutAmount() public {
        testFuzz_Donate_FailsIfAmountLessThanPayoutAmount(0.5 ether);
    }

    function testFuzz_Donate_FailsIfAmountLessThanPayoutAmount(uint256 amount) public {
        amount = _bound(amount, 0, PAYOUT_AMOUNT - 1);
        vm.expectRevert(IPOLErrors.DonateAmountLessThanPayoutAmount.selector);
        feeCollector.donate(amount);
    }

    function test_Donate_FailsIfNotApproved() public {
        testFuzz_Donate_FailsIfNotApproved(10 ether);
    }

    function testFuzz_Donate_FailsIfNotApproved(uint256 amount) public {
        amount = _bound(amount, PAYOUT_AMOUNT, type(uint256).max);
        wbera.approve(address(feeCollector), amount - 1);
        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        feeCollector.donate(amount);
    }

    function testFuzz_Donate_FailsIfPaused(uint256 amount) public {
        test_Pause();
        amount = _bound(amount, PAYOUT_AMOUNT, type(uint256).max);
        deal(address(wbera), address(this), amount);
        wbera.approve(address(feeCollector), amount);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        feeCollector.donate(amount);
    }

    function test_Donate() public {
        testFuzz_Donate(10 ether);
    }

    function testFuzz_Donate(uint256 amount) public {
        amount = _bound(amount, PAYOUT_AMOUNT, type(uint256).max / PRECISION);
        deal(address(wbera), address(this), amount);
        wbera.approve(address(feeCollector), amount);
        vm.expectEmit();
        emit IFeeCollector.PayoutDonated(address(this), amount);
        feeCollector.donate(amount);
        assertEq(wbera.balanceOf(address(this)), 0);
        assertEq(wbera.balanceOf(address(bgtStaker)), amount);
        assertEq(wbera.balanceOf(address(feeCollector)), 0);
    }

    function _addFees() internal {
        feeToken.transfer(address(feeCollector), 10 ether);
        assertEq(feeToken.balanceOf(address(feeCollector)), 10 ether);
    }

    function _deployNewFeeCollector() internal returns (FeeCollector feeCollectorNew) {
        feeCollectorNew = FeeCollector(LibClone.deployERC1967(address(new FeeCollector())));
    }

    function test_Pause_FailIfNotPauser() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), pauserRole)
        );
        feeCollector.pause();
    }

    function test_Pause() public {
        vm.prank(pauser);
        feeCollector.pause();
        assertTrue(feeCollector.paused());
    }

    function test_Unpause_FailIfNotManager() public {
        test_Pause();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), managerRole
            )
        );
        feeCollector.unpause();
    }

    function test_Unpause() public {
        vm.prank(pauser);
        feeCollector.pause();
        vm.prank(manager);
        feeCollector.unpause();
        assertFalse(feeCollector.paused());
    }

    function test_GrantPauserRoleFailWithGovernance() public {
        address newVaultPauser = makeAddr("newVaultPauser");
        vm.prank(governance);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, governance, managerRole)
        );
        feeCollector.grantRole(pauserRole, newVaultPauser);
    }

    function test_GrantPauserRole() public {
        address newVaultPauser = makeAddr("newVaultPauser");
        vm.prank(manager);
        feeCollector.grantRole(pauserRole, newVaultPauser);
        assert(feeCollector.hasRole(pauserRole, newVaultPauser));
    }

    function test_RecoverERC20() public {
        _addFees();
        address[] memory tokens = new address[](1);
        tokens[0] = address(feeToken);
        vm.prank(governance);
        feeCollector.recoverERC20(tokens);
        assertEq(feeToken.balanceOf(governance), 10 ether);
        assertEq(feeToken.balanceOf(address(feeCollector)), 0);
    }

    function test_RecoverERC20_FailIfNotOwner() public {
        _addFees();
        address[] memory tokens = new address[](1);
        tokens[0] = address(feeToken);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), defaultAdminRole
            )
        );
        feeCollector.recoverERC20(tokens);
    }
}
