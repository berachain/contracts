// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { RewardVault } from "src/pol/rewards/RewardVault.sol";
import { RewardVaultHelper } from "src/pol/rewards/RewardVaultHelper.sol";
import { IStakingRewards } from "src/base/IStakingRewards.sol";
import { IRewardVaultHelper, IPOLErrors } from "src/pol/interfaces/IRewardVaultHelper.sol";
import { IRewardAllocation } from "src/pol/interfaces/IRewardAllocation.sol";
import { DistributorTest } from "./Distributor.t.sol";
import { MockDAI } from "@mock/busd/MockAssets.sol";
import { MockERC4626 } from "@mock/token/MockERC4626.sol";

contract RewardVaultHelperTest is DistributorTest {
    address internal user = makeAddr("user");
    MockDAI internal dai = new MockDAI();
    MockERC4626 internal mockSWBERA;
    RewardVaultHelper internal helper;

    address internal constant WBERA_ADDR = 0x6969696969696969696969696969696969696969;

    function setUp() public override {
        super.setUp();

        helper = RewardVaultHelper(payable(rewardVaultHelper));

        vm.prank(governance);
        factory.setRewardVaultHelper(rewardVaultHelper);

        mockSWBERA = new MockERC4626();
        mockSWBERA.initialize(IERC20(WBERA_ADDR), "Staked WBERA", "sWBERA");

        vm.prank(governance);
        helper.setSWBERA(address(mockSWBERA));
    }

    receive() external payable { }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_Initialize_SetsGovernanceAsAdmin() public view {
        assertTrue(helper.hasRole(helper.DEFAULT_ADMIN_ROLE(), governance));
    }

    function test_Initialize_RevertsOnZeroAddress() public {
        RewardVaultHelper impl = new RewardVaultHelper();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        RewardVaultHelper uninitHelper = RewardVaultHelper(payable(address(proxy)));
        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        uninitHelper.initialize(address(0));
    }

    function test_Initialize_CannotBeCalledTwice() public {
        vm.expectRevert();
        helper.initialize(governance);
    }

    function test_Constructor_DisablesInitializers() public {
        RewardVaultHelper impl = new RewardVaultHelper();
        vm.expectRevert();
        impl.initialize(governance);
    }

    function test_SetSWBERA_Success() public {
        address newSWBERA = makeAddr("newSWBERA");
        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit IRewardVaultHelper.SWBERASet(newSWBERA);
        helper.setSWBERA(newSWBERA);
        assertEq(helper.sWBERA(), newSWBERA);
    }

    function test_SetSWBERA_RevertsOnZeroAddress() public {
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        helper.setSWBERA(address(0));
    }

    function test_SetSWBERA_RevertsIfNotAdmin() public {
        vm.prank(user);
        vm.expectRevert();
        helper.setSWBERA(makeAddr("sWBERA"));
    }

    function test_Upgrade_RevertsIfNotAdmin() public {
        address newImpl = address(new RewardVaultHelper());
        vm.prank(user);
        vm.expectRevert();
        helper.upgradeToAndCall(newImpl, bytes(""));
    }

    function test_Upgrade_SucceedsAsAdmin() public {
        address newImpl = address(new RewardVaultHelper());
        vm.prank(governance);
        helper.upgradeToAndCall(newImpl, bytes(""));
    }

    function test_ClaimAllRewards_SingleVault() public {
        _distributeRewards();
        _stakeInVault(user, address(vault), address(busd), 100 ether);
        vm.warp(block.timestamp + 1 weeks);

        uint256 earned = vault.earned(user);
        assertGt(earned, 0);

        address receiver = makeAddr("receiver");
        address[] memory vaults = _singleVaultArray(address(vault));

        vm.prank(user);
        helper.claimAllRewards(vaults, receiver);

        assertEq(wbera.balanceOf(receiver), earned);
        assertEq(wbera.balanceOf(user), 0);
    }

    function test_ClaimAllRewards_MultipleVaults() public {
        RewardVault vault2 = _createAndSetupSecondVault();

        _stakeInVault(user, address(vault), address(busd), 100 ether);
        dai.mint(user, 100 ether);
        _stakeInVault(user, address(vault2), address(dai), 100 ether);

        vm.warp(block.timestamp + 1 weeks);

        uint256 earned1 = vault.earned(user);
        uint256 earned2 = vault2.earned(user);
        uint256 totalExpected = earned1 + earned2;
        assertGt(totalExpected, 0);

        address[] memory vaults = new address[](2);
        vaults[0] = address(vault);
        vaults[1] = address(vault2);

        vm.prank(user);
        helper.claimAllRewards(vaults, user);

        assertEq(wbera.balanceOf(user), totalExpected);
    }

    function test_ClaimAllRewards_EmptyVaultArray() public {
        address[] memory vaults = new address[](0);

        vm.prank(user);
        helper.claimAllRewards(vaults, user);

        assertEq(wbera.balanceOf(user), 0);
    }

    function test_ClaimAllRewards_EmitsRewardsClaimedEvent() public {
        _distributeRewards();
        _stakeInVault(user, address(vault), address(busd), 100 ether);
        vm.warp(block.timestamp + 1 weeks);

        uint256 earned = vault.earned(user);
        address receiver = makeAddr("receiver");
        address[] memory vaults = _singleVaultArray(address(vault));

        vm.expectEmit(true, true, true, true);
        emit IRewardVaultHelper.RewardsClaimed(earned, receiver, WBERA_ADDR);

        vm.prank(user);
        helper.claimAllRewards(vaults, receiver);
    }

    function test_ClaimAllRewards_NoRewardsEarned() public {
        _distributeRewards();
        _stakeInVault(user, address(vault), address(busd), 100 ether);

        address[] memory vaults = _singleVaultArray(address(vault));

        vm.prank(user);
        helper.claimAllRewards(vaults, user);

        assertEq(wbera.balanceOf(user), 0);
    }

    function test_ClaimAllRewards_ReceiverIsDifferentFromCaller() public {
        _distributeRewards();
        _stakeInVault(user, address(vault), address(busd), 100 ether);
        vm.warp(block.timestamp + 1 weeks);

        uint256 earned = vault.earned(user);
        address alice = makeAddr("alice");
        address[] memory vaults = _singleVaultArray(address(vault));

        vm.prank(user);
        helper.claimAllRewards(vaults, alice);

        assertEq(wbera.balanceOf(alice), earned);
        assertEq(wbera.balanceOf(user), 0);
    }

    function test_ClaimAllRewards_CallerHasNoStake() public {
        _distributeRewards();
        _stakeInVault(user, address(vault), address(busd), 100 ether);
        vm.warp(block.timestamp + 1 weeks);

        address nobody = makeAddr("nobody");
        address[] memory vaults = _singleVaultArray(address(vault));

        vm.prank(nobody);
        helper.claimAllRewards(vaults, nobody);

        assertEq(wbera.balanceOf(nobody), 0);
    }

    function test_ClaimAllRewards_ClaimingTwiceYieldsZeroSecondTime() public {
        _distributeRewards();
        _stakeInVault(user, address(vault), address(busd), 100 ether);
        vm.warp(block.timestamp + 1 weeks);

        address[] memory vaults = _singleVaultArray(address(vault));

        vm.prank(user);
        helper.claimAllRewards(vaults, user);
        uint256 balanceAfterFirstClaim = wbera.balanceOf(user);
        assertGt(balanceAfterFirstClaim, 0);

        vm.prank(user);
        helper.claimAllRewards(vaults, user);
        assertEq(wbera.balanceOf(user), balanceAfterFirstClaim);
    }

    function test_ClaimAllRewardsWithOutput_InvalidToken_Reverts() public {
        address[] memory vaults = new address[](0);
        address invalidToken = makeAddr("invalidToken");

        vm.prank(user);
        vm.expectRevert(IPOLErrors.InvalidToken.selector);
        helper.claimAllRewards(vaults, user, invalidToken);
    }

    function test_ClaimAllRewardsWithOutput_SWBERA_DepositsIntoVault() public {
        _distributeRewards();
        _stakeInVault(user, address(vault), address(busd), 100 ether);
        vm.warp(block.timestamp + 1 weeks);

        uint256 earned = vault.earned(user);
        assertGt(earned, 0);

        address receiver = makeAddr("receiver");
        address[] memory vaults = _singleVaultArray(address(vault));

        vm.prank(user);
        helper.claimAllRewards(vaults, receiver, address(mockSWBERA));

        assertEq(wbera.balanceOf(address(helper)), 0, "helper should have no leftover WBERA");
        assertEq(mockSWBERA.balanceOf(receiver), earned, "receiver should have sWBERA shares");
    }

    function test_ClaimAllRewardsWithOutput_SWBERA_EmitsEvent() public {
        _distributeRewards();
        _stakeInVault(user, address(vault), address(busd), 100 ether);
        vm.warp(block.timestamp + 1 weeks);

        uint256 earned = vault.earned(user);
        address receiver = makeAddr("receiver");
        address[] memory vaults = _singleVaultArray(address(vault));

        vm.expectEmit(true, true, true, true);
        emit IRewardVaultHelper.RewardsClaimed(earned, receiver, address(mockSWBERA));

        vm.prank(user);
        helper.claimAllRewards(vaults, receiver, address(mockSWBERA));
    }

    function test_ClaimAllRewardsWithOutput_SWBERA_MultipleVaults() public {
        RewardVault vault2 = _createAndSetupSecondVault();

        _stakeInVault(user, address(vault), address(busd), 100 ether);
        dai.mint(user, 100 ether);
        _stakeInVault(user, address(vault2), address(dai), 100 ether);

        vm.warp(block.timestamp + 1 weeks);

        uint256 earned1 = vault.earned(user);
        uint256 earned2 = vault2.earned(user);
        uint256 totalExpected = earned1 + earned2;

        address[] memory vaults = new address[](2);
        vaults[0] = address(vault);
        vaults[1] = address(vault2);

        address receiver = makeAddr("receiver");

        vm.prank(user);
        helper.claimAllRewards(vaults, receiver, address(mockSWBERA));

        assertEq(mockSWBERA.balanceOf(receiver), totalExpected);
        assertEq(wbera.balanceOf(address(helper)), 0);
    }

    function test_ClaimAllRewardsWithOutput_WBERA_SendsDirectly() public {
        _distributeRewards();
        _stakeInVault(user, address(vault), address(busd), 100 ether);
        vm.warp(block.timestamp + 1 weeks);

        uint256 earned = vault.earned(user);
        assertGt(earned, 0);

        address[] memory vaults = _singleVaultArray(address(vault));
        address receiver = makeAddr("receiver");

        vm.prank(user);
        helper.claimAllRewards(vaults, receiver, WBERA_ADDR);

        assertEq(wbera.balanceOf(receiver), earned, "receiver should have WBERA");
        assertEq(wbera.balanceOf(address(helper)), 0, "helper should have no leftover WBERA");
    }

    function test_ClaimAllRewardsWithOutput_WBERA_EmitsEvent() public {
        _distributeRewards();
        _stakeInVault(user, address(vault), address(busd), 100 ether);
        vm.warp(block.timestamp + 1 weeks);

        uint256 earned = vault.earned(user);
        address receiver = makeAddr("receiver");
        address[] memory vaults = _singleVaultArray(address(vault));

        vm.expectEmit(true, true, true, true);
        emit IRewardVaultHelper.RewardsClaimed(earned, receiver, WBERA_ADDR);

        vm.prank(user);
        helper.claimAllRewards(vaults, receiver, WBERA_ADDR);
    }

    function test_ClaimAllRewardsWithOutput_NativeBERA() public {
        _distributeRewards();
        _stakeInVault(user, address(vault), address(busd), 100 ether);
        vm.warp(block.timestamp + 1 weeks);

        uint256 earned = vault.earned(user);
        assertGt(earned, 0);

        address[] memory vaults = _singleVaultArray(address(vault));
        address receiver = address(this);

        uint256 balBefore = receiver.balance;

        vm.prank(user);
        helper.claimAllRewards(vaults, receiver, address(0));

        assertEq(receiver.balance - balBefore, earned);
        assertEq(wbera.balanceOf(address(helper)), 0);
    }

    function test_ClaimAllRewardsWithOutput_EmptyVaults_NoRevert() public {
        address[] memory vaults = new address[](0);

        vm.prank(user);
        helper.claimAllRewards(vaults, user, address(mockSWBERA));

        assertEq(mockSWBERA.balanceOf(user), 0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   WITHDRAW FROM VAULTS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_WithdrawAllFromVaults_SingleVault() public {
        _stakeInVault(user, address(vault), address(busd), 100 ether);
        assertEq(vault.balanceOf(user), 100 ether);

        address receiver = makeAddr("receiver");
        address[] memory vaults = _singleVaultArray(address(vault));

        vm.prank(user);
        helper.withdrawAllFromVaults(vaults, receiver);

        assertEq(vault.balanceOf(user), 0);
        assertEq(busd.balanceOf(receiver), 100 ether);
        assertEq(busd.balanceOf(address(helper)), 0);
    }

    function test_WithdrawAllFromVaults_ReceiverIsCaller() public {
        _stakeInVault(user, address(vault), address(busd), 100 ether);

        address[] memory vaults = _singleVaultArray(address(vault));

        vm.prank(user);
        helper.withdrawAllFromVaults(vaults, user);

        assertEq(vault.balanceOf(user), 0);
        assertEq(busd.balanceOf(user), 100 ether);
    }

    function test_WithdrawAllFromVaults_MultipleVaults() public {
        RewardVault vault2 = _createAndSetupSecondVault();
        _stakeInVault(user, address(vault), address(busd), 100 ether);
        _stakeInVault(user, address(vault2), address(dai), 50 ether);

        address receiver = makeAddr("receiver");
        address[] memory vaults = new address[](2);
        vaults[0] = address(vault);
        vaults[1] = address(vault2);

        vm.prank(user);
        helper.withdrawAllFromVaults(vaults, receiver);

        assertEq(vault.balanceOf(user), 0);
        assertEq(vault2.balanceOf(user), 0);
        assertEq(busd.balanceOf(receiver), 100 ether);
        assertEq(dai.balanceOf(receiver), 50 ether);
        assertEq(busd.balanceOf(address(helper)), 0);
        assertEq(dai.balanceOf(address(helper)), 0);
    }

    function test_WithdrawAllFromVaults_SkipsVaultWithNoStake() public {
        RewardVault vault2 = _createAndSetupSecondVault();
        // user only stakes in `vault`, not `vault2`
        _stakeInVault(user, address(vault), address(busd), 100 ether);

        address receiver = makeAddr("receiver");
        address[] memory vaults = new address[](2);
        vaults[0] = address(vault2); // no stake here: must be skipped, not revert
        vaults[1] = address(vault);

        vm.prank(user);
        helper.withdrawAllFromVaults(vaults, receiver);

        assertEq(busd.balanceOf(receiver), 100 ether);
        assertEq(dai.balanceOf(receiver), 0);
        assertEq(vault.balanceOf(user), 0);
    }

    function test_WithdrawAllFromVaults_ExcludesDelegateStake() public {
        address delegate = makeAddr("delegate");
        _stakeInVault(user, address(vault), address(busd), 100 ether);
        _delegateStakeInVault(delegate, user, address(vault), address(busd), 40 ether);

        assertEq(vault.balanceOf(user), 140 ether);
        assertEq(vault.getTotalDelegateStaked(user), 40 ether);

        address receiver = makeAddr("receiver");
        address[] memory vaults = _singleVaultArray(address(vault));

        vm.prank(user);
        helper.withdrawAllFromVaults(vaults, receiver);

        // only the self-staked 100 is withdrawn; the delegate-staked 40 stays put
        assertEq(busd.balanceOf(receiver), 100 ether);
        assertEq(vault.balanceOf(user), 40 ether);
        assertEq(vault.getTotalDelegateStaked(user), 40 ether);
    }

    function test_WithdrawAllFromVaults_PreservesEarnedRewards() public {
        _distributeRewards();
        _stakeInVault(user, address(vault), address(busd), 100 ether);
        vm.warp(block.timestamp + 1 weeks);

        uint256 earnedBefore = vault.earned(user);
        assertGt(earnedBefore, 0);

        address[] memory vaults = _singleVaultArray(address(vault));

        vm.prank(user);
        helper.withdrawAllFromVaults(vaults, user);

        assertEq(vault.balanceOf(user), 0);
        assertEq(vault.earned(user), earnedBefore);
    }

    function test_WithdrawAllFromVaults_SecondCallWithdrawsNothing() public {
        _stakeInVault(user, address(vault), address(busd), 100 ether);
        address[] memory vaults = _singleVaultArray(address(vault));

        vm.prank(user);
        helper.withdrawAllFromVaults(vaults, user);
        uint256 balanceAfterFirst = busd.balanceOf(user);
        assertEq(balanceAfterFirst, 100 ether);

        vm.prank(user);
        helper.withdrawAllFromVaults(vaults, user);
        assertEq(busd.balanceOf(user), balanceAfterFirst);
    }

    function test_WithdrawAllFromVaults_EmptyArray_NoRevert() public {
        address[] memory vaults = new address[](0);

        vm.prank(user);
        helper.withdrawAllFromVaults(vaults, user);

        assertEq(busd.balanceOf(user), 0);
    }

    function test_WithdrawAllFromVaults_RevertsOnZeroReceiver() public {
        _stakeInVault(user, address(vault), address(busd), 100 ether);
        address[] memory vaults = _singleVaultArray(address(vault));

        vm.prank(user);
        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        helper.withdrawAllFromVaults(vaults, address(0));
    }

    function test_WithdrawAllFromVaults_RevertsWhenVaultPaused() public {
        _stakeInVault(user, address(vault), address(busd), 100 ether);

        // grant this contract the manager role, then the pauser role, then pause the vault.
        bytes32 managerRole = factory.VAULT_MANAGER_ROLE();
        bytes32 pauserRole = factory.VAULT_PAUSER_ROLE();
        vm.prank(governance);
        factory.grantRole(managerRole, address(this));
        factory.grantRole(pauserRole, address(this));
        vault.pause();

        address[] memory vaults = _singleVaultArray(address(vault));

        vm.prank(user);
        vm.expectRevert(); // PausableUpgradeable.EnforcedPause
        helper.withdrawAllFromVaults(vaults, user);
    }

    function _delegateStakeInVault(
        address _delegate,
        address _account,
        address _vault,
        address _token,
        uint256 _amount
    )
        internal
    {
        deal(_token, _delegate, _amount);
        vm.startPrank(_delegate);
        IERC20(_token).approve(_vault, _amount);
        RewardVault(payable(_vault)).delegateStake(_account, _amount);
        vm.stopPrank();
    }

    function _distributeRewards() internal {
        helper_SetDefaultRewardAllocation();
        distributor.distributeFor(
            DISTRIBUTE_FOR_TIMESTAMP, valData.index, valData.pubkey, valData.proposerIndexProof, valData.pubkeyProof
        );
    }

    function _stakeInVault(address _user, address _vault, address _token, uint256 _amount) internal {
        deal(_token, _user, _amount);
        vm.startPrank(_user);
        IERC20(_token).approve(_vault, _amount);
        RewardVault(payable(_vault)).stake(_amount);
        vm.stopPrank();
    }

    function _singleVaultArray(address _vault) internal pure returns (address[] memory vaults) {
        vaults = new address[](1);
        vaults[0] = _vault;
    }

    function _createAndSetupSecondVault() internal returns (RewardVault vault2) {
        vm.prank(governance);
        vault2 = RewardVault(payable(factory.createRewardVault(address(dai))));

        vm.startPrank(governance);
        IRewardAllocation.Weight[] memory weights = new IRewardAllocation.Weight[](2);
        weights[0] = IRewardAllocation.Weight(address(vault), 5000);
        weights[1] = IRewardAllocation.Weight(address(vault2), 5000);
        beraChef.setVaultWhitelistedStatus(address(vault), true, "");
        beraChef.setVaultWhitelistedStatus(address(vault2), true, "");
        beraChef.setDefaultRewardAllocation(IRewardAllocation.RewardAllocation(1, weights));
        vm.stopPrank();

        vm.prank(0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE);
        distributor.distributeFor(valData.pubkey);
    }
}
