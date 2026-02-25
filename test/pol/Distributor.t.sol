// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC1967 } from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import { IBeaconDeposit } from "src/pol/interfaces/IBeaconDeposit.sol";
import { IBeraChef } from "src/pol/interfaces/IBeraChef.sol";
import { IRewardAllocation } from "src/pol/interfaces/IRewardAllocation.sol";
import { IBGT } from "src/pol/interfaces/IBGT.sol";
import { IBlockRewardController } from "src/pol/interfaces/IBlockRewardController.sol";
import { IDistributor } from "src/pol/interfaces/IDistributor.sol";
import { IPOLErrors } from "src/pol/interfaces/IPOLErrors.sol";
import { BeraChef } from "src/pol/rewards/BeraChef.sol";
import { BlockRewardController } from "src/pol/rewards/BlockRewardController.sol";
import { Distributor } from "src/pol/rewards/Distributor.sol";
import { RewardVault } from "src/pol/rewards/RewardVault.sol";

import { BeaconRootsHelperTest } from "./BeaconRootsHelper.t.sol";
import { MockHoney } from "@mock/honey/MockHoney.sol";
import { ReentrantERC20 } from "@mock/token/ReentrantERC20.sol";
import { MockERC20 } from "@mock/token/MockERC20.sol";

contract DistributorTest is BeaconRootsHelperTest {
    address internal manager = makeAddr("manager");
    bytes32 internal defaultAdminRole;

    /// @dev The system address used by the execution layer client.
    address internal constant SYSTEM_ADDRESS = 0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE;

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual override {
        initDefaultRewardAllocation = false;
        super.setUp();

        defaultAdminRole = distributor.DEFAULT_ADMIN_ROLE();
    }

    /// @dev Ensure that the contract is owned by the governance.
    function test_OwnerIsGovernance() public virtual {
        assert(distributor.hasRole(defaultAdminRole, governance));
    }

    /// @dev Should fail if not the owner
    function test_FailIfNotOwner() public virtual {
        vm.expectRevert();
        distributor.revokeRole(defaultAdminRole, governance);

        address newImpl = address(new Distributor());
        vm.expectRevert();
        distributor.upgradeToAndCall(newImpl, bytes(""));
    }

    /// @dev Distribute rewards via the system-call path. Used by downstream tests as a setup helper.
    function test_Distribute() public virtual {
        helper_SetDefaultRewardAllocation();
        vm.prank(SYSTEM_ADDRESS);
        distributor.distributeFor(valData.pubkey);
    }

    /// @dev Should upgrade to a new implementation
    function test_UpgradeTo() public virtual {
        address newImpl = address(new Distributor());
        vm.expectEmit(true, true, true, true);
        emit IERC1967.Upgraded(newImpl);
        vm.prank(governance);
        distributor.upgradeToAndCall(newImpl, bytes(""));
        assertEq(vm.load(address(distributor), ERC1967Utils.IMPLEMENTATION_SLOT), bytes32(uint256(uint160(newImpl))));
    }

    /// @dev Should fail if initialize again
    function test_FailIfInitializeAgain() public virtual {
        vm.expectRevert();
        distributor.initialize(
            address(beraChef),
            address(bgt),
            address(blockRewardController),
            governance,
            ZERO_VALIDATOR_PUBKEY_G_INDEX_ELECTRA,
            PROPOSER_INDEX_G_INDEX
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    SYSTEM CALL TESTS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Test that the new distributeFor function with only pubkey parameter works when called by system address.
    function test_DistributeForSystemCall() public {
        helper_SetDefaultRewardAllocation();

        // expect a call to process the rewards
        bytes memory data =
            abi.encodeCall(IBlockRewardController.processRewards, (valData.pubkey, uint64(block.timestamp), true));
        vm.expectCall(address(blockRewardController), data, 1);

        // expect a call to mint the BGT to the distributor
        data = abi.encodeCall(IBGT.mint, (address(distributor), TEST_BGT_PER_BLOCK));
        vm.expectCall(address(bgt), data, 1);

        // expect a call to activate the queued reward allocation
        data = abi.encodeCall(IBeraChef.activateReadyQueuedRewardAllocation, (valData.pubkey));
        vm.expectCall(address(beraChef), data, 1);

        vm.expectEmit(true, true, true, true);
        emit IDistributor.Distributed(valData.pubkey, uint64(block.timestamp), address(vault), TEST_BGT_PER_BLOCK);

        // Call as system address
        vm.prank(SYSTEM_ADDRESS);
        distributor.distributeFor(valData.pubkey);

        assertEq(bgt.allowance(address(distributor), address(vault)), TEST_BGT_PER_BLOCK);
    }

    /// @dev Test that the new distributeFor function fails when called by non-system address.
    function test_DistributeForSystemCall_FailIfNotSystemAddress() public {
        helper_SetDefaultRewardAllocation();
        // Try to call as a regular address
        vm.expectRevert(IPOLErrors.NotSystemAddress.selector);
        distributor.distributeFor(valData.pubkey);

        // Try to call as governance
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.NotSystemAddress.selector);
        distributor.distributeFor(valData.pubkey);
    }

    /// @dev Test that the new distributeFor function works correctly with
    /// same block queued reward allocation activation.
    function test_DistributeForSystemCall_WithSameBlockQueuedRewardAllocationActivation() public {
        helper_SetDefaultRewardAllocation();

        address stakingToken = address(new MockERC20());
        address vault2 = factory.createRewardVault(stakingToken);
        vm.prank(governance);
        beraChef.setVaultWhitelistedStatus(vault2, true, "");

        IRewardAllocation.Weight[] memory weights = new IRewardAllocation.Weight[](2);
        weights[0] = IRewardAllocation.Weight(address(vault), 5000);
        weights[1] = IRewardAllocation.Weight(vault2, 5000);

        vm.prank(operator);
        beraChef.queueNewRewardAllocation(valData.pubkey, uint64(block.number), weights);

        // expect a call to process the rewards
        bytes memory data =
            abi.encodeCall(IBlockRewardController.processRewards, (valData.pubkey, uint64(block.timestamp), true));
        vm.expectCall(address(blockRewardController), data, 1);

        // expect a call to mint the BGT to the distributor
        data = abi.encodeCall(IBGT.mint, (address(distributor), TEST_BGT_PER_BLOCK));
        vm.expectCall(address(bgt), data, 1);

        // expect a call to activate the queued reward allocation
        data = abi.encodeCall(IBeraChef.activateReadyQueuedRewardAllocation, (valData.pubkey));
        vm.expectCall(address(beraChef), data, 1);

        vm.expectEmit(true, true, true, true);
        emit IDistributor.Distributed(valData.pubkey, uint64(block.timestamp), address(vault), TEST_BGT_PER_BLOCK / 2);
        emit IDistributor.Distributed(valData.pubkey, uint64(block.timestamp), vault2, TEST_BGT_PER_BLOCK / 2);

        // Call as system address
        vm.prank(SYSTEM_ADDRESS);
        distributor.distributeFor(valData.pubkey);

        // check that the queued reward allocation was activated
        assertEq(beraChef.getActiveRewardAllocation(valData.pubkey).startBlock, uint64(block.number));
        assertEq(bgt.allowance(address(distributor), address(vault)), TEST_BGT_PER_BLOCK / 2);
        assertEq(bgt.allowance(address(distributor), vault2), TEST_BGT_PER_BLOCK / 2);
    }

    /// @dev Test when the reward rate is zero via system call.
    function test_SystemCall_ZeroRewards() public {
        vm.startPrank(governance);
        blockRewardController.setRewardRate(0);
        blockRewardController.setMinBoostedRewardRate(0);
        vm.stopPrank();

        // expect a call to process the rewards
        bytes memory data =
            abi.encodeCall(IBlockRewardController.processRewards, (valData.pubkey, uint64(block.timestamp), false));
        vm.expectCall(address(blockRewardController), data, 1);
        // expect no call to mint BGT
        data = abi.encodeCall(IBGT.mint, (address(distributor), TEST_BGT_PER_BLOCK));
        vm.expectCall(address(bgt), data, 0);

        vm.prank(SYSTEM_ADDRESS);
        distributor.distributeFor(valData.pubkey);
        assertEq(bgt.allowance(address(distributor), address(vault)), 0);
    }

    /// @dev Test that in genesis no bgts are left unallocated in the distributor via system call.
    function test_SystemCall_DistributeDuringGenesisNoBgtWaste() public {
        vm.startPrank(governance);
        blockRewardController.setRewardRate(1e18);
        blockRewardController.setMinBoostedRewardRate(1e18);
        vm.stopPrank();

        BlockRewardController brc = BlockRewardController(address(distributor.blockRewardController()));
        address valOperator = IBeaconDeposit(brc.beaconDepositContract()).getOperator(valData.pubkey);

        uint256 distributorBgtBefore = bgt.balanceOf(address(distributor));
        uint256 valOperatorBgtBefore = bgt.balanceOf(valOperator);

        vm.prank(SYSTEM_ADDRESS);
        distributor.distributeFor(valData.pubkey);

        assertEq(bgt.allowance(address(distributor), address(vault)), 0);
        // distributor should have same bgts as before
        assertEq(bgt.balanceOf(address(distributor)), distributorBgtBefore);
        // validator operator should receive base rate as well in genesis
        assertEq(bgt.balanceOf(valOperator), valOperatorBgtBefore + blockRewardController.baseRate());
    }

    /// @dev Test dust-free distribution via system call with two vaults.
    function testFuzz_SystemCall_DistributeDoesNotLeaveDust(uint256 weight) public {
        helper_SetDefaultRewardAllocation();
        uint256 MAX_WEIGHT = 10_000; // 100%
        weight = _bound(weight, 1, MAX_WEIGHT - 1);
        address stakingToken = address(new MockERC20());
        address vault2 = factory.createRewardVault(stakingToken);
        vm.prank(governance);
        beraChef.setVaultWhitelistedStatus(vault2, true, "");

        IRewardAllocation.Weight[] memory weights = new IRewardAllocation.Weight[](2);
        weights[0] = IRewardAllocation.Weight(address(vault), uint96(weight));
        weights[1] = IRewardAllocation.Weight(vault2, uint96(MAX_WEIGHT - weight));
        uint64 startBlock = uint64(block.number + 2);

        vm.prank(operator);
        beraChef.queueNewRewardAllocation(valData.pubkey, startBlock, weights);

        // Distribute the rewards.
        vm.roll(startBlock);

        // BGT balance before distribute
        uint256 vaultAllowanceBefore = bgt.allowance(address(distributor), address(vault));
        uint256 vault2AllowanceBefore = bgt.allowance(address(distributor), vault2);

        vm.prank(SYSTEM_ADDRESS);
        distributor.distributeFor(valData.pubkey);

        uint256 vaultRewards;
        uint256 vault2Rewards;
        {
            uint256 vaultAllowanceAfter = bgt.allowance(address(distributor), address(vault));
            uint256 vault2AllowanceAfter = bgt.allowance(address(distributor), vault2);
            vaultRewards = vaultAllowanceAfter - vaultAllowanceBefore;
            vault2Rewards = vault2AllowanceAfter - vault2AllowanceBefore;
        }

        // Cal this to know the exact total amount of rewards distributed
        vm.prank(address(distributor));
        uint256 rewardDistributed = blockRewardController.processRewards(valData.pubkey, uint64(block.timestamp), true);
        assertEq(vaultRewards + vault2Rewards, rewardDistributed);
    }

    function testFuzz_SystemCall_DistributeDoesNotLeaveDust(
        uint256 weight,
        uint256 rewardRate,
        uint256 minReward,
        uint256 multiplier,
        uint256 convexity
    )
        public
    {
        rewardRate = _bound(rewardRate, 0, blockRewardController.MAX_REWARD_RATE());
        minReward = _bound(minReward, 0, blockRewardController.MAX_MIN_BOOSTED_REWARD_RATE());
        multiplier = _bound(multiplier, 0, blockRewardController.MAX_BOOST_MULTIPLIER());
        convexity = _bound(convexity, 1, blockRewardController.MAX_REWARD_CONVEXITY());

        vm.startPrank(governance);
        blockRewardController.setRewardRate(rewardRate);
        blockRewardController.setMinBoostedRewardRate(minReward);
        blockRewardController.setBoostMultiplier(multiplier);
        blockRewardController.setRewardConvexity(convexity);
        vm.stopPrank();

        vm.deal(address(bgt), address(bgt).balance + rewardRate * multiplier / 1e18); // add max bgt minted in a block

        testFuzz_SystemCall_DistributeDoesNotLeaveDust(weight);
    }
}
