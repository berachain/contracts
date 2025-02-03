// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { FactoryOwnable } from "src/base/FactoryOwnable.sol";
import { IRewardVault, IPOLErrors } from "src/pol/interfaces/IRewardVault.sol";
import { IStakingRewards, IStakingRewardsErrors } from "src/base/IStakingRewards.sol";
import { POLTest } from "./POL.t.sol";
import { DistributorTest } from "./Distributor.t.sol";
import { StakingTest } from "./Staking.t.sol";
import { MockDAI, MockUSDT, MockAsset } from "@mock/honey/MockAssets.sol";
import { PausableERC20 } from "@mock/token/PausableERC20.sol";

contract RewardVaultTest is DistributorTest, StakingTest {
    using SafeERC20 for IERC20;

    address internal otherUser = makeAddr("otherUser");
    address internal vaultManager = makeAddr("vaultManager");
    address internal vaultPauser = makeAddr("vaultPauser");
    address internal daiIncentiveManager = makeAddr("daiIncentiveManager");
    address internal usdtIncentiveManager = makeAddr("usdtIncentiveManager");
    address internal honeyIncentiveManager = makeAddr("honeyIncentiveManager");
    MockDAI internal dai = new MockDAI();
    MockUSDT internal usdt = new MockUSDT();
    PausableERC20 internal pausableERC20 = new PausableERC20();

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
        vm.prank(vaultManager);
        factory.grantRole(vaultPauserRole, vaultPauser);
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
        vm.prank(governance);
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
        honey.approve(address(VAULT), _amount);

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
        vault.setRewardsDuration(255);

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

    function test_RecoverERC20_FailIfStakingToken() public {
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.CannotRecoverStakingToken.selector);
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

    function test_SetRewardDuration_FailIfNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(FactoryOwnable.OwnableUnauthorizedAccount.selector, address(this)));
        vault.setRewardsDuration(1 days);
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

    // test incentiveRate >= incentiveRateStored
    // amount >= FixedPointMathLib.mulDiv(amountRemaining, rateDelta, incentiveRateStored)
    function test_IncreaseIncentiveRate() public {
        uint256 newIncentiveRate = 150 * 1e18;
        uint256 amountToAdd1 = 5_000_000 * 1e18;
        uint256 amountToAdd2 = 2_500_000 * 1e18;
        addIncentives(amountToAdd1, 100 * 1e18);

        // amount >= FixedPointMathLib.mulDiv(amountRemaining, rateDelta, incentiveRateStored), incentive rate updated
        vm.prank(daiIncentiveManager);
        vault.addIncentive(address(dai), amountToAdd2, newIncentiveRate);
        // check the dai incentive data
        (uint256 updatedMinIncentiveRate, uint256 updatedIncentiveRate, uint256 updatedAmountRemaining,) =
            vault.incentives(address(dai));

        assertEq(updatedMinIncentiveRate, 100 * 1e18);
        assertEq(updatedIncentiveRate, newIncentiveRate);
        assertEq(updatedAmountRemaining, amountToAdd1 + amountToAdd2);
    }

    // amount < FixedPointMathLib.mulDiv(amountRemaining, rateDelta, incentiveRateStored)
    function test_DoNotUpdateIncentiveRateWhenAmountIsInsufficient() public {
        // Set an initial incentive rate and add incentives
        uint256 initialIncentiveRate = 100 * 1e18;
        uint256 amountToAdd1 = 5_000_000 * 1e18;
        addIncentives(amountToAdd1, initialIncentiveRate);

        // Attempt to update the incentive rate with an insufficient amount
        uint256 higherIncentiveRate = 150 * 1e18;
        uint256 insufficientAmountToAdd = 1000 * 1e18; // set to be insufficient

        vm.prank(daiIncentiveManager);
        vault.addIncentive(address(dai), insufficientAmountToAdd, higherIncentiveRate);

        (uint256 updatedMinIncentiveRate, uint256 updatedIncentiveRate, uint256 updatedAmountRemaining,) =
            vault.incentives(address(dai));

        // The incentive rate should not be updated
        assertEq(updatedMinIncentiveRate, 100 * 1e18);
        assertEq(updatedIncentiveRate, initialIncentiveRate);
        assertEq(updatedAmountRemaining, amountToAdd1 + insufficientAmountToAdd);
    }

    // test the increase in incentive rate when amountRemaining is not required to be 0.
    function testFuzz_AddIncentive_IncreaseIncentiveRate(uint256 newIncentiveRate) public {
        newIncentiveRate = bound(newIncentiveRate, 200 * 1e18 + 1, 1e36);
        // updates the incentive rate to 200 * 1e18 while minRate is 100 * 1e18.
        addIncentives(100 * 1e18, 200 * 1e18);
        // amountRemaining is 100 * 1e18.
        uint256 bgtIncentivizedWithCurrentRate = (100 * 1e18 * 1e18) / (200 * 1e18);
        uint256 minAmountToAdd =
            FixedPointMathLib.mulDiv(bgtIncentivizedWithCurrentRate, (newIncentiveRate - 200 * 1e18), 1e18);
        minAmountToAdd = FixedPointMathLib.max(minAmountToAdd, 100 * 1e18);
        // add more dai incentive with rate of newIncentiveRate
        vm.prank(daiIncentiveManager);
        vault.addIncentive(address(dai), minAmountToAdd, newIncentiveRate);
        (, uint256 incentiveRate, uint256 amountRemaining,) = vault.incentives(address(dai));
        assertEq(incentiveRate, newIncentiveRate);
        assertEq(amountRemaining, 100 * 1e18 + minAmountToAdd);
    }

    // test the decrease in incentive rate when amountRemaining is not 0.
    function testFuzz_AddIncentive_IncentiveRateNotChanged(uint256 newIncentiveRate) public {
        newIncentiveRate = bound(newIncentiveRate, 100 * 1e18 + 1, 200 * 1e18 - 1);
        // updates the incentive rate to 200 * 1e18 while minRate is 100 * 1e18.
        addIncentives(101 * 1e18, 200 * 1e18);
        // add more dai incentive with rate of newIncentiveRate
        // it wont change the rate as amountRemaining is not 0 and newIncentiveRate is less than current rate.
        vm.prank(daiIncentiveManager);
        vault.addIncentive(address(dai), 100 * 1e18, newIncentiveRate);
        (, uint256 incentiveRate, uint256 amountRemaining,) = vault.incentives(address(dai));
        assertNotEq(incentiveRate, newIncentiveRate);
        assertEq(amountRemaining, 201 * 1e18);
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
        assertEq(dai.balanceOf(operator), tokenToIncentivize);
        assertEq(honey.balanceOf(operator), tokenToIncentivize);
    }

    function test_ProcessIncentives() public {
        addIncentives(100 * 1e18, 200 * 1e18);
        // validator emit 1 BGT to the vault and will get all the incentives
        vm.startPrank(address(distributor));
        IERC20(bgt).safeIncreaseAllowance(address(vault), 1 ether);
        vm.expectEmit();
        emit IRewardVault.IncentivesProcessed(valData.pubkey, address(dai), 1e18, 100 * 1e18);
        emit IRewardVault.IncentivesProcessed(valData.pubkey, address(honey), 1e18, 100 * 1e18);
        vault.notifyRewardAmount(valData.pubkey, 1e18);
        (,, uint256 amountRemainingUSDC,) = vault.incentives(address(dai));
        (,, uint256 amountRemainingHoney,) = vault.incentives(address(honey));
        // validator will get min(200(incentiveRate) * 1, 100(amountRemaining)) = 100 tokens of dai and honey
        assertEq(amountRemainingUSDC, 0);
        assertEq(amountRemainingHoney, 0);
        assertEq(dai.balanceOf(operator), 100 * 1e18);
        assertEq(honey.balanceOf(operator), 100 * 1e18);
        vm.stopPrank();
        // Since amountRemaining is 0, incentiveRate can be updated here.
        // This will set the incentiveRate to 110 * 1e18
        vm.prank(daiIncentiveManager);
        vault.addIncentive(address(dai), 100 * 1e18, 110 * 1e18);
        (, uint256 incentiveRate, uint256 amountRemaining,) = vault.incentives(address(dai));
        assertEq(incentiveRate, 110 * 1e18);
        assertEq(amountRemaining, 100 * 1e18);
    }

    function test_ProcessIncentives_NotFailWithMaliciusIncentive() public {
        _addIncentiveToken(address(dai), daiIncentiveManager, 100 * 1e18, 200 * 1e18);
        addMaliciusIncentive(100 * 1e18, 200 * 1e18);

        // Pause the contract in order to make it revert on transfer
        pausableERC20.pause();

        vm.startPrank(address(distributor));
        IERC20(bgt).safeIncreaseAllowance(address(vault), 1e17);

        vm.expectEmit();
        emit IRewardVault.IncentivesProcessed(valData.pubkey, address(dai), 1e17, 20 * 1e18);
        emit IRewardVault.IncentivesProcessed(valData.pubkey, address(honey), 1e17, 20 * 1e18);
        emit IRewardVault.IncentivesProcessFailed(valData.pubkey, address(pausableERC20), 1e17, 20 * 1e18);
        vault.notifyRewardAmount(valData.pubkey, 1e17);

        (,, uint256 amountRemainingDAI,) = vault.incentives(address(dai));
        (,, uint256 amountRemainingPausableERC20,) = vault.incentives(address(pausableERC20));

        assertEq(amountRemainingDAI, 80 * 1e18);
        assertEq(amountRemainingPausableERC20, 100 * 1e18); // Amount remaining should not change
        assertEq(dai.balanceOf(operator), 20 * 1e18);
        assertEq(pausableERC20.balanceOf(operator), 0); // No tokens should be transferred
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

    function addMaliciusIncentive(uint256 amount, uint256 _incentiveRate) internal {
        testFuzz_WhitelistIncentiveToken(address(pausableERC20), address(this));
        // mint dai and approve vault to use the tokens on behalf of the user
        pausableERC20.mint(address(this), type(uint256).max);
        pausableERC20.approve(address(vault), type(uint256).max);

        vm.expectEmit();
        emit IRewardVault.IncentiveAdded(address(pausableERC20), address(this), amount, _incentiveRate);
        vault.addIncentive(address(pausableERC20), amount, _incentiveRate);

        // check incentive data
        (uint256 minIncentiveRate, uint256 incentiveRate, uint256 amountRemaining,) =
            vault.incentives(address(pausableERC20));
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

    function test_UndistributedRewardsDust() public virtual {
        performNotify(100);
        vm.prank(governance);
        vault.setRewardsDuration(3);

        uint256 amount = 100;
        uint256 rewardsDuration = VAULT.rewardsDuration();

        vm.warp(block.timestamp + rewardsDuration);
        performStake(user, amount);

        // check that math of the rewards is correct with given PRECISION
        assertEq(VAULT.undistributedRewards() + VAULT.rewardRate() * VAULT.rewardsDuration(), amount * PRECISION);
    }

    function test_PauseFailWithVaultManager() public {
        vm.prank(vaultManager);
        vm.expectRevert(abi.encodeWithSelector(FactoryOwnable.OwnableUnauthorizedAccount.selector, vaultManager));
        vault.pause();
    }
}
