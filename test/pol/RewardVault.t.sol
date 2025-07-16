// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { FactoryOwnable } from "src/base/FactoryOwnable.sol";
import { RewardVault } from "src/pol/rewards/RewardVault.sol";
import { IRewardVault, IPOLErrors } from "src/pol/interfaces/IRewardVault.sol";
import { IRewardVaultFactory } from "src/pol/interfaces/IRewardVaultFactory.sol";
import { IStakingRewards, IStakingRewardsErrors } from "src/base/IStakingRewards.sol";
import { POLTest } from "./POL.t.sol";
import { DistributorTest } from "./Distributor.t.sol";
import { StakingTest } from "./Staking.t.sol";
import { MockDAI, MockUSDT, MockAsset } from "@mock/honey/MockAssets.sol";
import { PausableERC20 } from "@mock/token/PausableERC20.sol";
import { MockERC20 } from "@mock/token/MockERC20.sol";
import { ApprovalPauseERC20 } from "@mock/token/ApprovalPauseERC20.sol";
import { MaxGasConsumeERC20 } from "@mock/token/MaxGasConsumeERC20.sol";
import { IBGTIncentiveDistributor } from "src/pol/interfaces/IBGTIncentiveDistributor.sol";

contract RewardVaultTest is DistributorTest, StakingTest {
    using SafeERC20 for IERC20;

    address internal otherUser = makeAddr("otherUser");
    address internal vaultManager = makeAddr("vaultManager");
    address internal vaultPauser = makeAddr("vaultPauser");
    address internal daiIncentiveManager = makeAddr("daiIncentiveManager");
    address internal usdtIncentiveManager = makeAddr("usdtIncentiveManager");
    address internal honeyIncentiveManager = makeAddr("honeyIncentiveManager");
    address internal honeyVaultManager = makeAddr("honeyVaultManager");
    MockDAI internal dai = new MockDAI();
    MockUSDT internal usdt = new MockUSDT();
    PausableERC20 internal pausableERC20 = new PausableERC20();
    ApprovalPauseERC20 internal approvalPauseERC20 = new ApprovalPauseERC20();

    bytes32 internal defaultFactoryAdminRole;
    bytes32 internal vaultManagerRole;
    bytes32 internal vaultPauserRole;

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual override {
        super.setUp();
        VAULT = IStakingRewards(vault);
        stakeToken = vault.stakeToken();
        rewardToken = vault.rewardToken();
        OWNER = governance;

        defaultFactoryAdminRole = factory.DEFAULT_ADMIN_ROLE();
        vaultManagerRole = factory.VAULT_MANAGER_ROLE();
        vaultPauserRole = factory.VAULT_PAUSER_ROLE();

        vm.prank(governance);
        factory.grantRole(vaultManagerRole, vaultManager);

        // only vault manager can grant the vault pauser role.
        vm.startPrank(vaultManager);
        factory.grantRole(vaultPauserRole, vaultPauser);
        // set the reward vault manager for honey vault.
        vault.setRewardVaultManager(honeyVaultManager);
        vm.stopPrank();
    }

    /// @dev helper function to perform staking
    function _stake(address _user, uint256 _amount) internal override {
        vm.prank(_user);
        vault.stake(_amount);
    }

    function _withdraw(address _user, uint256 _amount) internal override {
        vm.prank(_user);
        vault.withdraw(_amount);
    }

    function _getReward(address _caller, address _user, address _recipient) internal override returns (uint256) {
        vm.prank(_caller);
        // user getting the BGT emission.
        return vault.getReward(_user, _recipient);
    }

    function _notifyRewardAmount(uint256 _amount) internal override {
        vm.prank(address(distributor));
        vault.notifyRewardAmount(valData.pubkey, _amount);
    }

    function _setRewardsDuration(uint256 _duration) internal override {
        vm.prank(honeyVaultManager);
        vault.setRewardsDuration(_duration);
    }

    /// @dev helper function to perform reward notification
    function performNotify(uint256 _amount) internal override {
        deal(address(bgt), address(distributor), bgt.balanceOf(address(distributor)) + _amount);
        uint256 allowance = bgt.allowance(address(distributor), address(vault));
        vm.prank(address(distributor));
        IERC20(bgt).approve(address(vault), allowance + _amount);
        _notifyRewardAmount(_amount);
    }

    /// @dev helper function to perform staking
    function performStake(address _user, uint256 _amount) internal override {
        // Mint honey tokens to the user
        deal(address(honey), _user, _amount);

        // Approve the vault to spend honey tokens on behalf of the user
        vm.prank(_user);
        honey.approve(address(vault), _amount);

        // Stake the tokens in the vault
        vm.expectEmit();
        emit IStakingRewards.Staked(_user, _amount);
        _stake(_user, _amount);
    }

    /// @dev helper function to perform withdrawal
    function performWithdraw(address _user, uint256 _amount) internal override {
        vm.expectEmit();
        emit IStakingRewards.Withdrawn(_user, _amount);
        _withdraw(_user, _amount);
    }

    /// @dev Ensure that the contract is owned by the governance.
    function test_OwnerIsGovernance() public view override {
        assert(vault.isFactoryOwner(governance));
    }

    function test_FactoryOwner() public view {
        assertEq(address(vault.factory()), address(factory));
    }

    function test_ChangeInFactoryOwner() public {
        address newOwner = makeAddr("newOwner");
        testFuzz_ChangeInFactoryOwner(newOwner);
    }

    function testFuzz_ChangeInFactoryOwner(address newOwner) public {
        vm.assume(newOwner != address(0) && newOwner != address(governance));
        vm.startPrank(governance);
        // change owner of rewardVaultFactory
        factory.grantRole(defaultFactoryAdminRole, newOwner);
        factory.renounceRole(defaultFactoryAdminRole, governance);
        vm.stopPrank();
        // vault should reflect the change in factory owner.
        assert(!vault.isFactoryOwner(governance));
        assert(vault.isFactoryOwner(newOwner));
    }

    /// @dev Should fail if not the owner
    function test_FailIfNotOwner() public override {
        vm.expectRevert();
        vault.setDistributor(address(1));

        vm.expectRevert();
        vault.notifyRewardAmount(valData.pubkey, 255);

        vm.expectRevert();
        vault.recoverERC20(address(honey), 255);

        vm.expectRevert();
        vault.pause();
    }

    /// @dev Should fail if initialize again
    function test_FailIfInitializeAgain() public override {
        vm.expectRevert();
        vault.initialize(address(beraChef), address(bgt), address(distributor), address(honey));
    }

    function test_SetDistributor_FailIfNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(FactoryOwnable.OwnableUnauthorizedAccount.selector, address(this)));
        vault.setDistributor(address(1));
    }

    function test_SetDistributor_FailWithZeroAddress() public {
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        vault.setDistributor(address(0));
    }

    function test_SetDistributor() public {
        address newDistributor = makeAddr("newDistributor");
        vm.prank(governance);
        vm.expectEmit();
        emit IRewardVault.DistributorSet(newDistributor);
        vault.setDistributor(address(newDistributor));
        assertEq(vault.distributor(), address(newDistributor));
    }

    function test_RecoverERC20_FailIfNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(FactoryOwnable.OwnableUnauthorizedAccount.selector, address(this)));
        vault.recoverERC20(address(honey), 1 ether);
    }

    function test_RecoverERC20_FailsIfIncentiveToken() public {
        testFuzz_WhitelistIncentiveToken(address(dai), daiIncentiveManager);
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.CannotRecoverIncentiveToken.selector);
        vault.recoverERC20(address(dai), 1 ether);
    }

    function test_RecoverERC20() public {
        dai.mint(address(this), 1 ether);
        dai.transfer(address(vault), 1 ether);
        vm.prank(governance);
        vm.expectEmit();
        emit IRewardVault.Recovered(address(dai), 1 ether);
        vault.recoverERC20(address(dai), 1 ether);
        assertEq(dai.balanceOf(governance), 1 ether);
    }

    function test_RecoverERC20StakingToken() public {
        MockERC20 stakeToken = MockERC20(address(vault.stakeToken()));
        stakeToken.mint(address(this), 1 ether);
        stakeToken.transfer(address(vault), 1 ether);
        vm.prank(governance);
        vm.expectEmit();
        emit IRewardVault.Recovered(address(stakeToken), 1 ether);
        vault.recoverERC20(address(stakeToken), 1 ether);
        assertEq(stakeToken.balanceOf(governance), 1 ether);
    }

    function test_RecoverERC20StakingToken_FailIfNotEnoughBalance() public {
        MockERC20 stakeToken = MockERC20(address(vault.stakeToken()));
        stakeToken.mint(address(this), 1 ether);
        stakeToken.approve(address(vault), 1 ether);
        vault.stake(1 ether);
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.NotEnoughBalance.selector);
        vault.recoverERC20(address(stakeToken), 1 ether);
    }

    function test_SetRewardDuration() public {
        testFuzz_SetRewardDuration(1 days);
    }

    function testFuzz_SetRewardDuration(uint256 duration) public {
        duration = _bound(duration, 3 days, 7 days);
        // should store the new duration as pending rewards duration
        _setRewardsDuration(duration);
        assertEq(vault.pendingRewardsDuration(), duration);
        assertEq(vault.rewardsDuration(), 7 days);
    }

    /// @dev Changing rewards duration during reward cycle is allowed and is stored as pending rewards duration,
    /// thus not changing the reward rate and hence the earned amount, until a notify is performed
    function test_SetRewardsDurationDuringCycle() public {
        performNotify(100 ether);
        performStake(user, 100 ether);
        uint256 blockTimestamp = vm.getBlockTimestamp();
        // reward rate is computed over default rewards duration of 7 days
        uint256 startingRate = FixedPointMathLib.fullMulDiv(100 ether, PRECISION, 7 days);
        assertEq(vault.rewardRate(), startingRate);

        vm.warp(blockTimestamp + 0.5 days);
        blockTimestamp = vm.getBlockTimestamp();
        assertApproxEqAbs(vault.earned(user), FixedPointMathLib.fullMulDiv(startingRate, 0.5 days, PRECISION), 1e2);

        // changing rewards duration is allowed during reward cycle
        _setRewardsDuration(4 days);
        assertEq(vault.pendingRewardsDuration(), 4 days);
        assertEq(vault.rewardsDuration(), 7 days);

        // does not affect reward rate and thus user earned amount...
        assertEq(vault.rewardRate(), startingRate);
        vm.warp(blockTimestamp + 0.5 days);
        blockTimestamp = vm.getBlockTimestamp();
        assertApproxEqAbs(vault.earned(user), FixedPointMathLib.fullMulDiv(startingRate, 1 days, PRECISION), 1e2);

        // ... until a new amount is notified to the vault
        performNotify(100 ether);
        // pending rewards duration should be cleared
        assertEq(vault.pendingRewardsDuration(), 0);
        // rewards duration should be updated
        assertEq(vault.rewardsDuration(), 4 days);

        uint256 leftOver = 100 ether * PRECISION - startingRate * 1 days;
        uint256 newRate = (100 ether * PRECISION + leftOver) / 4 days;
        assertEq(vault.rewardRate(), newRate);

        vm.warp(blockTimestamp + 1 days);
        blockTimestamp = vm.getBlockTimestamp();
        uint256 expectedEarned = FixedPointMathLib.fullMulDiv(startingRate, 1 days, PRECISION)
            + FixedPointMathLib.fullMulDiv(newRate, 1 days, PRECISION);
        assertApproxEqAbs(vault.earned(user), expectedEarned, 2e2);
    }

    /// @dev Changing rewards duration during reward cycle afftects users staking in different times.
    function test_SetRewardsDurationDuringCycleMultipleUsers() public {
        address user2 = makeAddr("user2");
        uint256 blockTimestamp = vm.getBlockTimestamp();

        performNotify(100 ether);
        performStake(user, 100 ether);

        // default rewards duration is 7 days
        uint256 startingRate = FixedPointMathLib.fullMulDiv(100 ether, PRECISION, 7 days);
        vm.warp(blockTimestamp + 0.5 days);
        blockTimestamp = vm.getBlockTimestamp();

        _setRewardsDuration(4 days);

        // user staking after _setRewardsDuration is still earning at the same rate until a new notify
        performStake(user2, 100 ether);
        vm.warp(blockTimestamp + 0.5 days);
        blockTimestamp = vm.getBlockTimestamp();

        performNotify(100 ether);

        uint256 leftOver = 100 ether - FixedPointMathLib.fullMulDiv(startingRate, 1 days, PRECISION);
        uint256 newRate = FixedPointMathLib.fullMulDiv(100 ether + leftOver, PRECISION, 4 days);

        vm.warp(blockTimestamp + 1 days);
        blockTimestamp = vm.getBlockTimestamp();
        uint256 userExpectedEarned = FixedPointMathLib.fullMulDiv(startingRate, 0.5 days, PRECISION)
            + FixedPointMathLib.fullMulDiv(startingRate, 0.5 days, PRECISION) / 2
            + FixedPointMathLib.fullMulDiv(newRate, 1 days, PRECISION) / 2;

        uint256 user2ExpectedEarned = FixedPointMathLib.fullMulDiv(startingRate, 0.5 days, PRECISION) / 2
            + FixedPointMathLib.fullMulDiv(newRate, 1 days, PRECISION) / 2;

        assertApproxEqAbs(vault.earned(user), userExpectedEarned, 5e2);
        assertApproxEqAbs(vault.earned(user2), user2ExpectedEarned, 5e2);
    }

    function test_SetRewardDurationDuringCycleEarned() public {
        testFuzz_SetRewardsDurationDuringCycleEarned(8 days, 1 days);
    }

    /// @dev Changing rewards duration during reward cycle and notifying rewards does change the earned amount
    /// according to the new rate
    function testFuzz_SetRewardsDurationDuringCycleEarned(uint256 duration, uint256 time) public {
        duration = _bound(duration, 3 days, 7 days);
        time = _bound(time, 3 days, 7 days);

        performNotify(100 ether);
        performStake(user, 100 ether);

        uint256 rate = vault.rewardRate();
        vm.warp(block.timestamp + 1 days);

        _setRewardsDuration(duration);
        performNotify(100 ether);
        uint256 newRate = vault.rewardRate();

        vm.warp(block.timestamp + time);

        if (time >= duration) {
            assertApproxEqAbs(vault.earned(user), 200 ether, 5e3);
        } else {
            assertApproxEqAbs(
                vault.earned(user),
                FixedPointMathLib.fullMulDiv(rate, 1 days, PRECISION)
                    + FixedPointMathLib.fullMulDiv(newRate, time, PRECISION),
                1e4
            );
        }
    }

    function test_SetRewardDuration_FailIfNotManager() public {
        vm.expectRevert(IPOLErrors.NotRewardVaultManager.selector);
        vault.setRewardsDuration(3 days);

        // fails even if factory owner tries to set the reward duration.
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.NotRewardVaultManager.selector);
        vault.setRewardsDuration(3 days);
    }

    function test_SetRewardDuration_FailIfInvalidDuration() public {
        vm.startPrank(honeyVaultManager);
        vm.expectRevert(IPOLErrors.InvalidRewardDuration.selector);
        // fails if less than 3 days.
        vault.setRewardsDuration(3 days - 1);

        // fails if more than 14 days
        vm.expectRevert(IPOLErrors.InvalidRewardDuration.selector);
        vault.setRewardsDuration(14 days + 1);
        vm.stopPrank();
    }

    function test_SetRewardDuration_FailIfTargetRewardsPerSecondIsSet() public {
        testFuzz_SetTargetRewardsPerSecond(1e36);
        vm.prank(honeyVaultManager);
        vm.expectRevert(IPOLErrors.DurationChangeNotAllowed.selector);
        vault.setRewardsDuration(7 days);
    }

    function testFuzz_SetRewardVaultManager_FailIfNotVaultManager(address caller) public {
        vm.assume(caller != vaultManager);
        address newRewardVaultManager = makeAddr("newRewardVaultManager");
        vm.expectRevert(abi.encodeWithSelector(FactoryOwnable.OwnableUnauthorizedAccount.selector, caller));
        vm.prank(caller);
        vault.setRewardVaultManager(newRewardVaultManager);
    }

    function test_SetRewardVaultManager_FailIfZeroAddress() public {
        vm.prank(vaultManager);
        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        vault.setRewardVaultManager(address(0));
    }

    function test_SetRewardVaultManager() public {
        address newManager = makeAddr("newManager");
        vm.prank(vaultManager);
        vm.expectEmit();
        emit IRewardVault.RewardVaultManagerSet(newManager, honeyVaultManager);
        vault.setRewardVaultManager(newManager);
        assertEq(vault.rewardVaultManager(), newManager);
    }

    function test_SetTargetRewardsPerSecond_FailIfNotRewardVaultManager() public {
        vm.expectRevert(IPOLErrors.NotRewardVaultManager.selector);
        vault.setTargetRewardsPerSecond(1e36);

        // fails even if factory owner tries to set the reward duration.
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.NotRewardVaultManager.selector);
        vault.setTargetRewardsPerSecond(1e36);
    }

    function test_SetTargetRewardsPerSecond_AllowResettingToZero() public {
        vm.startPrank(honeyVaultManager);
        vault.setTargetRewardsPerSecond(1e36);
        assertEq(vault.targetRewardsPerSecond(), 1e36);
        vm.expectEmit();
        emit IRewardVault.TargetRewardsPerSecondUpdated(0, 1e36);
        vault.setTargetRewardsPerSecond(0);
        assertEq(vault.targetRewardsPerSecond(), 0);
        vm.stopPrank();
    }

    function test_SetTargetRewardsPerSecond() public {
        // set max rewards per second as 1 BGT per second.
        testFuzz_SetTargetRewardsPerSecond(1e36);
    }

    function testFuzz_SetTargetRewardsPerSecond(uint256 _targetRewardsPerSecond) public {
        _targetRewardsPerSecond = bound(_targetRewardsPerSecond, 1, type(uint256).max);
        vm.prank(honeyVaultManager);
        vm.expectEmit();
        emit IRewardVault.TargetRewardsPerSecondUpdated(_targetRewardsPerSecond, 0);
        emit IRewardVault.MinRewardDurationForTargetRateUpdated(3 days, 0);
        vault.setTargetRewardsPerSecond(_targetRewardsPerSecond);
        assertEq(vault.targetRewardsPerSecond(), _targetRewardsPerSecond);
        assertEq(vault.minRewardDurationForTargetRate(), 3 days);
    }

    function test_Pause_FailIfNotVaultPauser() public {
        vm.expectRevert(abi.encodeWithSelector(FactoryOwnable.OwnableUnauthorizedAccount.selector, address(this)));
        vault.pause();
    }

    function test_Pause() public {
        vm.prank(vaultPauser);
        vault.pause();
        assertTrue(vault.paused());
    }

    function test_Unpause_FailIfNotVaultManager() public {
        test_Pause();
        vm.expectRevert(abi.encodeWithSelector(FactoryOwnable.OwnableUnauthorizedAccount.selector, address(this)));
        vault.unpause();
    }

    function test_Unpause() public {
        vm.prank(vaultPauser);
        vault.pause();
        vm.prank(vaultManager);
        vault.unpause();
        assertFalse(vault.paused());
    }

    function test_StakeFailsIfPaused() public {
        test_Pause();
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vault.stake(1 ether);
    }

    function test_DelegateStakeFailsIfPused() public {
        test_Pause();
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vault.delegateStake(user, 1 ether);
    }

    function performDelegateStake(address _delegate, address _user, uint256 _amount) internal {
        // Mint honey tokens to the delegate
        honey.mint(_delegate, _amount);

        // Approve the vault to spend honey tokens on behalf of the delegate
        vm.startPrank(_delegate);
        honey.approve(address(vault), _amount);

        // Stake the tokens in the vault
        vm.expectEmit(true, true, true, true);
        emit IRewardVault.DelegateStaked(_user, _delegate, _amount);
        vault.delegateStake(_user, _amount);
        vm.stopPrank();
    }

    function test_SelfStake() public {
        performStake(user, 100 ether);
        assertEq(vault.totalSupply(), 100 ether);
        assertEq(vault.balanceOf(user), 100 ether);
        assertEq(vault.getTotalDelegateStaked(user), 0);
        assertEq(vault.getDelegateStake(user, operator), 0);
    }

    function test_DelegateStake() public {
        performDelegateStake(operator, user, 100 ether);
        assertEq(vault.totalSupply(), 100 ether);
        assertEq(vault.balanceOf(user), 100 ether);
        assertEq(vault.getTotalDelegateStaked(user), 100 ether);
        assertEq(vault.getDelegateStake(user, operator), 100 ether);
    }

    function testFuzz_DelegateStake(address _delegate, address _user, uint256 _stakeAmount) public {
        vm.assume(_stakeAmount > 0);
        vm.assume(_delegate != _user);
        performDelegateStake(_delegate, _user, _stakeAmount);
        assertEq(vault.totalSupply(), _stakeAmount);
        assertEq(vault.balanceOf(_user), _stakeAmount);
        assertEq(vault.getTotalDelegateStaked(_user), _stakeAmount);
        assertEq(vault.getDelegateStake(_user, _delegate), _stakeAmount);
    }

    function test_DelegateStakeWithSelfStake() public {
        address operator2 = makeAddr("operator2");
        performStake(user, 100 ether);
        performDelegateStake(operator, user, 100 ether);
        performDelegateStake(operator2, user, 100 ether);
        assertEq(vault.totalSupply(), 300 ether);
        assertEq(vault.balanceOf(user), 300 ether);
        assertEq(vault.getTotalDelegateStaked(user), 200 ether);
        assertEq(vault.getDelegateStake(user, operator), 100 ether);
        assertEq(vault.getDelegateStake(user, operator2), 100 ether);
    }

    function test_GetRewardFailsIfPaused() public {
        test_Pause();
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vault.getReward(user, user);
    }

    function test_GetRewardWithDelegateStake() public {
        test_Distribute();
        // operator staking on behalf of user.
        performDelegateStake(operator, user, 100 ether);
        vm.warp(block.timestamp + 1 weeks);
        uint256 accumulatedBGTRewards = vault.earned(user);

        uint256 rewardAmount = _getReward(user, user, user);
        assertEq(rewardAmount, accumulatedBGTRewards);
        assertEq(bgt.balanceOf(user), accumulatedBGTRewards);
    }

    function testFuzz_GetRewardToRecipient(address _recipient) public {
        vm.assume(_recipient != address(0));
        // should not be distributor address to avoid locking of BGT rewards.
        vm.assume(_recipient != address(distributor));
        test_Distribute();
        performStake(user, 100 ether);
        vm.warp(block.timestamp + 1 weeks);
        uint256 initialBal = bgt.balanceOf(_recipient);
        uint256 accumulatedBGTRewards = vault.earned(user);

        uint256 rewardAmount = _getReward(user, user, _recipient);
        assertEq(rewardAmount, accumulatedBGTRewards);
        assertEq(bgt.balanceOf(_recipient), initialBal + accumulatedBGTRewards);
    }

    function test_GetRewardNotOperatorOrUser() public {
        vm.prank(otherUser);
        vm.expectRevert(IPOLErrors.NotOperator.selector);
        vault.getReward(user, user);
    }

    function test_DelegateWithdrawFailsIfPaused() public {
        test_Pause();
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vault.delegateWithdraw(user, 100 ether);
    }

    function test_DelegateWithdrawFailsIfNotDelegate() public {
        vm.expectRevert(IPOLErrors.NotDelegate.selector);
        vault.delegateWithdraw(address(this), 100 ether);
    }

    function test_DelegateWithdrawFailsIfNotEnoughStakedByDelegate() public {
        performDelegateStake(operator, user, 100 ether);
        // call will revert as operator has only 100 ether staked on behalf of user.
        vm.expectRevert(IPOLErrors.InsufficientDelegateStake.selector);
        vm.prank(operator);
        vault.delegateWithdraw(user, 101 ether);
    }

    function testFuzz_DelegateWithdrawFailsIfNotEnoughStakedByDelegate(
        uint256 selfStake,
        uint256 delegateStake,
        uint256 delegateWithdraw
    )
        public
    {
        selfStake = _bound(selfStake, 1, type(uint64).max);
        delegateStake = _bound(delegateStake, 1, type(uint64).max);
        delegateWithdraw = _bound(delegateWithdraw, delegateStake + 1, type(uint256).max);
        performStake(user, selfStake);
        performDelegateStake(operator, user, delegateStake);
        // call will revert as operator trying to withdraw more than delegateStaked.
        vm.expectRevert(IPOLErrors.InsufficientDelegateStake.selector);
        vm.prank(operator);
        vault.delegateWithdraw(user, delegateWithdraw);
    }

    function test_DelegateWithdraw() public {
        performDelegateStake(operator, user, 100 ether);
        vm.prank(operator);
        vm.expectEmit(true, true, true, true);
        emit IRewardVault.DelegateWithdrawn(user, operator, 100 ether);
        vault.delegateWithdraw(user, 100 ether);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.balanceOf(user), 0);
        assertEq(vault.getTotalDelegateStaked(user), 0);
        assertEq(vault.getDelegateStake(user, operator), 0);
    }

    function testFuzz_DelegateWithdraw(
        address _delegate,
        address _user,
        uint256 _stakeAmount,
        uint256 _withdrawAmount
    )
        public
    {
        vm.assume(_stakeAmount > 0);
        vm.assume(_delegate != _user);
        _withdrawAmount = bound(_withdrawAmount, 1, _stakeAmount);
        performDelegateStake(_delegate, _user, _stakeAmount);
        vm.prank(_delegate);
        vm.expectEmit(true, true, true, true);
        emit IRewardVault.DelegateWithdrawn(_user, _delegate, _withdrawAmount);
        vault.delegateWithdraw(_user, _withdrawAmount);
        assertEq(vault.totalSupply(), _stakeAmount - _withdrawAmount);
        assertEq(vault.balanceOf(_user), _stakeAmount - _withdrawAmount);
        assertEq(vault.userRewardPerTokenPaid(_user), 0);
        assertEq(vault.getTotalDelegateStaked(_user), _stakeAmount - _withdrawAmount);
        assertEq(vault.getDelegateStake(_user, _delegate), _stakeAmount - _withdrawAmount);
    }

    /* Setting operator */

    /// @dev Should set operator
    function test_SetOperator() public {
        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit IRewardVault.OperatorSet(user, operator);
        vault.setOperator(operator);
        assertEq(vault.operator(user), operator);
    }

    /// @dev Operator can claim on behalf of the user
    function test_OperatorWorks() public {
        test_Distribute();

        performStake(user, 100 ether);

        vm.warp(block.timestamp + 1 weeks);

        // Set the operator for the user
        vm.prank(user);
        vault.setOperator(operator);

        // Assume the getReward should be called by the operator for the user
        // with recipient address as operator, hence operator should get BGT rewards.
        uint256 rewardAmount = _getReward(operator, user, operator);

        // Check the reward amount was correctly paid out
        assertTrue(rewardAmount > 0, "Should collect more than 0 rewards");
        assertTrue(
            bgt.balanceOf(operator) > 0,
            "Operator is the one calling this method then the reward will be credited to that address"
        );

        assertEq(vault.userRewardPerTokenPaid(user), rewardAmount / 100, "User's rewards per token paid should be set");

        // Ensure the user's rewards are reset after the payout
        assertEq(vault.rewards(user), 0, "User's rewards should be zero after withdrawal");
    }

    function test_Exit() public {
        testFuzz_Exit(100 ether, 100 ether);
    }

    function testFuzz_Exit(uint256 selfStake, uint256 delegateStake) public {
        selfStake = bound(selfStake, 1, type(uint256).max - 1);
        delegateStake = bound(delegateStake, 1, type(uint256).max - selfStake);
        test_Distribute();
        performStake(user, selfStake);
        performDelegateStake(operator, user, delegateStake);

        vm.warp(block.timestamp + 1 weeks);

        // Record balances before exit
        uint256 initialTokenBalance = honey.balanceOf(user);
        uint256 initialRewardBalance = bgt.balanceOf(otherUser);
        uint256 userRewards = vault.earned(user);

        // User calls exit, will only clear out self staked amount and rewards.
        vm.prank(user);
        // transfer BGT rewards to `otherUser` address
        vault.exit(otherUser);

        // Verify user's token balance increased by the `selfStake` amount.
        assertEq(honey.balanceOf(user), initialTokenBalance + selfStake);
        // Verify otherUser's reward balance increased.
        assertEq(bgt.balanceOf(otherUser), initialRewardBalance + userRewards);
        // Verify user's balance in the vault is `delegateStake`.
        assertEq(vault.balanceOf(user), delegateStake);
    }

    function test_ExitFailsIfPaused() public {
        test_Pause();
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vault.exit(user);
    }

    function test_ExitWithZeroBalance() public {
        // Ensure user has zero balance
        assertEq(vault.balanceOf(user), 0, "User should start with zero balance");

        // User tries to exit
        vm.expectRevert(IStakingRewardsErrors.WithdrawAmountIsZero.selector);
        vm.prank(user);
        vault.exit(user);
    }

    function test_FailNotifyRewardNoSufficientAllowance(int256 numDays) public {
        numDays = bound(numDays, 0, 6);
        test_Distribute();
        performStake(user, 100 ether);

        vm.warp(block.timestamp + uint256(numDays) * 1 days);

        vm.expectRevert(IStakingRewardsErrors.InsolventReward.selector);
        vm.prank(address(distributor));
        vault.notifyRewardAmount(valData.pubkey, 100 ether);
    }

    /* Getters */
    function test_TotalSupply() public {
        uint256 amount1 = 10_000_000_000_000 ether;
        uint256 amount2 = 50 ether;
        performStake(user, amount1);
        performStake(otherUser, amount2);

        assertEq(vault.totalSupply(), amount1 + amount2, "Total supply should match the stake amount");
    }

    function test_InitialState() external view {
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.periodFinish(), 0);
        assertEq(vault.rewardRate(), 0);
        assertEq(vault.lastUpdateTime(), 0);
        assertEq(vault.lastTimeRewardApplicable(), 0);
        assertEq(vault.rewardPerToken(), 0);
        assertEq(vault.rewardPerTokenStored(), 0);
        assertEq(vault.undistributedRewards(), 0);
    }

    function test_GetWhitelistedTokens() public {
        address[] memory tokenAddresses = new address[](2);
        address[] memory managers = new address[](2);
        tokenAddresses[0] = address(dai);
        managers[0] = daiIncentiveManager;
        tokenAddresses[1] = address(honey);
        managers[1] = honeyIncentiveManager;

        for (uint256 i; i < tokenAddresses.length; ++i) {
            vm.prank(governance);
            vault.whitelistIncentiveToken(tokenAddresses[i], 100 * 1e18, managers[i]);
        }

        address[] memory tokens = vault.getWhitelistedTokens();
        uint256 count = vault.getWhitelistedTokensCount();

        assertEq(tokens.length, count);
        assertEq(tokens, tokenAddresses);
    }

    function test_WhitelistIncentiveToken_FailsIfNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(FactoryOwnable.OwnableUnauthorizedAccount.selector, address(this)));
        //whitelisting USDC with 1000 USDC/BGT rate as minIncentiveRate
        vault.whitelistIncentiveToken(address(dai), 1000 * 1e18, daiIncentiveManager);
    }

    function test_WhitelistIncentiveToken_FailsIfZeroAddress() external {
        vm.startPrank(governance);
        // Fails if token is zero address
        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        vault.whitelistIncentiveToken(address(0), 100 * 1e18, daiIncentiveManager);

        // Fails if manager is zero address
        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        vault.whitelistIncentiveToken(address(dai), 100 * 1e18, address(0));
    }

    function test_WhitelistIncentiveToken_FailsIfAlreadyWhitelisted() external {
        test_WhitelistIncentiveToken();
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.TokenAlreadyWhitelistedOrLimitReached.selector);
        vault.whitelistIncentiveToken(address(dai), 10 * 1e18, daiIncentiveManager);
    }

    function test_WhitelistIncentiveToken_FailsIfCountEqualToMax() external {
        test_WhitelistIncentiveToken();
        test_SetMaxIncentiveTokensCount();
        MockDAI dai2 = new MockDAI();
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.TokenAlreadyWhitelistedOrLimitReached.selector);
        vault.whitelistIncentiveToken(address(dai2), 100 * 1e18, daiIncentiveManager);
    }

    function testFuzz_WhitelistIncentiveToken(address token, address _manager) public {
        uint256 count = vault.getWhitelistedTokensCount();
        vm.assume(token != address(0) && _manager != address(0));

        // Whitelist the token
        vm.prank(governance);
        vm.expectEmit();
        emit IRewardVault.IncentiveTokenWhitelisted(token, 100 * 1e18, _manager);
        vault.whitelistIncentiveToken(token, 100 * 1e18, _manager);

        // Verify the token was whitelisted
        (uint256 minIncentiveRate, uint256 incentiveRate,, address manager) = vault.incentives(token);
        assertEq(minIncentiveRate, 100 * 1e18);
        assertEq(incentiveRate, 100 * 1e18);
        assertEq(manager, _manager);

        // Verify the token was added to the list of whitelisted tokens
        assertEq(vault.getWhitelistedTokensCount(), count + 1);
        assertEq(vault.whitelistedTokens(count), token);
    }

    function test_WhitelistIncentiveToken() public {
        testFuzz_WhitelistIncentiveToken(address(dai), daiIncentiveManager);
        testFuzz_WhitelistIncentiveToken(address(honey), honeyIncentiveManager);
    }

    function test_WhitelistIncentiveToken_FailsIfMinIncentiveRateIsZero() public {
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.MinIncentiveRateIsZero.selector);
        vault.whitelistIncentiveToken(address(dai), 0, daiIncentiveManager);
    }

    function test_WhitelistIncentiveToken_FailsIfMinIncentiveRateMoreThanMax() public {
        testFuzz_WhitelistIncentiveToken_FailsIfMinIncentiveRateMoreThanMax(1e37);
    }

    function testFuzz_WhitelistIncentiveToken_FailsIfMinIncentiveRateMoreThanMax(uint256 minIncentiveRate) public {
        // 1e36 is the max value for incentiveRate
        minIncentiveRate = bound(minIncentiveRate, 1e36 + 1, type(uint256).max);
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.IncentiveRateTooHigh.selector);
        vault.whitelistIncentiveToken(address(dai), minIncentiveRate, daiIncentiveManager);
    }

    function test_UpdateIncentiveManager_FailsIfTokenNotWhitelisted() public {
        vm.startPrank(governance);
        vm.expectRevert(IPOLErrors.TokenNotWhitelisted.selector);
        vault.updateIncentiveManager(address(dai), address(this));

        // Token 0 should also revert with not whitelisted
        vm.expectRevert(IPOLErrors.TokenNotWhitelisted.selector);
        vault.updateIncentiveManager(address(0), address(this));
        vm.stopPrank();
    }

    function test_UpdateIncentiveManager_FailsIfNotFactoryOwner() public {
        vm.expectRevert(abi.encodeWithSelector(FactoryOwnable.OwnableUnauthorizedAccount.selector, address(this)));
        vault.updateIncentiveManager(address(dai), address(this));
    }

    function test_UpdateIncentiveManager_FailsIfZeroAddress() public {
        test_WhitelistIncentiveToken();
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        vault.updateIncentiveManager(address(dai), address(0));
    }

    function test_UpdateIncentiveManager() public {
        testFuzz_UpdateIncentiveManager(address(dai), daiIncentiveManager);
    }

    function testFuzz_UpdateIncentiveManager(address token, address newManager) public {
        vm.assume(token != address(0) && newManager != address(0));
        // whitelist the token with `address(this)` as manager
        testFuzz_WhitelistIncentiveToken(token, address(this));
        vm.prank(governance);
        vm.expectEmit();
        emit IRewardVault.IncentiveManagerChanged(token, newManager, address(this));
        vault.updateIncentiveManager(token, newManager);
        (,,, address manager) = vault.incentives(token);
        assertEq(manager, newManager);
    }

    function test_RemoveIncentiveToken_FailsIfNotVaultManager() public {
        test_WhitelistIncentiveToken();
        vm.expectRevert(abi.encodeWithSelector(FactoryOwnable.OwnableUnauthorizedAccount.selector, address(this)));
        vault.removeIncentiveToken(address(dai));
    }

    function test_RemoveIncentiveToken_FailsIfNotWhitelisted() public {
        vm.prank(vaultManager);
        vm.expectRevert(IPOLErrors.TokenNotWhitelisted.selector);
        vault.removeIncentiveToken(address(dai));
    }

    function test_RemoveIncentiveToken() public {
        test_WhitelistIncentiveToken();
        removeIncentiveToken(address(honey));
        removeIncentiveToken(address(dai));
    }

    function testFuzz_RemoveIncentiveToken(address token) public {
        vm.assume(token != address(0));
        testFuzz_WhitelistIncentiveToken(token, address(this));
        removeIncentiveToken(token);
    }

    function testFuzz_RemoveIncentiveToken_Multiple(uint8 numTokens, uint256 seed) public {
        numTokens = uint8(bound(numTokens, 1, 16));

        // Adjust the max incentive tokens count for testing purposes
        vm.startPrank(governance);
        vault.setMaxIncentiveTokensCount(numTokens);

        // Add tokens to the whitelist
        for (uint256 i; i < numTokens; ++i) {
            vault.whitelistIncentiveToken(address(new MockDAI()), 100 * 1e18, daiIncentiveManager);
        }
        vm.stopPrank();

        while (vault.getWhitelistedTokensCount() > 0) {
            // randomly remove tokens from the whitelist
            removeIncentiveToken(vault.whitelistedTokens(seed % vault.getWhitelistedTokensCount()));
            seed = uint256(keccak256(abi.encode(seed)));
        }
    }

    function test_SetMaxIncentiveTokensCount_FailsIfNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(FactoryOwnable.OwnableUnauthorizedAccount.selector, address(this)));
        vault.setMaxIncentiveTokensCount(1);
    }

    function test_SetMaxIncentiveTokensCount_FailsIfLessThanCurrentWhitelistedCount() public {
        test_WhitelistIncentiveToken();
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.InvalidMaxIncentiveTokensCount.selector);
        vault.setMaxIncentiveTokensCount(1);
    }

    function test_SetMaxIncentiveTokensCount() public {
        vm.prank(governance);
        vm.expectEmit();
        emit IRewardVault.MaxIncentiveTokensCountUpdated(2);
        vault.setMaxIncentiveTokensCount(2);
        assertEq(vault.maxIncentiveTokensCount(), 2);
    }

    function test_AddIncentive_FailsIfRateIsMoreThanMaxIncentiveRate() public {
        testFuzz_AddIncentive_FailsIfRateMoreThanMaxIncentiveRate(1e35);
    }

    function testFuzz_AddIncentive_FailsIfRateMoreThanMaxIncentiveRate(uint256 incentiveRate) public {
        incentiveRate = bound(incentiveRate, 1e36 + 1, type(uint256).max);
        test_WhitelistIncentiveToken();
        vm.expectRevert(IPOLErrors.IncentiveRateTooHigh.selector);
        vault.addIncentive(address(dai), 10 * 1e18, incentiveRate);
    }

    function test_AddIncentive_FailsIfRateLessThanMinIncentiveRate() public {
        testFuzz_AddIncentive_FailsIfRateLessThanMinIncentiveRate(100 * 1e18 - 1);
    }

    function testFuzz_AddIncentive_FailsIfRateLessThanMinIncentiveRate(uint256 incentiveRate) public {
        incentiveRate = bound(incentiveRate, 0, 100 * 1e18 - 1);
        test_WhitelistIncentiveToken();
        vm.prank(daiIncentiveManager);
        vm.expectRevert(IPOLErrors.InvalidIncentiveRate.selector);
        vault.addIncentive(address(dai), 100 * 1e18, incentiveRate);
    }

    function test_AddIncentive_FailsIfNotWhitelisted() public {
        vm.expectRevert(IPOLErrors.TokenNotWhitelisted.selector);
        vault.addIncentive(address(dai), 10 * 1e18, 10 * 1e18);
    }

    function test_AddIncentive_FailsIfAmountLessThanMinIncentiveRate() public {
        test_WhitelistIncentiveToken();
        vm.expectRevert(IPOLErrors.AmountLessThanMinIncentiveRate.selector);
        vm.prank(daiIncentiveManager);
        vault.addIncentive(address(dai), 10 * 1e18, 5 * 1e18);
    }

    function test_AddIncentive_FailsIfNotWhitelistedToken() public {
        vm.expectRevert(IPOLErrors.TokenNotWhitelisted.selector);
        vault.addIncentive(address(dai), 10 * 1e18, 10 * 1e18);
    }

    function testFuzz_AddIncentive_FailsIfAmountLessThanMinRate(uint256 amount) public {
        test_WhitelistIncentiveToken();
        // bound amount within 0 and minIncentiveRate.
        amount = bound(amount, 0, 100 * 1e18 - 1);
        vm.expectRevert(IPOLErrors.AmountLessThanMinIncentiveRate.selector);
        vm.prank(daiIncentiveManager);
        vault.addIncentive(address(dai), amount, 100 * 1e18);
    }

    function test_AddIncentive_FailIfNotManager() public {
        test_WhitelistIncentiveToken();
        vm.expectRevert(abi.encodeWithSelector(IPOLErrors.NotIncentiveManager.selector));
        vault.addIncentive(address(dai), 10 * 1e18, 10 * 1e18);
    }

    // Incentive rate can always be increased.
    function testFuzz_AddIncentive_IncreaseIncentiveRate(uint256 amount, uint256 newIncentiveRate) public {
        uint256 initialAmount = 100 * 1e18;
        uint256 initialIncentiveRate = 100 * 1e18;
        addIncentives(initialAmount, initialIncentiveRate);

        amount = bound(amount, 100 * 1e18, 5000 * 1e18);
        newIncentiveRate = bound(newIncentiveRate, initialIncentiveRate + 1, 1e36);

        vm.prank(daiIncentiveManager);
        vault.addIncentive(address(dai), amount, newIncentiveRate);
        (, uint256 incentiveRate, uint256 amountRemaining,) = vault.incentives(address(dai));
        assertEq(incentiveRate, newIncentiveRate);
        assertEq(amountRemaining, initialAmount + amount);
    }

    // test the decrease in incentive rate when amountRemaining is not 0.
    function testFuzz_AddIncentive_IncentiveRateNotChanged(uint256 amount, uint256 newIncentiveRate) public {
        uint256 initialAmount = 100 * 1e18;
        uint256 initialIncentiveRate = 200 * 1e18;
        // updates the incentive rate to 200 * 1e18 while minRate is 100 * 1e18.
        addIncentives(initialAmount, initialIncentiveRate);

        amount = bound(amount, 100 * 1e18, 5_000_000 * 1e18);
        newIncentiveRate = bound(newIncentiveRate, 100 * 1e18, initialIncentiveRate - 1);
        // add more dai incentive with rate of newIncentiveRate
        // it wont change the rate as amountRemaining is not 0 and newIncentiveRate is less than current rate.
        vm.prank(daiIncentiveManager);
        vm.expectRevert(IPOLErrors.InvalidIncentiveRate.selector);
        vault.addIncentive(address(dai), amount, newIncentiveRate);
    }

    // incentive rate changes if undistributed incentive amount is 0.
    function testFuzz_AddIncentive_UpdatesIncentiveRate(uint256 amount, uint256 _incentiveRate) public {
        // 100 * 1e18 is the minIncentiveRate
        _incentiveRate = bound(_incentiveRate, 100 * 1e18, 1e36);
        amount = bound(amount, 100 * 1e18, 1e50);
        addIncentives(amount, _incentiveRate);
    }

    function testFuzz_ProcessIncentives(uint256 bgtEmitted) public {
        bgtEmitted = bound(bgtEmitted, 0, 1000 * 1e18);
        // adds 100 dai, 100 honey incentive with rate 200 * 1e18.
        addIncentives(100 * 1e18, 200 * 1e18);
        performNotify(bgtEmitted);
        uint256 tokenToIncentivize = (bgtEmitted * 200);
        tokenToIncentivize = tokenToIncentivize > 100 * 1e18 ? 100 * 1e18 : tokenToIncentivize;
        (,, uint256 amountRemainingUSDC,) = vault.incentives(address(dai));
        (,, uint256 amountRemainingHoney,) = vault.incentives(address(honey));
        assertEq(amountRemainingUSDC, 100 * 1e18 - tokenToIncentivize);
        assertEq(amountRemainingHoney, 100 * 1e18 - tokenToIncentivize);
        // given default validator commission on incentive token is 5%, 95% of incentive tokens are transferred to
        // bgtIncentiveDistributor.
        assertEq(dai.balanceOf(bgtIncentiveDistributor), tokenToIncentivize * 95 / 100);
        assertEq(honey.balanceOf(bgtIncentiveDistributor), tokenToIncentivize * 95 / 100);

        // 5% of incentive tokens are transferred to the operator.
        assertEq(dai.balanceOf(address(operator)), tokenToIncentivize * 5 / 100);
        assertEq(honey.balanceOf(address(operator)), tokenToIncentivize * 5 / 100);
    }

    function testFuzz_ProcessIncentivesWithNonZeroCommission(uint256 bgtEmitted, uint256 commission) public {
        commission = bound(commission, 1, 0.2e4); // capped at 20%
        bgtEmitted = bound(bgtEmitted, 0, 1000 * 1e18);

        // adds 100 dai, 100 honey incentive with rate 200 * 1e18.
        addIncentives(100 * 1e18, 200 * 1e18);

        // Set the commission on the validator
        setValCommission(commission);

        performNotify(bgtEmitted);
        uint256 tokenToIncentivize = (bgtEmitted * 200);
        tokenToIncentivize = tokenToIncentivize > 100 * 1e18 ? 100 * 1e18 : tokenToIncentivize;
        uint256 validatorShare = (tokenToIncentivize * commission) / 1e4;
        uint256 bgtBoosterShare = tokenToIncentivize - validatorShare;
        (,, uint256 amountRemainingUSDC,) = vault.incentives(address(dai));
        (,, uint256 amountRemainingHoney,) = vault.incentives(address(honey));
        assertEq(amountRemainingUSDC, 100 * 1e18 - tokenToIncentivize);
        assertEq(amountRemainingHoney, 100 * 1e18 - tokenToIncentivize);

        // BGTIncentiveDistributor should get the bgtBoosterShare of the incentive tokens
        assertEq(dai.balanceOf(bgtIncentiveDistributor), bgtBoosterShare);
        assertEq(honey.balanceOf(bgtIncentiveDistributor), bgtBoosterShare);

        // Operator should get the validatorShare of the incentive tokens
        assertEq(dai.balanceOf(address(operator)), validatorShare);
        assertEq(honey.balanceOf(address(operator)), validatorShare);
    }

    function test_ProcessIncentives_WithNonZeroCommission() public {
        addIncentives(100 * 1e18, 200 * 1e18);

        // Set the commission on the validator to 20%
        setValCommission(2e3);

        // validator emit 1 BGT to the vault and will get all the incentives
        vm.startPrank(address(distributor));
        IERC20(bgt).safeIncreaseAllowance(address(vault), 1 ether);
        vm.expectEmit();
        emit IRewardVault.BGTBoosterIncentivesProcessed(valData.pubkey, address(dai), 1e18, 80 * 1e18);
        emit IRewardVault.BGTBoosterIncentivesProcessed(valData.pubkey, address(honey), 1e18, 80 * 1e18);
        emit IRewardVault.IncentivesProcessed(valData.pubkey, address(dai), 1e18, 20 * 1e18);
        emit IRewardVault.IncentivesProcessed(valData.pubkey, address(honey), 1e18, 20 * 1e18);
        vault.notifyRewardAmount(valData.pubkey, 1e18);

        // check the incentive data
        (,, uint256 amountRemainingUSDC,) = vault.incentives(address(dai));
        (,, uint256 amountRemainingHoney,) = vault.incentives(address(honey));
        assertEq(amountRemainingUSDC, 0);
        assertEq(amountRemainingHoney, 0);

        // check the operator's balance
        assertEq(dai.balanceOf(address(operator)), 20 * 1e18);
        assertEq(honey.balanceOf(address(operator)), 20 * 1e18);

        // check the bgtIncentiveDistributor's balance
        assertEq(dai.balanceOf(bgtIncentiveDistributor), 80 * 1e18);
        assertEq(honey.balanceOf(bgtIncentiveDistributor), 80 * 1e18);

        // make sure the book keeping is correct inside bgtIncentiveDistributor
        assertEq(
            IBGTIncentiveDistributor(bgtIncentiveDistributor).incentiveTokensPerValidator(valData.pubkey, address(dai)),
            80 * 1e18
        );
        assertEq(
            IBGTIncentiveDistributor(bgtIncentiveDistributor).incentiveTokensPerValidator(
                valData.pubkey, address(honey)
            ),
            80 * 1e18
        );
    }

    function test_ProcessIncentives_WithMultipleNotify() public {
        // add 200 dai, 100 honey incentive with rate 100 * 1e18.
        addIncentives(200 * 1e18, 100 * 1e18);
        performNotify(1e18);
        performNotify(1e18);
        // After 2nd notify, bgtIncentiveDistributor should have 95% of 200 of dai and honey.
        assertEq(dai.balanceOf(bgtIncentiveDistributor), 190 * 1e18);
        assertEq(honey.balanceOf(bgtIncentiveDistributor), 190 * 1e18);
        // make sure the book keeping is correct inside bgtIncentiveDistributor
        assertEq(
            IBGTIncentiveDistributor(bgtIncentiveDistributor).incentiveTokensPerValidator(valData.pubkey, address(dai)),
            190 * 1e18
        );
        assertEq(
            IBGTIncentiveDistributor(bgtIncentiveDistributor).incentiveTokensPerValidator(
                valData.pubkey, address(honey)
            ),
            190 * 1e18
        );
    }

    function test_ProcessIncentives() public {
        addIncentives(100 * 1e18, 200 * 1e18);
        // validator emit 1 BGT to the vault and will get all the incentives
        vm.startPrank(address(distributor));
        IERC20(bgt).safeIncreaseAllowance(address(vault), 1 ether);
        // Given default val commission is 5%, 95% of tokens moves to bgtIncentiveDistributor and 5% moves to operator.
        uint256 validatorShare = 100 * 1e18 * 5 / 100;
        uint256 bgtIncentiveDistributorShare = 100 * 1e18 - validatorShare;
        vm.expectEmit();
        emit IRewardVault.BGTBoosterIncentivesProcessed(
            valData.pubkey, address(dai), 1e18, bgtIncentiveDistributorShare
        );
        emit IRewardVault.BGTBoosterIncentivesProcessed(
            valData.pubkey, address(honey), 1e18, bgtIncentiveDistributorShare
        );
        emit IRewardVault.IncentivesProcessed(valData.pubkey, address(dai), 1e18, validatorShare);
        emit IRewardVault.IncentivesProcessed(valData.pubkey, address(honey), 1e18, validatorShare);
        vault.notifyRewardAmount(valData.pubkey, 1e18);
        (,, uint256 amountRemainingUSDC,) = vault.incentives(address(dai));
        (,, uint256 amountRemainingHoney,) = vault.incentives(address(honey));
        // total incentive tokens = min(200(incentiveRate) * 1, 100(amountRemaining)) = 100 tokens of dai and honey
        assertEq(amountRemainingUSDC, 0);
        assertEq(amountRemainingHoney, 0);
        // bgtIncentiveDistributor should get 95% of the incentive tokens
        assertEq(dai.balanceOf(bgtIncentiveDistributor), bgtIncentiveDistributorShare);
        assertEq(honey.balanceOf(bgtIncentiveDistributor), bgtIncentiveDistributorShare);
        // 5% of incentive tokens are transferred to the operator.
        assertEq(dai.balanceOf(address(operator)), validatorShare);
        assertEq(honey.balanceOf(address(operator)), validatorShare);
        vm.stopPrank();
        // Since amountRemaining is 0, incentiveRate can be updated here.
        // This will set the incentiveRate to 110 * 1e18
        vm.prank(daiIncentiveManager);
        vault.addIncentive(address(dai), 100 * 1e18, 110 * 1e18);
        (, uint256 incentiveRate, uint256 amountRemaining,) = vault.incentives(address(dai));
        assertEq(incentiveRate, 110 * 1e18);
        assertEq(amountRemaining, 100 * 1e18);
    }

    function test_ProcessIncentives_WithNonZeroCommissionAndMaliciousIncentive() public {
        addMaliciusIncentive(pausableERC20, 100 * 1e18, 100 * 1e18);
        // Set the commission on the validator to 20%
        setValCommission(2e3);

        // Pause the contract in order to make it revert on transfer
        pausableERC20.pause();

        vm.startPrank(address(distributor));
        IERC20(bgt).safeIncreaseAllowance(address(vault), 1e18);

        vm.expectEmit();
        emit IRewardVault.BGTBoosterIncentivesProcessFailed(valData.pubkey, address(pausableERC20), 1e18, 80 * 1e18);
        emit IRewardVault.IncentivesProcessFailed(valData.pubkey, address(dai), 1e18, 20 * 1e18);
        vault.notifyRewardAmount(valData.pubkey, 1e18);

        (,, uint256 amountRemainingPausableERC20,) = vault.incentives(address(pausableERC20));

        assertEq(amountRemainingPausableERC20, 100 * 1e18); // Amount remaining should not change
        assertEq(pausableERC20.balanceOf(bgtIncentiveDistributor), 0);
        assertEq(pausableERC20.balanceOf(address(operator)), 0);
        // if transfer fails, allowance should be 0.
        assertEq(pausableERC20.allowance(address(vault), address(bgtIncentiveDistributor)), 0);
    }

    function test_ProcessIncentives_WithApprovalPauseERC20() public {
        addMaliciusIncentive(approvalPauseERC20, 100 * 1e18, 100 * 1e18);
        // Set the commission on the validator to 20%
        setValCommission(2e3);
        // Pause the contract in order to make it revert on approval
        approvalPauseERC20.pause();

        vm.startPrank(address(distributor));
        IERC20(bgt).safeIncreaseAllowance(address(vault), 1e18);
        vm.expectEmit();
        emit IRewardVault.BGTBoosterIncentivesProcessFailed(
            valData.pubkey, address(approvalPauseERC20), 1e18, 80 * 1e18
        );
        emit IRewardVault.IncentivesProcessed(valData.pubkey, address(approvalPauseERC20), 1e18, 20 * 1e18);
        vault.notifyRewardAmount(valData.pubkey, 1e18);

        (,, uint256 amountRemainingApprovalPauseERC20,) = vault.incentives(address(approvalPauseERC20));
        // only validator share is processed i.e 20% of amount.
        // As BGT booster share fails cuz approval fails.
        assertEq(amountRemainingApprovalPauseERC20, 80 * 1e18);
        assertEq(approvalPauseERC20.balanceOf(bgtIncentiveDistributor), 0);
        assertEq(approvalPauseERC20.balanceOf(address(operator)), 20 * 1e18);
    }

    function test_ProcessIncentives_NotFailWithMaliciusIncentive() public {
        _addIncentiveToken(address(dai), daiIncentiveManager, 100 * 1e18, 200 * 1e18);
        addMaliciusIncentive(pausableERC20, 100 * 1e18, 200 * 1e18);

        // Pause the contract in order to make it revert on transfer
        pausableERC20.pause();

        vm.startPrank(address(distributor));
        IERC20(bgt).safeIncreaseAllowance(address(vault), 1e17);

        // Given 5% default commission to val, 95% of tokens moves to bgtIncentiveDistributor and 5% moves to operator.
        uint256 validatorShare = 20 * 1e18 * 5 / 100;
        uint256 bgtIncentiveDistributorShare = 20 * 1e18 - validatorShare;

        vm.expectEmit();
        emit IRewardVault.BGTBoosterIncentivesProcessed(
            valData.pubkey, address(dai), 1e17, bgtIncentiveDistributorShare
        );
        emit IRewardVault.BGTBoosterIncentivesProcessed(
            valData.pubkey, address(honey), 1e17, bgtIncentiveDistributorShare
        );
        emit IRewardVault.BGTBoosterIncentivesProcessFailed(
            valData.pubkey, address(pausableERC20), 1e17, bgtIncentiveDistributorShare
        );
        emit IRewardVault.IncentivesProcessed(valData.pubkey, address(dai), 1e17, validatorShare);
        emit IRewardVault.IncentivesProcessed(valData.pubkey, address(honey), 1e17, validatorShare);
        emit IRewardVault.IncentivesProcessFailed(valData.pubkey, address(pausableERC20), 1e17, validatorShare);
        vault.notifyRewardAmount(valData.pubkey, 1e17);

        (,, uint256 amountRemainingDAI,) = vault.incentives(address(dai));
        (,, uint256 amountRemainingPausableERC20,) = vault.incentives(address(pausableERC20));

        assertEq(amountRemainingDAI, 80 * 1e18);
        assertEq(amountRemainingPausableERC20, 100 * 1e18); // Amount remaining should not change
        assertEq(dai.balanceOf(bgtIncentiveDistributor), bgtIncentiveDistributorShare);
        assertEq(dai.balanceOf(operator), validatorShare);
        // No tokens should be transferred for malicious incentive token
        assertEq(pausableERC20.balanceOf(bgtIncentiveDistributor), 0);
        assertEq(pausableERC20.balanceOf(address(operator)), 0);
    }

    function test_WithdrawFailsIfPaused() public {
        performStake(address(this), 100 ether);
        test_Pause();
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vault.withdraw(100 ether);
    }

    function test_Withdraw_FailsIfInsufficientSelfStake() public {
        testFuzz_Withdraw_FailsIfInsufficientSelfStake(10 ether, 100 ether, 100 ether);
    }

    // withdraw fails if user has insufficient self stake.
    function testFuzz_Withdraw_FailsIfInsufficientSelfStake(
        uint256 selfStake,
        uint256 delegateStake,
        uint256 withdrawAmount
    )
        public
    {
        selfStake = bound(selfStake, 1, type(uint256).max - 1);
        delegateStake = bound(delegateStake, 1, type(uint256).max - selfStake);
        withdrawAmount = bound(withdrawAmount, selfStake + 1, type(uint256).max);
        performStake(user, selfStake);
        performDelegateStake(operator, user, delegateStake);
        // User calls withdraw
        vm.prank(user);
        vm.expectRevert(IPOLErrors.InsufficientSelfStake.selector);
        vault.withdraw(withdrawAmount);
    }

    // incentive rate changes if undistributed incentive amount is 0.
    function addIncentives(uint256 amount, uint256 _incentiveRate) internal {
        _addIncentiveToken(address(dai), daiIncentiveManager, amount, _incentiveRate);
        _addIncentiveToken(address(honey), honeyIncentiveManager, amount, _incentiveRate);

        // check the dai incentive data
        (uint256 minIncentiveRate, uint256 incentiveRate, uint256 amountRemaining,) = vault.incentives(address(dai));
        assertEq(minIncentiveRate, 100 * 1e18);
        assertEq(incentiveRate, _incentiveRate);
        assertEq(amountRemaining, amount);
    }

    function _addIncentiveToken(address token, address manager, uint256 amount, uint256 incentiveRate) internal {
        testFuzz_WhitelistIncentiveToken(token, manager);
        MockAsset(token).mint(manager, type(uint256).max);
        vm.startPrank(manager);
        MockAsset(token).approve(address(vault), type(uint256).max);

        vm.expectEmit();
        emit IRewardVault.IncentiveAdded(token, manager, amount, incentiveRate);
        vault.addIncentive(token, amount, incentiveRate);
        vm.stopPrank();
    }

    function addMaliciusIncentive(MockERC20 token, uint256 amount, uint256 _incentiveRate) internal {
        testFuzz_WhitelistIncentiveToken(address(token), address(this));
        // mint dai and approve vault to use the tokens on behalf of the user
        token.mint(address(this), type(uint256).max);
        token.approve(address(vault), type(uint256).max);

        vm.expectEmit();
        emit IRewardVault.IncentiveAdded(address(token), address(this), amount, _incentiveRate);
        vault.addIncentive(address(token), amount, _incentiveRate);

        // check incentive data
        (uint256 minIncentiveRate, uint256 incentiveRate, uint256 amountRemaining,) = vault.incentives(address(token));
        assertEq(minIncentiveRate, 100 * 1e18);
        assertEq(incentiveRate, _incentiveRate);
        assertEq(amountRemaining, amount);
    }

    function removeIncentiveToken(address token) internal {
        uint256 count = vault.getWhitelistedTokensCount();
        vm.prank(vaultManager);
        vm.expectEmit();
        emit IRewardVault.IncentiveTokenRemoved(token);
        vault.removeIncentiveToken(token);
        (uint256 minIncentiveRate, uint256 incentiveRate,, address manager) = vault.incentives(token);
        assertEq(minIncentiveRate, 0);
        assertEq(incentiveRate, 0);
        assertEq(manager, address(0));
        assertEq(vault.getWhitelistedTokensCount(), count - 1);
    }

    function test_UndistributedRewardsDust() public {
        performNotify(100);
        uint256 amount = 100;
        uint256 rewardsDuration = vault.rewardsDuration();

        vm.warp(block.timestamp + rewardsDuration);
        performStake(user, amount);

        // check that math of the rewards is correct with given PRECISION
        assertEq(vault.undistributedRewards() + vault.rewardRate() * vault.rewardsDuration(), amount * PRECISION);
    }

    function test_PauseFailWithVaultManager() public {
        vm.prank(vaultManager);
        vm.expectRevert(abi.encodeWithSelector(FactoryOwnable.OwnableUnauthorizedAccount.selector, vaultManager));
        vault.pause();
    }

    function setValCommission(uint256 commission) internal {
        vm.prank(operator);
        beraChef.queueValCommission(valData.pubkey, uint96(commission));
        vm.roll(block.number + 2 * 8191);
        beraChef.activateQueuedValCommission(valData.pubkey);
    }

    function test_ProcessIncentives_FailsIfApprovalCrossesSafeGasLimit() public {
        MaxGasConsumeERC20 maxGasConsumeERC20 = new MaxGasConsumeERC20();
        addMaliciusIncentive(maxGasConsumeERC20, 100 * 1e18, 200 * 1e18);

        vm.startPrank(address(distributor));
        IERC20(bgt).safeIncreaseAllowance(address(vault), 1e17);

        // Given 5% default commission to val, 95% of tokens moves to bgtIncentiveDistributor and 5% moves to operator.
        uint256 validatorShare = 20 * 1e18 * 5 / 100;
        uint256 bgtIncentiveDistributorShare = 20 * 1e18 - validatorShare;

        vm.expectEmit();
        emit IRewardVault.BGTBoosterIncentivesProcessFailed(
            valData.pubkey, address(maxGasConsumeERC20), 1e17, bgtIncentiveDistributorShare
        );
        emit IRewardVault.IncentivesProcessed(valData.pubkey, address(maxGasConsumeERC20), 1e17, validatorShare);
        vault.notifyRewardAmount(valData.pubkey, 1e17);
    }

    function test_AccountIncentives_FailsIfNotManager() public {
        _addIncentiveToken(address(dai), daiIncentiveManager, 500 * 1e18, 100 * 1e18);

        vm.startPrank(makeAddr("fail"));
        vm.expectRevert(abi.encodeWithSelector(IPOLErrors.NotIncentiveManager.selector));
        vault.accountIncentives(address(dai), 100e18);
    }

    function test_AccountIncentives_FailsIfAmountSmall() public {
        _addIncentiveToken(address(dai), daiIncentiveManager, 500 * 1e18, 100 * 1e18);

        vm.startPrank(daiIncentiveManager);
        vm.expectRevert(abi.encodeWithSelector(IPOLErrors.AmountLessThanMinIncentiveRate.selector));
        vault.accountIncentives(address(dai), 1e18);
    }

    function test_AccountIncentives_FailsIfNotEnoughBalance() public {
        _addIncentiveToken(address(dai), daiIncentiveManager, 500 * 1e18, 100 * 1e18);

        vm.startPrank(daiIncentiveManager);
        vm.expectRevert(abi.encodeWithSelector(IPOLErrors.NotEnoughBalance.selector));
        vault.accountIncentives(address(dai), 100e18);
    }

    function test_AccountIncentives() public {
        _addIncentiveToken(address(dai), daiIncentiveManager, 500 * 1e18, 100 * 1e18);
        deal(address(dai), address(vault), dai.balanceOf(address(vault)) + 100e18);

        (,, uint256 amountRemaining,) = vault.incentives(address(dai));
        assertEq(amountRemaining, 500e18);

        vm.startPrank(daiIncentiveManager);
        vault.accountIncentives(address(dai), 100e18);

        (,, amountRemaining,) = vault.incentives(address(dai));
        assertEq(amountRemaining, 600e18);
    }

    function test_AccountIncentivesStakeToken_FailsIfNotEnoughBalance() public {
        // testing the case the incentive token is the same as the stake token

        address stakeToken = address(vault.stakeToken());
        address stakeTokenIncentiveManager = makeAddr("stakeTokenIncentiveManager");

        performStake(user, 1000 ether);
        _addIncentiveToken(stakeToken, stakeTokenIncentiveManager, 500 * 1e18, 100 * 1e18);

        (,, uint256 amountRemaining,) = vault.incentives(stakeToken);
        assertEq(amountRemaining, 500e18);

        vm.startPrank(stakeTokenIncentiveManager);
        vm.expectRevert(abi.encodeWithSelector(IPOLErrors.NotEnoughBalance.selector));
        vault.accountIncentives(stakeToken, 1000e18);
    }

    function test_AccountIncentivesStakeToken() public {
        address stakeToken = address(vault.stakeToken());
        address stakeTokenIncentiveManager = makeAddr("stakeTokenIncentiveManager");

        performStake(user, 1000 ether);
        _addIncentiveToken(stakeToken, stakeTokenIncentiveManager, 500 * 1e18, 100 * 1e18);

        (,, uint256 amountRemaining,) = vault.incentives(stakeToken);
        assertEq(amountRemaining, 500e18);

        // donate 100e18 to the vault
        address donor = makeAddr("donor");
        deal(stakeToken, donor, 100e18);
        vm.prank(donor);
        IERC20(stakeToken).safeTransfer(address(vault), 100e18);

        vm.prank(stakeTokenIncentiveManager);
        vault.accountIncentives(stakeToken, 100e18);

        (,, amountRemaining,) = vault.incentives(stakeToken);
        assertEq(amountRemaining, 600e18);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    TARGET RATE TESTS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_SetMinRewardDurationForTargetRate_FailIfNotRewardVaultManager() public {
        vm.expectRevert(abi.encodeWithSelector(IPOLErrors.NotRewardVaultManager.selector));
        vault.setMinRewardDurationForTargetRate(3 days);
    }

    function test_SetMinRewardDurationForTargetRate_FailIfInvalidDuration() public {
        vm.startPrank(honeyVaultManager);
        vm.expectRevert(abi.encodeWithSelector(IPOLErrors.InvalidRewardDuration.selector));
        vault.setMinRewardDurationForTargetRate(1 days);
        vm.expectRevert(abi.encodeWithSelector(IPOLErrors.InvalidRewardDuration.selector));
        vault.setMinRewardDurationForTargetRate(8 days);
    }

    function test_SetMinRewardDurationForTargetRate() public {
        testFuzz_SetMinRewardDurationForTargetRate(5 days);
    }

    function testFuzz_SetMinRewardDurationForTargetRate(uint256 minRewardDurationForTargetRate) public {
        uint256 oldMinRewardDurationForTargetRate = vault.minRewardDurationForTargetRate();
        minRewardDurationForTargetRate = bound(minRewardDurationForTargetRate, 3 days, 7 days);
        vm.prank(honeyVaultManager);
        vm.expectEmit();
        emit IRewardVault.MinRewardDurationForTargetRateUpdated(
            minRewardDurationForTargetRate, oldMinRewardDurationForTargetRate
        );
        vault.setMinRewardDurationForTargetRate(minRewardDurationForTargetRate);
        assertEq(vault.minRewardDurationForTargetRate(), minRewardDurationForTargetRate);
    }

    function test_TargetRate_NotAppliedWhenTargetRewardsPerSecondIsZero() public {
        // Set targetRewardsPerSecond to 0 (default)
        assertEq(vault.targetRewardsPerSecond(), 0);

        // Add a large reward amount that would normally exceed any reasonable cap
        uint256 largeReward = 1000 ether;
        performNotify(largeReward);

        // Stake to trigger reward rate calculation
        performStake(user, 100 ether);

        // Reward rate should be calculated normally without target rate adjustment
        uint256 expectedRewardRate = largeReward * PRECISION / vault.rewardsDuration();
        assertEq(vault.rewardRate(), expectedRewardRate);
        assertEq(vault.rewardsDuration(), 7 days);
    }

    function test_TargetRate_AppliedWhenExceedsTargetRewardsPerSecond() public {
        // Set a target rewards per second
        uint256 targetRewardsPerSecond = 1e36; // 1 BGT per second, with precision
        testFuzz_SetTargetRewardsPerSecond(targetRewardsPerSecond);

        // Add a reward amount that would result in a rate higher than the target
        uint256 rewardAmount = (targetRewardsPerSecond * vault.rewardsDuration() * 2) / PRECISION; // 2x the target
        performNotify(rewardAmount);

        // Stake to trigger reward rate calculation
        performStake(user, 100 ether);

        // Reward rate should be set to target rate
        assertEq(vault.rewardRate(), targetRewardsPerSecond);

        // Rewards duration should be extended to accommodate the target rate
        uint256 expectedDuration = rewardAmount * PRECISION / targetRewardsPerSecond;
        assertEq(vault.rewardsDuration(), expectedDuration);
        assertEq(vault.periodFinish(), block.timestamp + expectedDuration);
    }

    function test_TargetRate_AppliedWhenBelowTargetRewardsPerSecond() public {
        // Set a target rewards per second
        uint256 targetRewardsPerSecond = 10e36; // 10 BGT per second, with precision
        testFuzz_SetTargetRewardsPerSecond(targetRewardsPerSecond);

        // Add a reward amount that would result in a rate below the target
        uint256 rewardAmount = (targetRewardsPerSecond * vault.rewardsDuration()) / (2 * PRECISION); // 0.5x the target
        performNotify(rewardAmount);

        // Stake to trigger reward rate calculation
        performStake(user, 100 ether);

        // Reward rate should be adjusted to target rate and duration shortened
        assertEq(vault.rewardRate(), targetRewardsPerSecond);
        uint256 expectedDuration = rewardAmount * PRECISION / targetRewardsPerSecond;
        assertEq(vault.rewardsDuration(), expectedDuration);
        assertEq(vault.rewardsDuration(), 7 days / 2);
    }

    function test_TargetRate_MinimumDurationEnforcement() public {
        // Set a very high target rate that would require duration < minRewardDurationForTargetRate
        uint256 targetRewardsPerSecond = 1000e36; // 1000 BGT per second, with precision
        testFuzz_SetTargetRewardsPerSecond(targetRewardsPerSecond);

        // Add a small reward amount
        uint256 rewardAmount = 1 ether; // 1 BGT
        performNotify(rewardAmount);

        // Stake to trigger reward rate calculation
        performStake(user, 100 ether);

        // Duration should be clamped to minRewardDurationForTargetRate
        uint256 minRewardDurationForTargetRate = vault.minRewardDurationForTargetRate();
        assertEq(vault.rewardsDuration(), minRewardDurationForTargetRate);

        // Reward rate should be calculated based on minRewardDurationForTargetRate, not target rate
        uint256 expectedRewardRate = rewardAmount * PRECISION / minRewardDurationForTargetRate;
        assertEq(vault.rewardRate(), expectedRewardRate);
        assertLt(vault.rewardRate(), targetRewardsPerSecond);
    }

    function test_TargetRate_WithMultipleNotifications() public {
        // Set a target rewards per second
        uint256 targetRewardsPerSecond = 1e36; // 1 BGT per second, with precision
        testFuzz_SetTargetRewardsPerSecond(targetRewardsPerSecond);

        // First notification - should be adjusted to target rate
        uint256 firstReward = (targetRewardsPerSecond * vault.rewardsDuration() * 2) / PRECISION;
        performNotify(firstReward);
        performStake(user, 100 ether);

        assertEq(vault.rewardRate(), targetRewardsPerSecond);
        uint256 firstDuration = vault.rewardsDuration();
        assertEq(firstDuration, 2 * 7 days);

        // Second notification during active period - should extend duration
        vm.warp(block.timestamp + 1 days);
        uint256 secondReward = (targetRewardsPerSecond * vault.rewardsDuration()) / PRECISION;
        performNotify(secondReward);

        // Reward rate should remain at target
        assertEq(vault.rewardRate(), targetRewardsPerSecond);
        // Duration should be extended
        assertGt(vault.rewardsDuration(), firstDuration);
    }

    function test_TargetRate_AfterPeriodFinish() public {
        // Set a target rewards per second
        uint256 targetRewardsPerSecond = 1e36; // 1 BGT per second, with precision
        testFuzz_SetTargetRewardsPerSecond(targetRewardsPerSecond);

        // First notification - should be adjusted to target rate
        uint256 firstReward = (targetRewardsPerSecond * vault.rewardsDuration() * 2) / PRECISION;
        performNotify(firstReward);
        performStake(user, 100 ether);

        assertEq(vault.rewardRate(), targetRewardsPerSecond);
        uint256 firstDuration = vault.rewardsDuration();

        // Wait for period to finish (but not too long to avoid timestamp overflow)
        vm.warp(block.timestamp + firstDuration + 1 days);

        // Second notification after period finish - should be adjusted to target rate again
        uint256 secondReward = (targetRewardsPerSecond * vault.rewardsDuration() * 3) / PRECISION;
        performNotify(secondReward);

        // Reward rate should be set to target rate again
        assertEq(vault.rewardRate(), targetRewardsPerSecond);
        uint256 expectedDuration = secondReward * PRECISION / targetRewardsPerSecond;
        assertEq(vault.rewardsDuration(), expectedDuration);
        assertEq(firstDuration, 2 * 7 days);
        assertEq(vault.rewardsDuration(), 3 * firstDuration);
        assertEq(vault.rewardsDuration(), 3 * 2 * 7 days);
    }

    function test_TargetRate_WithZeroTotalSupply() public {
        // Set a target rewards per second
        uint256 targetRewardsPerSecond = 1e36; // 1 BGT per second, with precision
        testFuzz_SetTargetRewardsPerSecond(targetRewardsPerSecond);

        // Add rewards but don't stake yet
        uint256 rewardAmount = (targetRewardsPerSecond * vault.rewardsDuration() * 2) / PRECISION;
        performNotify(rewardAmount);

        // Reward rate should not be set until first stake
        assertEq(vault.rewardRate(), 0);

        // Now stake to trigger reward rate calculation
        performStake(user, 100 ether);

        // Reward rate should be set to target rate
        assertEq(vault.rewardRate(), targetRewardsPerSecond);
    }

    function test_TargetRate_WithdrawAndRestake() public {
        // Set a target rewards per second
        uint256 targetRewardsPerSecond = 1e36; // 1 BGT per second, with precision
        testFuzz_SetTargetRewardsPerSecond(targetRewardsPerSecond);

        // Add rewards and stake
        uint256 rewardAmount = (targetRewardsPerSecond * vault.rewardsDuration() * 2) / PRECISION;
        performNotify(rewardAmount);
        performStake(user, 100 ether);

        assertEq(vault.rewardRate(), targetRewardsPerSecond);

        // Withdraw all tokens
        _withdraw(user, 100 ether);

        // Add more rewards
        performNotify(rewardAmount);

        // Stake again
        performStake(user, 100 ether);

        // Reward rate should be recalculated and set to target rate
        uint256 totalRewards = rewardAmount * 2;
        uint256 expectedDuration = totalRewards * PRECISION / targetRewardsPerSecond;
        assertEq(vault.rewardRate(), targetRewardsPerSecond);
        assertEq(vault.rewardsDuration(), expectedDuration);
    }

    function testFuzz_TargetRate(
        uint256 targetRewardsPerSecond,
        uint256 rewardAmount,
        uint256 minRewardDurationForTargetRate
    )
        public
    {
        // Bound the parameters to reasonable values
        targetRewardsPerSecond = bound(targetRewardsPerSecond, 1e33, 1e39); // 0.001 to 1000 BGT per second, with
            // precision
        rewardAmount = bound(rewardAmount, 1e18, 1e25); // 1 to 10M BGT
        minRewardDurationForTargetRate = bound(minRewardDurationForTargetRate, 3 days, 7 days);

        // Set target rewards per second
        testFuzz_SetTargetRewardsPerSecond(targetRewardsPerSecond);
        testFuzz_SetMinRewardDurationForTargetRate(minRewardDurationForTargetRate);

        // Add rewards and stake
        performNotify(rewardAmount);
        performStake(user, 100 ether);

        // Calculate expected duration to achieve target rate
        uint256 expectedDuration = rewardAmount * PRECISION / targetRewardsPerSecond;

        if (expectedDuration >= minRewardDurationForTargetRate) {
            // Should achieve target rate
            assertEq(vault.rewardRate(), targetRewardsPerSecond);
            assertEq(vault.rewardsDuration(), expectedDuration);
        } else {
            // Should be clamped to minimum duration
            assertEq(vault.rewardsDuration(), minRewardDurationForTargetRate);
            uint256 expectedRewardRate = rewardAmount * PRECISION / minRewardDurationForTargetRate;
            assertEq(vault.rewardRate(), expectedRewardRate);
            assertLt(vault.rewardRate(), targetRewardsPerSecond);
        }
    }

    function test_TargetRate_EdgeCase_TargetRewardsPerSecondEqualsCalculatedRate() public {
        // Set target rewards per second to exactly match the calculated rate
        uint256 rewardAmount = 7 ether; // 7 BGT over 7 days = 1 BGT per day
        uint256 targetRewardsPerSecond = rewardAmount * PRECISION / vault.rewardsDuration();

        testFuzz_SetTargetRewardsPerSecond(targetRewardsPerSecond);

        // Add rewards and stake
        performNotify(rewardAmount);
        performStake(user, 100 ether);

        // Reward rate should be exactly at the target
        assertEq(vault.rewardRate(), targetRewardsPerSecond);
        assertEq(vault.rewardsDuration(), 7 days);
    }

    function test_TargetRate_UndistributedRewardsAccounting() public {
        uint256 targetRewardsPerSecond = 1e36; // 1 BGT per second, with precision
        // Set a target rate that would require very short duration for small rewards
        testFuzz_SetTargetRewardsPerSecond(targetRewardsPerSecond);

        // Add rewards that would exceed the target
        uint256 rewardAmount = (targetRewardsPerSecond * vault.rewardsDuration() * 2) / PRECISION;
        performNotify(rewardAmount);

        uint256 undistributedBefore = vault.undistributedRewards();

        // Stake to trigger reward rate calculation
        performStake(user, 100 ether);

        // Check that undistributed rewards are properly accounted for
        // using the targetRewardsPerSecond as rewardRate
        uint256 undistributedAfter = vault.undistributedRewards();
        uint256 expectedDeduction = targetRewardsPerSecond * vault.rewardsDuration();

        assertEq(undistributedBefore - undistributedAfter, expectedDeduction);
    }

    function test_TargetRate_WithVeryHighRewardAmount() public {
        uint256 targetRewardsPerSecond = 1e36; // 1 BGT per second, with precision
        // Set a target rate that would require very short duration for small rewards
        testFuzz_SetTargetRewardsPerSecond(targetRewardsPerSecond);

        // Add an extremely high reward amount
        uint256 rewardAmount = type(uint256).max / PRECISION - 1; // Near maximum
        performNotify(rewardAmount);

        // Stake to trigger reward rate calculation
        performStake(user, 100 ether);

        // Should be set to target rate
        assertEq(vault.rewardRate(), targetRewardsPerSecond);

        // Duration should be very long but finite
        assertGt(vault.rewardsDuration(), 7 days);
        assertLt(vault.rewardsDuration(), type(uint256).max);
    }

    function test_TargetRate_SmallRewardsRespectMinimumDuration() public {
        uint256 targetRewardsPerSecond = 1e36; // 1 BGT per second
        // Set a target rate that would require very short duration for small rewards
        testFuzz_SetTargetRewardsPerSecond(targetRewardsPerSecond);

        // Add a very small reward
        uint256 smallReward = 0.1 ether; // 0.1 BGT
        performNotify(smallReward);
        performStake(user, 100 ether);

        // Duration should be clamped to minRewardDurationForTargetRate
        uint256 minRewardDurationForTargetRate = vault.minRewardDurationForTargetRate();
        assertEq(vault.rewardsDuration(), minRewardDurationForTargetRate);

        // Rate should be calculated based on minimum duration
        uint256 expectedRate = smallReward * PRECISION / minRewardDurationForTargetRate;
        assertEq(vault.rewardRate(), expectedRate);
        assertLt(vault.rewardRate(), targetRewardsPerSecond);
    }

    function test_TargetRate_MediumRewardsClampedToMinimumDuration() public {
        uint256 targetRewardsPerSecond = 1e36; // 1 BGT per second
        // Set a target rate with minRewardDurationForTargetRate set to 3 days
        testFuzz_SetTargetRewardsPerSecond(targetRewardsPerSecond);
        // change minRewardDurationForTargetRate to 5 days
        testFuzz_SetMinRewardDurationForTargetRate(5 days);

        // Add a reward that would require duration < minRewardDurationForTargetRate
        // 400000 BGT at 1 BGT/second = 400000 seconds = ~4.6 days < minRewardDurationForTargetRate
        uint256 mediumReward = 400_000 ether; // 400000 BGT
        performNotify(mediumReward);
        performStake(user, 100 ether);

        // Duration should be clamped to minRewardDurationForTargetRate
        assertEq(vault.rewardsDuration(), 5 days);

        // Rate should be calculated based on minimum duration, not target rate
        uint256 expectedRate = mediumReward * PRECISION / 5 days;
        assertEq(vault.rewardRate(), expectedRate);
        assertLt(vault.rewardRate(), targetRewardsPerSecond);
    }

    function test_TargetRate_LargeRewardsAchieveTargetRate() public {
        uint256 targetRewardsPerSecond = 1e36; // 1 BGT per second
        // Set a target rate with minRewardDurationForTargetRate set to 3 days
        testFuzz_SetTargetRewardsPerSecond(targetRewardsPerSecond);

        // Add a large reward that can achieve target rate within reasonable duration
        // 1 BGT per second * 3 days = 1 * 259200 = 259,200 BGT minimum to achieve target rate
        // Let's use 1,000,000 BGT which will take 1,000,000 seconds = ~11.6 days
        uint256 largeReward = 1_000_000 ether; // 1M BGT
        performNotify(largeReward);
        performStake(user, 100 ether);

        // Should achieve target rate
        assertEq(vault.rewardRate(), targetRewardsPerSecond);

        // Duration should be calculated to achieve target rate
        uint256 expectedDuration = largeReward * PRECISION / targetRewardsPerSecond;
        assertApproxEqAbs(vault.rewardsDuration(), expectedDuration, 10);
        uint256 minRewardDurationForTargetRate = vault.minRewardDurationForTargetRate();
        // must always be greater than minRewardDurationForTargetRate
        assertGt(vault.rewardsDuration(), minRewardDurationForTargetRate);
    }

    function test_TargetRate_SwitchBackToDurationBasedDistribution() public {
        // Step 1: Start with duration-based distribution (default state)
        assertEq(vault.targetRewardsPerSecond(), 0);
        assertEq(vault.rewardsDuration(), 7 days);

        // Step 2: Switch to target rate-based distribution
        uint256 targetRewardsPerSecond = 1e36; // 1 BGT per second, with precision
        testFuzz_SetTargetRewardsPerSecond(targetRewardsPerSecond);
        assertEq(vault.targetRewardsPerSecond(), targetRewardsPerSecond);

        // Step 3: Verify that setRewardsDuration is blocked when target rate is active
        vm.prank(honeyVaultManager);
        vm.expectRevert(IPOLErrors.DurationChangeNotAllowed.selector);
        vault.setRewardsDuration(5 days);

        // Step 4: Switch back to duration-based distribution by setting target rate to 0
        vm.prank(honeyVaultManager);
        vm.expectEmit();
        emit IRewardVault.TargetRewardsPerSecondUpdated(0, targetRewardsPerSecond);
        vault.setTargetRewardsPerSecond(0);
        assertEq(vault.targetRewardsPerSecond(), 0);

        // Step 5: Verify that setRewardsDuration is now allowed again
        vm.prank(honeyVaultManager);
        vault.setRewardsDuration(5 days);
        // should be stored as pending rewards duration
        assertEq(vault.pendingRewardsDuration(), 5 days);

        // Step 6: Test reward distribution behavior in duration-based mode
        uint256 rewardAmount = 100 ether;
        performNotify(rewardAmount);
        performStake(user, 100 ether);
        // pending rewards duration should be cleared
        assertEq(vault.pendingRewardsDuration(), 0);
        // rewards duration should be updated
        assertEq(vault.rewardsDuration(), 5 days);

        // Reward rate should be calculated based on duration, not target rate
        uint256 expectedRewardRate = rewardAmount * PRECISION / 5 days;
        assertApproxEqAbs(vault.rewardRate(), expectedRewardRate, 10);
        assertEq(vault.rewardsDuration(), 5 days);
        assertEq(vault.periodFinish(), block.timestamp + 5 days);
    }

    function test_TargetRate_SwitchBackToDurationBasedDistribution_WithActiveRewards() public {
        // Step 1: Start with target rate-based distribution
        uint256 targetRewardsPerSecond = 1e36; // 1 BGT per second, with precision
        testFuzz_SetTargetRewardsPerSecond(targetRewardsPerSecond);

        // Step 2: Add rewards and stake to activate target rate logic
        uint256 rewardAmount = (targetRewardsPerSecond * vault.rewardsDuration() * 2) / PRECISION;
        performNotify(rewardAmount);
        performStake(user, 100 ether);

        // Verify target rate is being applied
        assertEq(vault.rewardRate(), targetRewardsPerSecond);
        assertEq(vault.rewardsDuration(), 14 days); // Duration should be extended for target rate

        // Step 3: Switch back to duration-based distribution
        vm.prank(honeyVaultManager);
        vault.setTargetRewardsPerSecond(0);
        assertEq(vault.targetRewardsPerSecond(), 0);
        // duration should be reset to 7 days as current duration was 14 days in target rate mode
        // and stored as pending rewards duration
        assertEq(vault.pendingRewardsDuration(), 7 days);
        assertEq(vault.rewardsDuration(), 14 days);

        // Step 4: Add more rewards - should now use duration-based calculation
        vm.warp(block.timestamp + 1 days);
        uint256 additionalReward = 50 ether;
        performNotify(additionalReward);
        // pending rewards duration should be cleared
        assertEq(vault.pendingRewardsDuration(), 0);
        // rewards duration should be updated
        assertEq(vault.rewardsDuration(), 7 days);

        // left over rewards from the previous period
        uint256 leftOverRewards = targetRewardsPerSecond * 13 days + vault.undistributedRewards();

        // Reward rate should be recalculated based on duration, not target rate
        uint256 expectedRewardRate = (additionalReward * PRECISION + leftOverRewards) / 7 days;
        assertApproxEqAbs(vault.rewardRate(), expectedRewardRate, 10);
        assertEq(vault.rewardsDuration(), 7 days);
    }

    function test_TargetRate_SwitchBackToDurationBasedDistribution_WithCustomDuration() public {
        // Step 1: Set a custom duration first
        vm.prank(honeyVaultManager);
        vault.setRewardsDuration(6 days);
        assertEq(vault.pendingRewardsDuration(), 6 days);
        assertEq(vault.rewardsDuration(), 7 days);

        // Step 2: Switch to target rate-based distribution
        uint256 targetRewardsPerSecond = 1e36; // 1 BGT per second, with precision
        testFuzz_SetTargetRewardsPerSecond(targetRewardsPerSecond);

        // Step 3: Add rewards to activate target rate logic
        uint256 rewardAmount = (targetRewardsPerSecond * 6 days * 2) / PRECISION;
        performNotify(rewardAmount);
        performStake(user, 100 ether);
        // pending rewards duration should be cleared
        assertEq(vault.pendingRewardsDuration(), 0);
        // Verify target rate is being applied and duration is extended
        assertEq(vault.rewardRate(), targetRewardsPerSecond);
        // rewards duration should be updated to pending rewards duration
        // i.e 6 days but due to target mode, it will be extended to 12 days to achieve target rate.
        assertEq(vault.rewardsDuration(), 12 days);

        // Step 4: Switch back to duration-based distribution
        vm.prank(honeyVaultManager);
        vault.setTargetRewardsPerSecond(0);
        // duration should be reset to 7 days as current duration was 12 days in target rate mode
        // and stored as pending rewards duration
        assertEq(vault.pendingRewardsDuration(), 7 days);
        assertEq(vault.rewardsDuration(), 12 days);

        // Step 5: Set a new custom duration
        vm.prank(honeyVaultManager);
        // should again update the pending rewards duration to 4 days
        vault.setRewardsDuration(4 days);
        assertEq(vault.pendingRewardsDuration(), 4 days);
        assertEq(vault.rewardsDuration(), 12 days);

        vm.warp(block.timestamp + 1 days);

        // Step 6: Add rewards - should use the new custom duration
        uint256 newReward = 200 ether;
        performNotify(newReward);
        // pending rewards duration should be cleared
        assertEq(vault.pendingRewardsDuration(), 0);
        // rewards duration should be updated
        assertEq(vault.rewardsDuration(), 4 days);

        // left over rewards from the previous period, period left is 11 days
        uint256 leftOverRewards = targetRewardsPerSecond * 11 days + vault.undistributedRewards();

        // Reward rate should be calculated based on the new custom duration
        uint256 expectedRewardRate = (newReward * PRECISION + leftOverRewards) / 4 days;
        assertApproxEqAbs(vault.rewardRate(), expectedRewardRate, 10);
        assertEq(vault.rewardsDuration(), 4 days);
    }

    function test_TargetRate_SwitchBackToDurationBasedDistribution_MultipleSwitches() public {
        // Step 1: Start with duration-based
        assertEq(vault.targetRewardsPerSecond(), 0);

        // Step 2: Switch to target rate
        uint256 targetRewardsPerSecond = 1e36;
        testFuzz_SetTargetRewardsPerSecond(targetRewardsPerSecond);

        // Step 3: Switch back to duration-based
        vm.prank(honeyVaultManager);
        vault.setTargetRewardsPerSecond(0);

        // Step 4: Switch to target rate again
        vm.prank(honeyVaultManager);
        vault.setTargetRewardsPerSecond(targetRewardsPerSecond);

        // Step 5: Switch back to duration-based again
        vm.prank(honeyVaultManager);
        vault.setTargetRewardsPerSecond(0);

        // Step 6: Verify duration-based functionality works
        vm.prank(honeyVaultManager);
        vault.setRewardsDuration(5 days);
        assertEq(vault.pendingRewardsDuration(), 5 days);
        assertEq(vault.rewardsDuration(), 7 days);

        // Step 7: Test reward distribution
        uint256 rewardAmount = 100 ether;
        performNotify(rewardAmount);
        performStake(user, 100 ether);
        // pending rewards duration should be cleared
        assertEq(vault.pendingRewardsDuration(), 0);
        // rewards duration should be updated
        assertEq(vault.rewardsDuration(), 5 days);

        uint256 expectedRewardRate = rewardAmount * PRECISION / 5 days;
        assertApproxEqAbs(vault.rewardRate(), expectedRewardRate, 10);
    }

    function test_IncentiveFeesOnAdd() public {
        address collector = makeAddr("collector");
        uint256 feeRate = 1000; // 10%
        _setIncentiveFeeRatAndCollector(feeRate, collector);

        uint256 incentiveAmount = 500 * 1e18;
        _addIncentiveToken(address(dai), daiIncentiveManager, incentiveAmount, 100 * 1e18);

        // check the incentive fees
        uint256 expectedFeeAmount = incentiveAmount * feeRate / 10_000;
        (,, uint256 amountRemaining,) = vault.incentives(address(dai));

        assertEq(expectedFeeAmount, IERC20(address(dai)).balanceOf(collector));
        assertEq(incentiveAmount - expectedFeeAmount, IERC20(address(dai)).balanceOf(address(vault)));
        assertEq(incentiveAmount - expectedFeeAmount, amountRemaining);
    }

    function test_IncentiveFeesOnAccount() public {
        address collector = makeAddr("collector");
        uint256 feeRate = 1000; // 10%
        _setIncentiveFeeRatAndCollector(feeRate, collector);

        uint256 incentiveAmount = 500 * 1e18;
        _transferAndAccountIncentives(address(dai), daiIncentiveManager, incentiveAmount);

        // check the incentive fees
        uint256 expectedFeeAmount = incentiveAmount * feeRate / 10_000;
        (,, uint256 amountRemaining,) = vault.incentives(address(dai));

        assertEq(expectedFeeAmount, IERC20(address(dai)).balanceOf(collector));
        assertEq(incentiveAmount - expectedFeeAmount, IERC20(address(dai)).balanceOf(address(vault)));
        assertEq(incentiveAmount - expectedFeeAmount, amountRemaining);
    }

    function _transferAndAccountIncentives(address token, address manager, uint256 amount) internal {
        testFuzz_WhitelistIncentiveToken(token, manager);
        deal(token, address(vault), dai.balanceOf(address(vault)) + amount);

        vm.startPrank(manager);
        vault.accountIncentives(address(dai), amount);
    }

    function _setIncentiveFeeRatAndCollector(uint256 rate, address collector) internal {
        vm.startPrank(governance);
        IRewardVaultFactory factory = IRewardVaultFactory(vault.factory());

        factory.setBGTIncentiveFeeRate(rate);
        factory.setBGTIncentiveFeeCollector(collector);
        vm.stopPrank();
        assertEq(factory.bgtIncentiveFeeRate(), rate);
        assertEq(factory.bgtIncentiveFeeCollector(), collector);
    }
}
