// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC1967 } from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { POLTest } from "./POL.t.sol";
import { BGTStaker } from "src/pol/BGTStaker.sol";
import { MockERC20 } from "@mock/token/MockERC20.sol";
import { IBGTStaker, IPOLErrors } from "src/pol/interfaces/IBGTStaker.sol";
import { IStakingRewards, IStakingRewardsErrors } from "src/base/IStakingRewards.sol";
import { StakingTest } from "./Staking.t.sol";

contract BGTStakerTest is POLTest, StakingTest {
    function setUp() public override(POLTest) {
        super.setUp();
        VAULT = IStakingRewards(bgtStaker);
        stakeToken = bgtStaker.stakeToken();
        rewardToken = bgtStaker.rewardToken();
        OWNER = governance;
    }

    function _stake(address _user, uint256 _amount) internal override {
        vm.prank(address(bgt));
        bgtStaker.stake(_user, _amount);
    }

    function _withdraw(address _user, uint256 _amount) internal override {
        vm.prank(address(bgt));
        bgtStaker.withdraw(_user, _amount);
    }

    function _getReward(address, address _user, address) internal override returns (uint256) {
        vm.prank(_user);
        return bgtStaker.getReward();
    }

    function _notifyRewardAmount(uint256 _amount) internal override {
        vm.prank(address(feeCollector));
        bgtStaker.notifyRewardAmount(_amount);
    }

    function _setRewardsDuration(uint256 _duration) internal override {
        vm.prank(governance);
        bgtStaker.setRewardsDuration(_duration);
    }

    /// @dev helper function to perform reward notification
    function performNotify(uint256 _amount) internal override {
        deal(address(rewardToken), address(bgtStaker), rewardToken.balanceOf(address(bgtStaker)) + _amount);
        _notifyRewardAmount(_amount);
    }

    function testFuzz_getRewardWithLowTotalSupply(uint256 stakeAmount) public {
        // arbitrary amount between 1 wei and 1e17
        stakeAmount = _bound(stakeAmount, 1, 1e17);
        uint256 rewardAmount = 3 ether;

        uint256 timestamp = block.timestamp;

        performStake(user, stakeAmount);

        performNotify(rewardAmount);

        timestamp += 1;
        vm.warp(timestamp);
        performNotify(rewardAmount);

        timestamp += 1;
        vm.warp(timestamp);
        performNotify(rewardAmount);

        timestamp += 617_501;
        vm.warp(timestamp);

        uint256 earned = VAULT.earned(user);
        vm.prank(user);
        uint256 rewards = bgtStaker.getReward();
        assertEq(earned, rewards);
    }

    /// @dev helper function to perform staking
    function performStake(address _user, uint256 _amount) internal override {
        vm.prank(address(bgt));
        vm.expectEmit();
        emit IStakingRewards.Staked(_user, _amount);
        bgtStaker.stake(_user, _amount);
    }

    /// @dev helper function to perform withdrawal
    function performWithdraw(address _user, uint256 _amount) internal override {
        vm.prank(address(bgt));
        vm.expectEmit();
        emit IStakingRewards.Withdrawn(_user, _amount);
        bgtStaker.withdraw(_user, _amount);
    }

    function test_OwnerIsGovernance() public view {
        assertEq(bgtStaker.owner(), governance);
    }

    function test_SetRewardDurationFailsIfNotOwner() public {
        testFuzz_SetRewardDurationFailsIfNotOwner(address(this));
    }

    function testFuzz_SetRewardDurationFailsIfNotOwner(address caller) public {
        vm.assume(caller != governance);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, caller));
        bgtStaker.setRewardsDuration(7 days);
    }

    function test_SetRewardDuration_FailsIfZero() public {
        vm.prank(governance);
        vm.expectRevert(IStakingRewardsErrors.RewardsDurationIsZero.selector);
        bgtStaker.setRewardsDuration(0);
    }

    function test_RecoverERC20FailsIfNotOwner() public {
        testFuzz_RecoverERC20FailsIfNotOwner(address(this));
    }

    function testFuzz_RecoverERC20FailsIfNotOwner(address caller) public {
        vm.assume(caller != governance);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, caller));
        bgtStaker.recoverERC20(address(this), 10 ether);
    }

    function test_RecoverERC20FailsIfRewardToken() public {
        deal(address(wbera), address(bgtStaker), 10 ether);
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.CannotRecoverRewardToken.selector);
        bgtStaker.recoverERC20(address(wbera), 10 ether);
    }

    function test_RecoverERC20() public {
        testFuzz_RecoverERC20(10 ether);
    }

    function testFuzz_RecoverERC20(uint256 amount) public {
        amount = _bound(amount, 1, type(uint64).max);
        MockERC20 mockERC20 = new MockERC20();
        deal(address(mockERC20), address(bgtStaker), amount);
        vm.prank(governance);
        vm.expectEmit();
        emit IBGTStaker.Recovered(address(mockERC20), amount);
        bgtStaker.recoverERC20(address(mockERC20), amount);
    }

    function test_NotifyRewardsFailsIfNotFeeCollector() public {
        testFuzz_NotifyRewardsFailsIfNotFeeCollector(address(this));
    }

    function testFuzz_NotifyRewardsFailsIfNotFeeCollector(address caller) public {
        vm.assume(caller != address(feeCollector));
        vm.prank(caller);
        vm.expectRevert(IPOLErrors.NotFeeCollector.selector);
        bgtStaker.notifyRewardAmount(10 ether);
    }

    function test_StakeFailsIfNotBGT() public {
        testFuzz_StakeFailsIfNotBGT(address(this));
    }

    function testFuzz_StakeFailsIfNotBGT(address caller) public {
        vm.assume(caller != address(bgt));
        vm.prank(caller);
        vm.expectRevert(IPOLErrors.NotBGT.selector);
        bgtStaker.stake(address(this), 10 ether);
    }

    function test_WithdrawFailsIfNotBGT() public {
        testFuzz_WithdrawFailsIfNotBGT(address(this));
    }

    function testFuzz_WithdrawFailsIfNotBGT(address caller) public {
        vm.assume(caller != address(bgt));
        vm.prank(caller);
        vm.expectRevert(IPOLErrors.NotBGT.selector);
        bgtStaker.withdraw(address(this), 10 ether);
    }

    function testFuzz_WithdrawFailsIfInsufficientStake(
        address _user,
        uint256 stakeAmount,
        uint256 withdrawAmount
    )
        public
    {
        stakeAmount = _bound(stakeAmount, 1, type(uint64).max);
        withdrawAmount = _bound(withdrawAmount, stakeAmount + 1, type(uint256).max);
        performStake(_user, stakeAmount);
        vm.expectRevert(IStakingRewardsErrors.InsufficientStake.selector);
        _withdraw(_user, withdrawAmount);
    }

    function test_UpgradeFailsIfNotOwner() public {
        address bgtStakerNewImpl = address(new BGTStaker());
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        bgtStaker.upgradeToAndCall(bgtStakerNewImpl, "");
    }

    function test_UpgradeFailsIfNewImplNotUUPS() public {
        address newImpl = makeAddr("newImpl");
        vm.prank(governance);
        vm.expectRevert();
        // call will revert as newImpl is not UUPSUpgradeable
        bgtStaker.upgradeToAndCall(newImpl, "");
    }

    function test_UpgradeTo() public {
        address bgtStakerNewImpl = address(new BGTStaker());
        vm.expectEmit();
        emit IERC1967.Upgraded(bgtStakerNewImpl);
        vm.prank(governance);
        bgtStaker.upgradeToAndCall(bgtStakerNewImpl, "");
    }
}
