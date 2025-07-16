// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { ERC20 } from "solady/src/tokens/ERC20.sol";
import { IERC1967 } from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { DistributorTest } from "./Distributor.t.sol";
import { MockERC20 } from "../mock/token/MockERC20.sol";
import { BGTIncentiveFeeDeployer } from "src/pol/BGTIncentiveFeeDeployer.sol";
import { BGTIncentiveFeeCollector } from "src/pol/BGTIncentiveFeeCollector.sol";
import { IBGTIncentiveFeeCollector, IPOLErrors } from "src/pol/interfaces/IBGTIncentiveFeeCollector.sol";
import {
    BGT_INCENTIVE_FEE_DEPLOYER_SALT,
    WBERA_STAKER_VAULT_SALT,
    BGT_INCENTIVE_FEE_COLLECTOR_SALT
} from "script/pol/POLSalts.sol";

contract BGTIncentiveFeeCollectorTest is DistributorTest {
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
            BGT_INCENTIVE_FEE_DEPLOYER_SALT,
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
        _mintTokensToIncentiveFeeCollector();
        // approve wbera token for incentive fee collector
        wbera.approve(address(incentiveFeeCollector), PAYOUT_AMOUNT);

        uint256 preWberaStakerVaultBalance = wbera.balanceOf(address(wberaStakerVault));

        address[] memory feeTokens = new address[](2);
        feeTokens[0] = address(feeToken1);
        feeTokens[1] = address(feeToken2);
        vm.expectEmit(true, true, true, true);
        emit IBGTIncentiveFeeCollector.IncentiveFeeTokenClaimed(address(this), address(this), address(feeToken1), 1e18);
        emit IBGTIncentiveFeeCollector.IncentiveFeeTokenClaimed(address(this), address(this), address(feeToken2), 1e18);
        emit IBGTIncentiveFeeCollector.IncentiveFeesClaimed(address(this), address(this));
        incentiveFeeCollector.claimFees(address(this), feeTokens);

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
                BGT_INCENTIVE_FEE_DEPLOYER_SALT,
                type(BGTIncentiveFeeDeployer).creationCode,
                abi.encode(
                    governance, address(this), PAYOUT_AMOUNT, WBERA_STAKER_VAULT_SALT, BGT_INCENTIVE_FEE_COLLECTOR_SALT
                )
            )
        );
        incentiveFeeCollector = bgtIncentiveFeeDeployer.bgtIncentiveFeeCollector();
        wberaStakerVault = address(bgtIncentiveFeeDeployer.wberaStakerVault());
    }
}
