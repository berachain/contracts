// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC1967 } from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import { IBeaconDeposit } from "src/pol/interfaces/IBeaconDeposit.sol";
import { IBeraChef } from "src/pol/interfaces/IBeraChef.sol";
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
    bytes32 internal managerRole;

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual override {
        initDefaultRewardAllocation = false;
        super.setUp();

        defaultAdminRole = distributor.DEFAULT_ADMIN_ROLE();
        managerRole = distributor.MANAGER_ROLE();

        vm.prank(governance);
        distributor.grantRole(managerRole, manager);
    }

    /// @dev Ensure that the contract is owned by the governance.
    function test_OwnerIsGovernance() public virtual {
        assert(distributor.hasRole(defaultAdminRole, governance));
    }

    /// @dev Should fail if not the owner
    function test_FailIfNotOwner() public virtual {
        vm.expectRevert();
        distributor.revokeRole(defaultAdminRole, governance);

        address rnd = makeAddr("address");
        vm.expectRevert();
        distributor.grantRole(managerRole, rnd);

        address newImpl = address(new Distributor());
        vm.expectRevert();
        distributor.upgradeToAndCall(newImpl, bytes(""));
    }

    /// @dev Should fail if not the manager
    function test_FailIfNotManager() public virtual {
        vm.expectRevert();
        distributor.setZeroValidatorPubkeyGIndex(0);

        vm.prank(manager);
        distributor.setZeroValidatorPubkeyGIndex(0);
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

    /// @dev Test when the reward rate is zero.
    function test_ZeroRewards() public {
        vm.startPrank(governance);
        blockRewardController.setRewardRate(0);
        blockRewardController.setMinBoostedRewardRate(0);
        vm.stopPrank();

        // expect a call to process the rewards
        bytes memory data =
            abi.encodeCall(IBlockRewardController.processRewards, (valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, false));
        vm.expectCall(address(blockRewardController), data, 1);
        // expect no call to mint BGT
        data = abi.encodeCall(IBGT.mint, (address(distributor), TEST_BGT_PER_BLOCK));
        vm.expectCall(address(bgt), data, 0);

        distributor.distributeFor(
            DISTRIBUTE_FOR_TIMESTAMP, valData.index, valData.pubkey, valData.proposerIndexProof, valData.pubkeyProof
        );
        assertEq(bgt.allowance(address(distributor), address(vault)), 0);
    }

    /// @dev Test that in genesis no bgts are left unallocated in the distributor.
    function test_DistributeDuringGenesisNoBgtWaste() public {
        vm.startPrank(governance);
        blockRewardController.setRewardRate(1e18);
        blockRewardController.setMinBoostedRewardRate(1e18);
        vm.stopPrank();

        BlockRewardController brc = BlockRewardController(address(distributor.blockRewardController()));
        address valOperator = IBeaconDeposit(brc.beaconDepositContract()).getOperator(valData.pubkey);

        uint256 distributorBgtBefore = bgt.balanceOf(address(distributor));
        uint256 valOperatorBgtBefore = bgt.balanceOf(valOperator);

        distributor.distributeFor(
            DISTRIBUTE_FOR_TIMESTAMP, valData.index, valData.pubkey, valData.proposerIndexProof, valData.pubkeyProof
        );

        assertEq(bgt.allowance(address(distributor), address(vault)), 0);
        // distributor should have same bgts as before
        assertEq(bgt.balanceOf(address(distributor)), distributorBgtBefore);
        // validator operator should receive base rate as well in genesis
        assertEq(bgt.balanceOf(valOperator), valOperatorBgtBefore + blockRewardController.baseRate());
    }

    /// @dev Distribute using the default reward allocation if none is set.
    function test_Distribute() public {
        helper_SetDefaultRewardAllocation();
        // expect a call to process the rewards
        bytes memory data =
            abi.encodeCall(IBlockRewardController.processRewards, (valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, true));
        vm.expectCall(address(blockRewardController), data, 1);
        // expect a call to mint the BGT to the distributor
        data = abi.encodeCall(IBGT.mint, (address(distributor), TEST_BGT_PER_BLOCK));
        vm.expectCall(address(bgt), data, 1);
        // expect single call to check if ready then activate the queued reward allocation
        // although it wont activate the queued reward allocation since it nothing is queued.
        data = abi.encodeCall(IBeraChef.activateReadyQueuedRewardAllocation, (valData.pubkey));
        vm.expectCall(address(beraChef), data, 1);

        vm.expectEmit(true, true, true, true);
        emit IDistributor.Distributed(valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, address(vault), TEST_BGT_PER_BLOCK);
        distributor.distributeFor(
            DISTRIBUTE_FOR_TIMESTAMP, valData.index, valData.pubkey, valData.proposerIndexProof, valData.pubkeyProof
        );

        // check that the default reward allocation was used
        // `getActiveRewardAllocation` should return default reward allocation as there was no active reward allocation
        // queued by the validator
        // the default reward allocation was set with `1` as startBlock in RootHelperTest.
        assertEq(beraChef.getActiveRewardAllocation(valData.pubkey).startBlock, 1);
        assertEq(bgt.allowance(address(distributor), address(vault)), TEST_BGT_PER_BLOCK);
    }

    /// @dev Test the `multicall` function for distributeFor.
    function test_DistributeMulticall() public {
        helper_SetDefaultRewardAllocation();
        // expect 3 calls to process the rewards
        bytes memory data =
            abi.encodeCall(IBlockRewardController.processRewards, (valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, true));
        vm.expectCall(address(blockRewardController), data, 1);
        data =
            abi.encodeCall(IBlockRewardController.processRewards, (valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP + 1, true));
        vm.expectCall(address(blockRewardController), data, 1);
        data =
            abi.encodeCall(IBlockRewardController.processRewards, (valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP + 2, true));
        vm.expectCall(address(blockRewardController), data, 1);
        // expect 3 calls to mint the BGT to the distributor
        data = abi.encodeCall(IBGT.mint, (address(distributor), TEST_BGT_PER_BLOCK));
        vm.expectCall(address(bgt), data, 3);
        // expect 3 calls to check if ready then activate the queued reward allocation
        // although it wont activate the queued reward allocation since it nothing is queued.
        data = abi.encodeCall(IBeraChef.activateReadyQueuedRewardAllocation, (valData.pubkey));
        vm.expectCall(address(beraChef), data, 3);

        // call distributeFor 3 times in a single multicall
        bytes[] memory callData = new bytes[](3);
        bytes4 selector = bytes4(keccak256("distributeFor(uint64,uint64,bytes,bytes32[],bytes32[])"));
        callData[0] = abi.encodeWithSelector(
            selector,
            DISTRIBUTE_FOR_TIMESTAMP,
            valData.index,
            valData.pubkey,
            valData.proposerIndexProof,
            valData.pubkeyProof
        );
        callData[1] = abi.encodeWithSelector(
            selector,
            DISTRIBUTE_FOR_TIMESTAMP + 1,
            valData.index,
            valData.pubkey,
            valData.proposerIndexProof,
            valData.pubkeyProof
        );
        callData[2] = abi.encodeWithSelector(
            selector,
            DISTRIBUTE_FOR_TIMESTAMP + 2,
            valData.index,
            valData.pubkey,
            valData.proposerIndexProof,
            valData.pubkeyProof
        );
        distributor.multicall(callData);

        // check that all BGT were distributed
        assertEq(beraChef.getActiveRewardAllocation(valData.pubkey).startBlock, 1);
        assertEq(bgt.allowance(address(distributor), address(vault)), 3 * TEST_BGT_PER_BLOCK);
    }

    /// @dev Activate the queued reward allocation if it is ready and distribute the rewards.
    function test_DistributeAndActivateQueuedRewardAllocation() public {
        helper_SetDefaultRewardAllocation();
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] = IBeraChef.Weight(address(vault), 10_000);
        uint64 startBlock = uint64(block.number + 2);

        vm.prank(operator);
        beraChef.queueNewRewardAllocation(valData.pubkey, startBlock, weights);

        // Distribute the rewards.
        vm.roll(startBlock);
        vm.prank(manager);

        // expect a call to process the rewards
        bytes memory data =
            abi.encodeCall(IBlockRewardController.processRewards, (valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, true));
        vm.expectCall(address(blockRewardController), data, 1);
        // expect a call to mint the BGT to the distributor
        data = abi.encodeCall(IBGT.mint, (address(distributor), TEST_BGT_PER_BLOCK));
        vm.expectCall(address(bgt), data, 1);
        // expect a call to activate the queued reward allocation
        data = abi.encodeCall(IBeraChef.activateReadyQueuedRewardAllocation, (valData.pubkey));
        vm.expectCall(address(beraChef), data, 1);

        vm.expectEmit(true, true, true, true);
        emit IDistributor.Distributed(valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, address(vault), TEST_BGT_PER_BLOCK);
        distributor.distributeFor(
            DISTRIBUTE_FOR_TIMESTAMP, valData.index, valData.pubkey, valData.proposerIndexProof, valData.pubkeyProof
        );

        // check that the queued reward allocation was activated
        assertEq(beraChef.getActiveRewardAllocation(valData.pubkey).startBlock, startBlock);
        assertEq(bgt.allowance(address(distributor), address(vault)), TEST_BGT_PER_BLOCK);
    }

    function test_DistributeForNonReentrant() public {
        ReentrantERC20 reentrantERC20 = new ReentrantERC20();

        reentrantERC20.setMakeExternalCall(true);
        reentrantERC20.setDistributeData(
            address(distributor),
            DISTRIBUTE_FOR_TIMESTAMP,
            valData.index,
            valData.pubkey,
            valData.proposerIndexProof,
            valData.pubkeyProof
        );

        _helper_addIncentives(address(reentrantERC20), 100 ether, 100 * 1e18);

        // Inside this test there're already some assert which check that core functions like
        // 'processRewards' and 'mint' are called only once
        test_DistributeAndActivateQueuedRewardAllocation();
    }

    function _helper_addIncentives(address token, uint256 amount, uint256 _incentiveRate) internal {
        _helper_WhitelistIncentiveToken(token);
        // mint dai and approve vault to use the tokens on behalf of the user
        ReentrantERC20(token).mint(address(this), type(uint256).max);
        ReentrantERC20(token).approve(address(vault), type(uint256).max);

        vault.addIncentive(token, amount, _incentiveRate);

        // check the dai incentive data
        (uint256 minIncentiveRate, uint256 incentiveRate, uint256 amountRemaining,) = vault.incentives(token);
        assertEq(minIncentiveRate, 100 * 1e18);
        assertEq(incentiveRate, _incentiveRate);
        assertEq(amountRemaining, amount);
    }

    function _helper_WhitelistIncentiveToken(address token) public {
        uint256 count = vault.getWhitelistedTokensCount();

        // Whitelist the token
        vm.prank(governance);
        vault.whitelistIncentiveToken(token, 100 * 1e18, address(this));

        // Verify the token was whitelisted
        (uint256 minIncentiveRate, uint256 incentiveRate,,) = vault.incentives(token);
        assertEq(minIncentiveRate, 100 * 1e18);
        assertEq(incentiveRate, 100 * 1e18);

        // Verify the token was added to the list of whitelisted tokens
        assertEq(vault.getWhitelistedTokensCount(), count + 1);
        assertEq(vault.whitelistedTokens(count), token);
    }

    function testFuzz_DistributeDoesNotLeaveDust(uint256 weight) public {
        helper_SetDefaultRewardAllocation();
        uint256 MAX_WEIGHT = 10_000; // 100%
        weight = _bound(weight, 1, MAX_WEIGHT - 1);
        address stakingToken = address(new MockERC20());
        address vault2 = factory.createRewardVault(stakingToken);
        vm.prank(governance);
        beraChef.setVaultWhitelistedStatus(vault2, true, "");

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](2);
        weights[0] = IBeraChef.Weight(address(vault), uint96(weight));
        weights[1] = IBeraChef.Weight(vault2, uint96(MAX_WEIGHT - weight));
        uint64 startBlock = uint64(block.number + 2);

        vm.prank(operator);
        beraChef.queueNewRewardAllocation(valData.pubkey, startBlock, weights);

        // Distribute the rewards.
        vm.roll(startBlock);
        vm.prank(manager);

        // BGT balance before distribute
        uint256 vaultAllowanceBefore = bgt.allowance(address(distributor), address(vault));
        uint256 vault2AllowanceBefore = bgt.allowance(address(distributor), vault2);
        distributor.distributeFor(
            DISTRIBUTE_FOR_TIMESTAMP, valData.index, valData.pubkey, valData.proposerIndexProof, valData.pubkeyProof
        );
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
        uint256 rewardDistributed =
            blockRewardController.processRewards(valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, true);
        assertEq(vaultRewards + vault2Rewards, rewardDistributed);
    }

    function testFuzz_DistributeDoesNotLeaveDust(
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

        testFuzz_DistributeDoesNotLeaveDust(weight);
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
        vm.prank(0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE);
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

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](2);
        weights[0] = IBeraChef.Weight(address(vault), 5000);
        weights[1] = IBeraChef.Weight(vault2, 5000);

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
        vm.prank(0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE);
        distributor.distributeFor(valData.pubkey);

        // check that the queued reward allocation was activated
        assertEq(beraChef.getActiveRewardAllocation(valData.pubkey).startBlock, uint64(block.number));
        assertEq(bgt.allowance(address(distributor), address(vault)), TEST_BGT_PER_BLOCK / 2);
        assertEq(bgt.allowance(address(distributor), vault2), TEST_BGT_PER_BLOCK / 2);
    }

    /// @dev Test that permissionless distributeFor function fails after Pectra11 hard fork.
    function test_PermissionlessDistributeFor_AfterHardFork() public {
        // Set timestamp to after Pectra11 hard fork
        uint64 postHardForkTimestamp = 1_756_915_201; // PECTRA11_HARD_FORK_TIMESTAMP + 1
        testFuzz_PermissionlessDistributeFor_AfterHardFork(postHardForkTimestamp);
    }

    /// @dev Test that permissionless distributeFor function fails starting from Pectra11 hard fork.
    function testFuzz_PermissionlessDistributeFor_AfterHardFork(uint64 timestamp) public {
        helper_SetDefaultRewardAllocation();
        // start from Pectra11 hard fork timestamp
        timestamp = uint64(bound(timestamp, 1_756_915_201, type(uint64).max));

        // expect the function to revert with OnlySystemCallAllowed error
        vm.expectRevert(IPOLErrors.OnlySystemCallAllowed.selector);
        distributor.distributeFor(
            timestamp, valData.index, valData.pubkey, valData.proposerIndexProof, valData.pubkeyProof
        );
        // Verify no BGT was distributed
        assertEq(bgt.allowance(address(distributor), address(vault)), 0);
    }
}
