// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IStakingRewards, IStakingRewardsErrors } from "src/base/IStakingRewards.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title StakingTest
/// @notice A contract for testing core staking functionality.
/// @dev Inheriting test contracts must implement specific business logic.
abstract contract StakingTest is Test {
    IERC20 internal stakeToken;
    IERC20 internal rewardToken;
    IStakingRewards internal VAULT;
    address internal user = makeAddr("user");
    address internal OWNER;
    uint256 internal constant PRECISION = 1e18;

    function performNotify(uint256 _amount) internal virtual;

    function performStake(address _user, uint256 _amount) internal virtual;

    function performWithdraw(address _user, uint256 _amount) internal virtual;

    function _stake(address _user, uint256 _amount) internal virtual;

    function _withdraw(address _user, uint256 _amount) internal virtual;

    function _getReward(address _caller, address _user, address _recipient) internal virtual returns (uint256);

    function _notifyRewardAmount(uint256 _amount) internal virtual;

    function _setRewardsDuration(uint256 _duration) internal virtual;

    function test_Stake_FailsIfZeroAmount() public virtual {
        vm.expectRevert(IStakingRewardsErrors.StakeAmountIsZero.selector);
        _stake(address(this), 0);
    }

    function test_Stake_FailsIfOverflow(address _user) public {
        performStake(_user, 10 ether);
        vm.expectRevert(IStakingRewardsErrors.TotalSupplyOverflow.selector);
        // stake with max amount with an initial stake of 10 ether, totalSupply will overflow.
        _stake(address(this), type(uint256).max);
    }

    function test_Stake() public virtual {
        testFuzz_Stake(address(this), 10 ether);
    }

    function testFuzz_Stake(address _user, uint256 stakeAmount) public virtual {
        // Skip the test case if stakeAmount is 0
        vm.assume(stakeAmount > 0);
        // Use the helper function to perform the staking action
        performStake(_user, stakeAmount);
        // Verify the stake was successful
        uint256 userBalance = VAULT.balanceOf(_user);
        assertEq(userBalance, stakeAmount, "User's staked balance should match the stake amount");

        uint256 totalSupply = VAULT.totalSupply();
        assertEq(totalSupply, stakeAmount, "Total supply should match the stake amount");
    }

    function test_Withdraw_FailsIfZeroAmount() public virtual {
        vm.expectRevert(IStakingRewardsErrors.WithdrawAmountIsZero.selector);
        _withdraw(address(this), 0);
    }

    function testFuzz_Withdraw(address _user, uint256 amount) public virtual {
        testFuzz_PartialWithdraw(_user, amount, amount);
    }

    function testFuzz_PartialWithdraw(address _user, uint256 stakeAmount, uint256 withdrawAmount) public virtual {
        vm.assume(stakeAmount > 0);
        withdrawAmount = bound(withdrawAmount, 1, stakeAmount);

        performStake(_user, stakeAmount);
        performWithdraw(_user, withdrawAmount);

        assertEq(VAULT.totalSupply(), stakeAmount - withdrawAmount);
        assertEq(VAULT.balanceOf(address(_user)), stakeAmount - withdrawAmount);
    }

    function test_GetRewards() public virtual {
        test_NotifyRewardsSetRewardRate();
        vm.warp(block.timestamp + VAULT.rewardsDuration());
        uint256 earned = VAULT.earned(address(this));
        _getReward(address(this), address(this), address(this));
        assertEq(rewardToken.balanceOf(address(this)), earned);
    }

    function test_NotifyRewardsDoesNotSetRewardRate() public virtual {
        deal(address(rewardToken), address(VAULT), 10 ether);
        performNotify(10 ether);
        // since totalSupply is 0, rewardRate wont get set.
        assertEq(VAULT.rewardRate(), 0);
        assertEq(VAULT.periodFinish(), 0);
        assertEq(VAULT.lastTimeRewardApplicable(), 0);
        // lastUpdateTime should not be set as rewardCycle is not started.
        assertEq(VAULT.lastUpdateTime(), 0);
    }

    function test_NotifyRewardsSetRewardRate() public virtual {
        test_NotifyRewardsDoesNotSetRewardRate();
        // first stake sets the reward rate.
        performStake(address(this), 10 ether);
        uint256 expectedRewardRate = FixedPointMathLib.fullMulDiv(10 ether, 1e18, VAULT.rewardsDuration());
        assertEq(VAULT.rewardRate(), expectedRewardRate);
        assertEq(VAULT.lastTimeRewardApplicable(), block.timestamp);
        assertEq(VAULT.lastUpdateTime(), block.timestamp);
        assertEq(VAULT.periodFinish(), block.timestamp + VAULT.rewardsDuration());
    }

    function test_NotifyRewardsFailsIfRewardInsolvent() public virtual {
        testFuzz_NotifyRewardsFailsIfRewardInsolvent(0, 10 ether);
    }

    function testFuzz_NotifyRewardsFailsIfRewardInsolvent(uint256 contractBal, uint256 reward) public virtual {
        contractBal = _bound(contractBal, 1, type(uint256).max / PRECISION - 1);
        reward = _bound(reward, contractBal + 1, type(uint256).max / PRECISION);
        deal(address(rewardToken), address(VAULT), contractBal);
        vm.expectRevert(IStakingRewardsErrors.InsolventReward.selector);
        _notifyRewardAmount(reward);
    }

    function test_GetReward_BeforeDuration(uint256 stakeAmount, uint256 timeElapsed) public virtual {
        timeElapsed = bound(timeElapsed, 1, VAULT.rewardsDuration() - 1);
        // Stake amount bounded to avoid rewardPerToken rounding to zero:
        // rewardPerToken = (rewardRate * elapsed * PRECISION) / totalSupply.
        // When totalSupply >> reward * PRECISION, the quotient truncates to 0.
        stakeAmount = bound(stakeAmount, 1, 1e14 ether);
        performNotify(100 ether);
        performStake(user, stakeAmount);

        vm.warp(block.timestamp + timeElapsed);

        uint256 expectedReward = VAULT.earned(user);
        assertTrue(expectedReward > 0, "Should accrue rewards");

        uint256 rewardAmount = _getReward(user, user, user);

        assertEq(rewardAmount, expectedReward, "Should collect rewards");
        assertEq(VAULT.rewards(user), 0, "Rewards balance should be reset after collection");
    }

    function test_GetReward_Notified_Twice(uint256 stakeAmount, uint256 timeElapsed) public virtual {
        timeElapsed = bound(timeElapsed, VAULT.rewardsDuration(), 156 weeks);
        // Stake amount bounded to avoid rewardPerToken rounding to zero:
        // rewardPerToken = (rewardRate * elapsed * PRECISION) / totalSupply.
        // When totalSupply >> reward * PRECISION, the quotient truncates to 0.
        stakeAmount = bound(stakeAmount, 1, 1e14 ether);
        performNotify(100 ether);
        performStake(user, stakeAmount);

        vm.warp(block.timestamp + timeElapsed);

        performNotify(1 ether);

        uint256 expectedReward = VAULT.earned(user);
        uint256 rewardAmount = _getReward(user, user, user);
        assertEq(expectedReward, rewardAmount);
    }

    function test_GetReward_AfterDuration(uint256 stakeAmount, uint256 timeElapsed) public virtual {
        timeElapsed = bound(timeElapsed, VAULT.rewardsDuration(), 156 weeks);
        // Stake amount bounded to avoid rewardPerToken rounding to zero:
        // rewardPerToken = (rewardRate * elapsed * PRECISION) / totalSupply.
        // When totalSupply >> reward * PRECISION, the quotient truncates to 0.
        stakeAmount = bound(stakeAmount, 1, 1e14 ether);
        performNotify(100 ether);
        performStake(user, stakeAmount);

        vm.warp(block.timestamp + timeElapsed);

        uint256 expectedReward = VAULT.earned(user);
        assertTrue(expectedReward > 0, "Should accrue rewards");

        uint256 rewardAmount = _getReward(user, user, user);

        assertEq(rewardAmount, expectedReward, "Should collect rewards");
        assertEq(VAULT.rewards(user), 0, "Rewards balance should be reset");
    }

    function test_RewardRateRemains_Zero_UntilFirstStake() public virtual {
        assertEq(VAULT.rewardRate(), 0);
        performNotify(100 ether);
        // reward cycle wont start as there are no stakes
        assertEq(VAULT.rewardRate(), 0);
        assertEq(VAULT.periodFinish(), 0);
        assertEq(VAULT.lastTimeRewardApplicable(), 0);
        assertEq(VAULT.undistributedRewards(), 100 ether * PRECISION);
    }

    function test_SetRewardRateAfterFirstStake() public virtual {
        performNotify(100 ether);
        uint256 amount = 100 ether;
        uint256 rewardsDuration = VAULT.rewardsDuration();
        vm.warp(block.timestamp + rewardsDuration);
        performStake(user, amount);
        // reward cycle starts after the first stake with 100 ether as rewards
        assertEq(VAULT.rewardRate(), FixedPointMathLib.fullMulDiv(amount, PRECISION, rewardsDuration));
        assertEq(VAULT.lastTimeRewardApplicable(), block.timestamp);
        assertEq(VAULT.periodFinish(), block.timestamp + rewardsDuration);
        // lost reward dust rolled over as undistributed rewards
        assertLe(VAULT.undistributedRewards(), amount * PRECISION - VAULT.getRewardForDuration() * PRECISION);
    }

    function test_RewardRateWithMultipleDistributeRewards() public virtual {
        performNotify(100 ether);
        uint256 amount = 100 ether;
        uint256 rewardsDuration = VAULT.rewardsDuration();
        vm.warp(block.timestamp + rewardsDuration);
        assertEq(VAULT.undistributedRewards(), amount * PRECISION);
        performStake(user, amount);
        uint256 undistributedRewards = amount * PRECISION - VAULT.rewardRate() * VAULT.rewardsDuration();
        assertEq(VAULT.undistributedRewards(), undistributedRewards);
        vm.warp(block.timestamp + 1 days);
        // 6 days left in the reward cycle, given rewards duration is 7 days
        uint256 leftOver = 6 days * VAULT.rewardRate();
        undistributedRewards += leftOver;
        _withdraw(user, amount);
        // reward rate wont be set as supply is 0
        performNotify(1 ether);
        undistributedRewards += 1 ether * PRECISION;
        assertEq(VAULT.undistributedRewards(), undistributedRewards);
        assertEq(VAULT.periodFinish(), block.timestamp + 6 days);

        // notify rewards again
        performNotify(1 ether);
        undistributedRewards += 1 ether * PRECISION;
        assertEq(VAULT.undistributedRewards(), undistributedRewards);
        assertEq(VAULT.periodFinish(), block.timestamp + 6 days);
        // reward rate will be set after this
        performStake(user, amount);
        assertEq(VAULT.rewardRate(), undistributedRewards / rewardsDuration);
        undistributedRewards -= VAULT.rewardRate() * VAULT.rewardsDuration();
        assertEq(VAULT.undistributedRewards(), undistributedRewards);
        assertEq(VAULT.periodFinish(), block.timestamp + rewardsDuration);

        // test another notify rewards with empty vault after periodFinish
        vm.warp(block.timestamp + rewardsDuration + 1 days);
        _withdraw(user, amount);
        assertEq(VAULT.undistributedRewards(), undistributedRewards);
        performNotify(1 ether);
        undistributedRewards += 1 ether * PRECISION;
        assertEq(VAULT.undistributedRewards(), undistributedRewards);
        // // cycle should have ended 1 day ago
        assertEq(VAULT.periodFinish(), block.timestamp - 1 days);
    }
}
