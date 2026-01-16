// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ERC20 } from "solady/src/tokens/ERC20.sol";
import { IERC1967 } from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { DistributorTest } from "./Distributor.t.sol";
import { MockERC20 } from "../mock/token/MockERC20.sol";
import { Salt } from "src/base/Salt.sol";
import { BGTIncentiveFeeDeployer } from "src/pol/BGTIncentiveFeeDeployer.sol";
import { BGTIncentiveFeeCollector } from "src/pol/BGTIncentiveFeeCollector.sol";
import { IBGTIncentiveFeeCollector, IPOLErrors } from "src/pol/interfaces/IBGTIncentiveFeeCollector.sol";

import { WBERAStakerVault } from "src/pol/WBERAStakerVault.sol";
import { MockLST } from "test/mock/pol/lst/MockLST.sol";
import { MockLSTStakerVault } from "test/mock/pol/lst/MockLSTStakerVault.sol";
import { MockLSTAdapter } from "test/mock/pol/lst/MockLSTAdapter.sol";
import { IStakerVault } from "src/pol/interfaces/lst/IStakerVault.sol";

contract MockNon18DecimalsERC20 is ERC20 {
    constructor() ERC20() { }

    function name() public pure override returns (string memory) {
        return "Non18Decimals";
    }

    function symbol() public pure override returns (string memory) {
        return "N18D";
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract BGTIncentiveFeeCollectorTest is DistributorTest {
    Salt public BGT_INCENTIVE_FEE_DEPLOYER_SALT = Salt({ implementation: 0, proxy: 1 });
    Salt public WBERA_STAKER_VAULT_SALT = Salt({ implementation: 0, proxy: 1 });
    Salt public BGT_INCENTIVE_FEE_COLLECTOR_SALT = Salt({ implementation: 0, proxy: 1 });

    bytes32 internal pauserRole;
    address internal pauser = makeAddr("pauser");

    MockERC20 internal feeToken1;
    MockERC20 internal feeToken2;
    address internal wberaStakerVault;
    BGTIncentiveFeeCollector public incentiveFeeCollector;

    function setUp() public virtual override {
        // deploy pol
        super.setUp();

        // Deal WBERA tokens to this contract for the deployer's initial deposit
        deal(address(wbera), address(this), 10 ether);

        address bgtIncentiveFeeDeployer = getCreate2AddressWithArgs(
            BGT_INCENTIVE_FEE_DEPLOYER_SALT.implementation,
            type(BGTIncentiveFeeDeployer).creationCode,
            abi.encode(
                governance, address(this), PAYOUT_AMOUNT, WBERA_STAKER_VAULT_SALT, BGT_INCENTIVE_FEE_COLLECTOR_SALT
            )
        );
        wbera.approve(bgtIncentiveFeeDeployer, 10 ether);

        // deploy incentive fee collector
        _deployBGTIncentiveFee();

        // deploy fee tokens
        feeToken1 = new MockERC20();
        feeToken2 = new MockERC20();
        deal(address(wbera), address(this), 1 ether);

        pauserRole = incentiveFeeCollector.PAUSER_ROLE();
        vm.prank(governance);
        incentiveFeeCollector.grantRole(managerRole, manager);
        vm.prank(manager);
        incentiveFeeCollector.grantRole(pauserRole, pauser);
    }

    function test_deployment() public view {
        // verify proxy is initialized correctly
        assertEq(incentiveFeeCollector.payoutAmount(), 1e18);
        assertEq(incentiveFeeCollector.queuedPayoutAmount(), 0);
        assertEq(incentiveFeeCollector.hasRole(incentiveFeeCollector.DEFAULT_ADMIN_ROLE(), governance), true);

        // Role Admin should be MANAGER_ROLE for PAUSER_ROLE, ADD_LIQUIDITY_BOT, BOOST_VALIDATOR_BOT
        assertEq(
            incentiveFeeCollector.getRoleAdmin(incentiveFeeCollector.PAUSER_ROLE()),
            incentiveFeeCollector.MANAGER_ROLE()
        );
    }

    function test_QueuePayoutAmountChange_FailsWhenZero() public {
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.PayoutAmountIsZero.selector);
        incentiveFeeCollector.queuePayoutAmountChange(0);
    }

    function test_QueuePayoutAmountChange_FailsWhenNotGovernance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), defaultAdminRole
            )
        );
        incentiveFeeCollector.queuePayoutAmountChange(1e18);
    }

    function test_QueuePayoutAmount() public {
        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit IBGTIncentiveFeeCollector.QueuedPayoutAmount(2e18, 1e18);
        incentiveFeeCollector.queuePayoutAmountChange(2e18);
        assertEq(incentiveFeeCollector.queuedPayoutAmount(), 2e18);
    }

    function test_ClaimFees_FailsIfPaused() public {
        vm.prank(pauser);
        incentiveFeeCollector.pause();
        address[] memory feeTokens = new address[](2);
        feeTokens[0] = address(feeToken1);
        feeTokens[1] = address(feeToken2);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        incentiveFeeCollector.claimFees(address(this), feeTokens);
    }

    function test_ClaimsFees_FailsIfNotApproved() public {
        _mintTokensToIncentiveFeeCollector();
        // approve wbera token for incentive fee collector less than payout amount
        wbera.approve(address(incentiveFeeCollector), PAYOUT_AMOUNT - 1);

        address[] memory feeTokens = new address[](2);
        feeTokens[0] = address(feeToken1);
        feeTokens[1] = address(feeToken2);
        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        incentiveFeeCollector.claimFees(address(this), feeTokens);
    }

    function test_ClaimFees() public {
        uint256 preWberaStakerVaultBalance = wbera.balanceOf(address(wberaStakerVault));
        _claimFees();

        // post claim check
        assertEq(feeToken1.balanceOf(address(incentiveFeeCollector)), 0);
        assertEq(feeToken2.balanceOf(address(incentiveFeeCollector)), 0);

        assertEq(feeToken1.balanceOf(address(this)), 1e18);
        assertEq(feeToken2.balanceOf(address(this)), 1e18);
        // wbera balance should be 0 for this contract and for incentive fee collector
        assertEq(wbera.balanceOf(address(this)), 0);
        assertEq(wbera.balanceOf(address(incentiveFeeCollector)), 0);
        // wbera balance of wberaStakerVault should increase by payout amount.
        assertEq(wbera.balanceOf(address(wberaStakerVault)), PAYOUT_AMOUNT + preWberaStakerVaultBalance);
    }

    function test_ClaimFees_ActivateQueuedPayoutAmount() public {
        vm.prank(governance);
        incentiveFeeCollector.queuePayoutAmountChange(2e18);

        // claim fees should activate queued payout amount
        test_ClaimFees();
        assertEq(incentiveFeeCollector.payoutAmount(), 2e18);
        assertEq(incentiveFeeCollector.queuedPayoutAmount(), 0);
    }

    function test_Pause_FailIfNotPauser() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), pauserRole)
        );
        incentiveFeeCollector.pause();
    }

    function test_Pause() public {
        vm.prank(pauser);
        incentiveFeeCollector.pause();
        assertTrue(incentiveFeeCollector.paused());
    }

    function test_Unpause_FailIfNotManager() public {
        test_Pause();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), managerRole
            )
        );
        incentiveFeeCollector.unpause();
    }

    function test_Unpause() public {
        vm.prank(pauser);
        incentiveFeeCollector.pause();
        vm.prank(manager);
        incentiveFeeCollector.unpause();
        assertFalse(incentiveFeeCollector.paused());
    }

    function test_GrantPauserRoleFailWithGovernance() public {
        address newPauser = makeAddr("newPauser");
        vm.prank(governance);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, governance, managerRole)
        );
        incentiveFeeCollector.grantRole(pauserRole, newPauser);
    }

    function test_GrantPauserRole() public {
        address newPauser = makeAddr("newPauser");
        vm.prank(manager);
        incentiveFeeCollector.grantRole(pauserRole, newPauser);
        assert(incentiveFeeCollector.hasRole(pauserRole, newPauser));
    }

    function test_Upgrade_FailsIfNotGovernance() public {
        address newImplementation = address(new BGTIncentiveFeeCollector());
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), defaultAdminRole
            )
        );
        incentiveFeeCollector.upgradeToAndCall(newImplementation, "");
    }

    function test_Upgrade() public {
        address newImplementation = address(new BGTIncentiveFeeCollector());
        vm.prank(governance);
        incentiveFeeCollector.upgradeToAndCall(newImplementation, "");
        assertEq(
            vm.load(address(incentiveFeeCollector), ERC1967Utils.IMPLEMENTATION_SLOT),
            bytes32(uint256(uint160(newImplementation)))
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       HELPER FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _mintTokensToIncentiveFeeCollector() internal {
        feeToken1.mint(address(incentiveFeeCollector), 1e18);
        feeToken2.mint(address(incentiveFeeCollector), 1e18);
    }

    // Helper function to deploy the incentive fee collector.
    function _deployBGTIncentiveFee() internal {
        BGTIncentiveFeeDeployer bgtIncentiveFeeDeployer = BGTIncentiveFeeDeployer(
            deployWithCreate2WithArgs(
                BGT_INCENTIVE_FEE_DEPLOYER_SALT.implementation,
                type(BGTIncentiveFeeDeployer).creationCode,
                abi.encode(
                    governance, address(this), PAYOUT_AMOUNT, WBERA_STAKER_VAULT_SALT, BGT_INCENTIVE_FEE_COLLECTOR_SALT
                )
            )
        );
        incentiveFeeCollector = bgtIncentiveFeeDeployer.bgtIncentiveFeeCollector();
        wberaStakerVault = address(bgtIncentiveFeeDeployer.wberaStakerVault());
    }

    function _claimFees() internal {
        _mintTokensToIncentiveFeeCollector();
        // approve wbera token for incentive fee collector
        wbera.approve(address(incentiveFeeCollector), PAYOUT_AMOUNT);

        address[] memory feeTokens = new address[](2);
        feeTokens[0] = address(feeToken1);
        feeTokens[1] = address(feeToken2);
        vm.expectEmit(true, true, true, true);
        emit IBGTIncentiveFeeCollector.IncentiveFeeTokenClaimed(address(this), address(this), address(feeToken1), 1e18);
        emit IBGTIncentiveFeeCollector.IncentiveFeeTokenClaimed(address(this), address(this), address(feeToken2), 1e18);
        emit IBGTIncentiveFeeCollector.IncentiveFeesClaimed(address(this), address(this));
        incentiveFeeCollector.claimFees(address(this), feeTokens);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*.                           LST                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _helper_AddLstStakerVault(address lstStakerVault, address lstAdapter) internal {
        vm.assume(lstStakerVault != address(0));
        vm.assume(lstAdapter != address(0));
        uint256 len = incentiveFeeCollector.lstStakerVaultsLength();

        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit IBGTIncentiveFeeCollector.LstStakerVaultAdded(lstStakerVault, lstAdapter);
        incentiveFeeCollector.addLstStakerVault(lstStakerVault, lstAdapter);

        assertEq(incentiveFeeCollector.lstAdapters(lstStakerVault), lstAdapter);
        assertEq(incentiveFeeCollector.lstStakerVaultsLength(), len + 1);
        assertEq(incentiveFeeCollector.lstStakerVaults(len), lstStakerVault);
    }

    function test_AddLstStakerVault() public {
        address lstStakerVault = address(new MockLSTStakerVault(address(new MockLST())));
        address lstAdapter = makeAddr("lstAdapter");

        _helper_AddLstStakerVault(lstStakerVault, lstAdapter);
    }

    function test_AddLstStakerVault_FailsIfNotGovernance() public {
        address lstStakerVault = address(new MockLSTStakerVault(address(new MockLST())));
        address lstAdapter = makeAddr("lstAdapter");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), defaultAdminRole
            )
        );
        incentiveFeeCollector.addLstStakerVault(lstStakerVault, lstAdapter);
    }

    function test_AddLstStakerVault_FailsIfZeroAddress() public {
        address lstStakerVault = address(new MockLSTStakerVault(address(new MockLST())));
        address lstAdapter = makeAddr("lstAdapter");

        vm.prank(governance);
        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        incentiveFeeCollector.addLstStakerVault(address(0), lstAdapter);

        vm.prank(governance);
        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        incentiveFeeCollector.addLstStakerVault(lstStakerVault, address(0));

        vm.prank(governance);
        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        incentiveFeeCollector.addLstStakerVault(address(0), address(0));
    }

    function test_AddLstStakerVault_FailsIfAlreadyAdded() public {
        test_AddLstStakerVault();

        address lstStakerVault = incentiveFeeCollector.lstStakerVaults(0);
        address lstAdapter = makeAddr("lstAdapter");

        vm.prank(governance);
        vm.expectRevert(IPOLErrors.LSTStakerVaultAlreadyAdded.selector);
        incentiveFeeCollector.addLstStakerVault(lstStakerVault, lstAdapter);
    }

    function test_AddLstStakerVault_FailsIfNon18Decimals() public {
        address mockNon18 = address(new MockNon18DecimalsERC20());
        address lstStakerVault = address(new MockLSTStakerVault(mockNon18));
        address lstAdapter = makeAddr("lstAdapter");

        vm.prank(governance);
        vm.expectRevert(IPOLErrors.InvalidToken.selector);
        incentiveFeeCollector.addLstStakerVault(lstStakerVault, lstAdapter);
    }

    function test_RemoveLstStakerVault() public {
        test_AddLstStakerVault();
        address lstStakerVault = incentiveFeeCollector.lstStakerVaults(0);

        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit IBGTIncentiveFeeCollector.LstStakerVaultRemoved(lstStakerVault);
        incentiveFeeCollector.removeLstStakerVault(lstStakerVault);

        assertEq(incentiveFeeCollector.lstStakerVaultsLength(), 0);
        assertEq(incentiveFeeCollector.lstAdapters(lstStakerVault), address(0));
    }

    function test_RemoveLstStakerVault_FailsIfNotGovernance() public {
        test_AddLstStakerVault();
        address lstStakerVault = makeAddr("lstStakerVault");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), defaultAdminRole
            )
        );
        incentiveFeeCollector.removeLstStakerVault(lstStakerVault);
    }

    function test_RemoveLstStakerVault_FailsIfNotAdded() public {
        address lstStakerVault = makeAddr("lstStakerVault");

        vm.prank(governance);
        vm.expectRevert(IPOLErrors.LSTStakerVaultNotFound.selector);
        incentiveFeeCollector.removeLstStakerVault(lstStakerVault);
    }

    function test_DistributionSplit_WithOneLst() public {
        (address lst, address lstStakerVault, address lstAdapter) = _deployLSTStakerVault();
        _helper_AddLstStakerVault(lstStakerVault, lstAdapter);

        // stake in main and lst vaults 50:50
        address alice = makeAddr("alice");
        _stakeLST(lst, lstStakerVault, alice, 10e18); // same amount staked in setup to wbera vault

        uint256 balanceBeforeLst = IERC20(lst).balanceOf(lstStakerVault);
        uint256 balanceBeforeWbera = wbera.balanceOf(wberaStakerVault);

        uint256 payoutAmount = incentiveFeeCollector.payoutAmount();

        // _claimFees() expansion to test RewardConverted event
        _mintTokensToIncentiveFeeCollector();
        wbera.approve(address(incentiveFeeCollector), payoutAmount);
        address[] memory feeTokens = new address[](2);
        feeTokens[0] = address(feeToken1);
        feeTokens[1] = address(feeToken2);
        vm.expectEmit(true, true, true, true);
        emit IBGTIncentiveFeeCollector.RewardConverted(lstStakerVault, payoutAmount / 2, payoutAmount / 2);
        incentiveFeeCollector.claimFees(address(this), feeTokens);
        // _claimFees() end

        uint256 balanceAfterLst = IERC20(lst).balanceOf(lstStakerVault);
        uint256 balanceAfterWbera = wbera.balanceOf(wberaStakerVault);

        // check amount has been fairly split
        vm.assertEq(balanceAfterLst - balanceBeforeLst, payoutAmount / 2);
        vm.assertEq(balanceAfterWbera - balanceBeforeWbera, payoutAmount / 2);
    }

    function test_DistributionSplit_WithMoreLsts() public {
        (address lst0, address lstStakerVault0, address lstAdapter0) = _deployLSTStakerVault();
        (address lst1, address lstStakerVault1, address lstAdapter1) = _deployLSTStakerVault();
        _helper_AddLstStakerVault(lstStakerVault0, lstAdapter0);
        _helper_AddLstStakerVault(lstStakerVault1, lstAdapter1);

        // stake same amount in all lst vaults 33:33:33
        address alice = makeAddr("alice");
        _stakeLST(lst0, lstStakerVault0, alice, 10e18);
        _stakeLST(lst1, lstStakerVault1, alice, 10e18);

        uint256 balanceBeforeLst0 = IERC20(lst0).balanceOf(lstStakerVault0);
        uint256 balanceBeforeLst1 = IERC20(lst1).balanceOf(lstStakerVault1);
        uint256 balanceBeforeWbera = wbera.balanceOf(wberaStakerVault);

        _claimFees();

        uint256 balanceAfterLst0 = IERC20(lst0).balanceOf(lstStakerVault0);
        uint256 balanceAfterLst1 = IERC20(lst1).balanceOf(lstStakerVault1);
        uint256 balanceAfterWbera = wbera.balanceOf(wberaStakerVault);

        // check amount has been fairly split
        uint256 payoutAmount = incentiveFeeCollector.payoutAmount();

        vm.assertEq(balanceAfterLst0 - balanceBeforeLst0, payoutAmount / 3);
        vm.assertEq(balanceAfterLst1 - balanceBeforeLst1, payoutAmount / 3);
        // dust goes to main vault
        vm.assertEq(balanceAfterWbera - balanceBeforeWbera, payoutAmount / 3 + 1);
    }

    function _stakeWBERA(address user, uint256 amount) internal {
        vm.deal(user, amount);
        vm.prank(user);
        WBERAStakerVault(payable(wberaStakerVault)).depositNative{ value: amount }(amount, user);
        vm.assertEq(WBERAStakerVault(payable(wberaStakerVault)).balanceOf(user), amount);
    }

    function _stakeLST(address lst, address vault, address user, uint256 amount) internal {
        deal(address(wbera), user, amount);
        vm.startPrank(user);

        // get lst
        wbera.approve(lst, amount);
        uint256 lstShares = MockLST(lst).deposit(amount, user);
        vm.assertEq(MockLST(lst).balanceOf(user), lstShares);

        // stake lst into staker vault
        MockLST(lst).approve(vault, lstShares);
        uint256 stakerShares = IERC4626(vault).deposit(lstShares, user);
        vm.assertEq(MockLST(lst).balanceOf(user), 0);
        vm.assertEq(IERC4626(vault).balanceOf(user), stakerShares);

        vm.stopPrank();
    }

    // Helper function to deploy an additional LST Staker Vault.
    function _deployLSTStakerVault() internal returns (address lst, address vault, address adapter) {
        lst = address(new MockLST());
        vault = address(new MockLSTStakerVault(lst));
        adapter = address(new MockLSTAdapter(lst));
    }
}
