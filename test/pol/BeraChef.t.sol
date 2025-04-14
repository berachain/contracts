// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC1967 } from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IBeraChef, IPOLErrors } from "src/pol/interfaces/IBeraChef.sol";
import { BeraChef } from "src/pol/rewards/BeraChef.sol";
import { RewardVault } from "src/pol/rewards/RewardVault.sol";

import { POLTest, Vm } from "./POL.t.sol";
import { MockHoney } from "@mock/honey/MockHoney.sol";

contract BeraChefTest is POLTest {
    address internal receiver;
    address internal receiver2;
    address internal stakeTokenVault;
    address internal stakeTokenVault2;

    /// @dev A function invoked before each test case is run.
    function setUp() public override {
        super.setUp();

        stakeTokenVault = address(new MockHoney());
        stakeTokenVault2 = address(new MockHoney());

        vm.startPrank(governance);
        receiver = factory.createRewardVault(address(stakeTokenVault));
        receiver2 = factory.createRewardVault(address(stakeTokenVault2));

        // Become frens with the chef.
        beraChef.setVaultWhitelistedStatus(receiver, true, "");
        beraChef.setVaultWhitelistedStatus(receiver2, true, "");
        vm.stopPrank();
    }

    /* Admin functions */

    /// @dev Ensure that the contract is owned by the governance.
    function test_OwnerIsGovernance() public view {
        assertEq(beraChef.owner(), governance);
    }

    /// @dev Should fail if not the owner
    function test_FailIfNotOwner() public {
        vm.expectRevert();
        beraChef.transferOwnership(address(1));

        vm.expectRevert();
        beraChef.setMaxNumWeightsPerRewardAllocation(255);

        vm.expectRevert();
        beraChef.setMaxWeightPerVault(1000);

        vm.expectRevert();
        beraChef.setRewardAllocationBlockDelay(255);

        vm.expectRevert();
        beraChef.setVaultWhitelistedStatus(receiver, true, "");

        vm.expectRevert();
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] = IBeraChef.Weight(governance, 10_000);
        beraChef.setDefaultRewardAllocation(IBeraChef.RewardAllocation(0, weights));

        address newImpl = address(new BeraChef());
        vm.expectRevert();
        beraChef.upgradeToAndCall(newImpl, bytes(""));
    }

    /// @dev Should upgrade to a new implementation
    function test_UpgradeTo() public {
        address newImpl = address(new BeraChef());
        vm.expectEmit(true, true, true, true);
        emit IERC1967.Upgraded(newImpl);
        vm.prank(governance);
        beraChef.upgradeToAndCall(newImpl, bytes(""));
        assertEq(vm.load(address(beraChef), ERC1967Utils.IMPLEMENTATION_SLOT), bytes32(uint256(uint160(newImpl))));
    }

    /// @dev Should fail if initialize again
    function test_FailIfInitializeAgain() public {
        vm.expectRevert();
        beraChef.initialize(address(distributor), address(factory), address(governance), beaconDepositContract, 1);
    }

    function test_SetMaxNumWeightsPerRewardAllocation_FailWithZero() public {
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.MaxNumWeightsPerRewardAllocationIsZero.selector);
        beraChef.setMaxNumWeightsPerRewardAllocation(0);
    }

    function test_SetMaxNumWeightsPerRewardAllocation_FailIfInvalidateDefaultRewardAllocation() public {
        vm.startPrank(governance);
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](2);
        weights[0] = IBeraChef.Weight(receiver, 5000);
        weights[1] = IBeraChef.Weight(receiver2, 5000);

        vm.expectEmit(true, true, true, true);
        emit IBeraChef.SetDefaultRewardAllocation(IBeraChef.RewardAllocation(1, weights));
        beraChef.setDefaultRewardAllocation(IBeraChef.RewardAllocation(1, weights));

        // Default reward allocation is set with 2 weights
        vm.expectRevert(IPOLErrors.InvalidateDefaultRewardAllocation.selector);
        beraChef.setMaxNumWeightsPerRewardAllocation(1);
    }

    /// @dev Should set the max number of weights per reward allocation
    function test_SetMaxNumWeightsPerRewardAllocation() public {
        vm.expectEmit(true, true, true, true);
        emit IBeraChef.MaxNumWeightsPerRewardAllocationSet(255);
        vm.prank(governance);
        beraChef.setMaxNumWeightsPerRewardAllocation(255);
        assertEq(beraChef.maxNumWeightsPerRewardAllocation(), 255);
    }

    /// @dev Should set the max number of weights per reward allocation
    function testFuzz_SetMaxNumWeightsPerRewardAllocation(uint8 seed) public {
        seed = uint8(bound(seed, 1, type(uint8).max));
        vm.prank(governance);
        beraChef.setMaxNumWeightsPerRewardAllocation(seed);
        assertEq(beraChef.maxNumWeightsPerRewardAllocation(), seed);
    }

    function test_SetMaxWeightPerVault_FailInvalid() public {
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.InvalidMaxWeightPerVault.selector);
        beraChef.setMaxWeightPerVault(0);

        vm.prank(governance);
        vm.expectRevert(IPOLErrors.InvalidMaxWeightPerVault.selector);
        beraChef.setMaxWeightPerVault(1e4 + 1);
    }

    function test_SetMaxWeightPerVault_FailIfInvalidateDefaultRewardAllocation() public {
        vm.startPrank(governance);
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](2);
        weights[0] = IBeraChef.Weight(receiver, 5000);
        weights[1] = IBeraChef.Weight(receiver2, 5000);

        vm.expectEmit(true, true, true, true);
        emit IBeraChef.SetDefaultRewardAllocation(IBeraChef.RewardAllocation(1, weights));
        beraChef.setDefaultRewardAllocation(IBeraChef.RewardAllocation(1, weights));

        // Default reward allocation is set with 2 weights
        vm.expectRevert(IPOLErrors.InvalidateDefaultRewardAllocation.selector);
        beraChef.setMaxWeightPerVault(4000);
    }

    /// @dev Should set the max number of weights per reward allocation
    function test_SetMaxWeightPerVault() public {
        vm.expectEmit(true, true, true, true);
        emit IBeraChef.MaxWeightPerVaultSet(0.2e4);
        vm.prank(governance);
        beraChef.setMaxWeightPerVault(uint96(0.2e4));
        assertEq(beraChef.maxWeightPerVault(), 0.2e4);
    }

    /// @dev Should set the max number of weights per reward allocation
    function testFuzz_SetMaxWeightPerVault(uint96 w) public {
        uint96 minValid = uint96(1e4) / beraChef.maxNumWeightsPerRewardAllocation();
        minValid += (uint96(1e4) % beraChef.maxNumWeightsPerRewardAllocation() == 0 ? 0 : 1); // ceil value

        w = uint96(bound(w, minValid, 1e4));
        vm.prank(governance);
        beraChef.setMaxWeightPerVault(w);
        assertEq(beraChef.maxWeightPerVault(), w);
    }

    /// @dev Should set the reward allocation block delay
    function test_SetRewardAllocationBlockDelay() public {
        vm.expectEmit(true, true, true, true);
        emit IBeraChef.RewardAllocationBlockDelaySet(255);
        vm.prank(governance);
        beraChef.setRewardAllocationBlockDelay(255);
        assertEq(beraChef.rewardAllocationBlockDelay(), 255);
    }

    /// @dev Should set the reward allocation block delay
    function testFuzz_SetRewardAllocationBlockDelay(uint64 seed) public {
        uint64 maxDelay = beraChef.MAX_REWARD_ALLOCATION_BLOCK_DELAY();
        seed = uint64(bound(seed, 0, maxDelay));
        vm.prank(governance);
        beraChef.setRewardAllocationBlockDelay(seed);
        assertEq(beraChef.rewardAllocationBlockDelay(), seed);
    }

    function testFuzz_SetRewardAllocationBlockDelay_FailsIfDelayTooLarge(uint64 seed) public {
        uint64 maxDelay = beraChef.MAX_REWARD_ALLOCATION_BLOCK_DELAY();
        seed = uint64(bound(seed, maxDelay + 1, type(uint64).max));
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.RewardAllocationBlockDelayTooLarge.selector);
        beraChef.setRewardAllocationBlockDelay(seed);
    }

    /// @dev Should update the whitelisted vaults
    function test_updateWhitelistedVaults() public {
        vm.expectEmit(true, true, true, true);
        emit IBeraChef.VaultWhitelistedStatusUpdated(receiver, true, "test");
        vm.prank(governance);
        beraChef.setVaultWhitelistedStatus(receiver, true, "test");
        assertTrue(beraChef.isWhitelistedVault(receiver));
    }

    function test_updateWhitelistedVaultMetadata() public {
        vm.expectEmit(true, true, true, true);
        emit IBeraChef.WhitelistedVaultMetadataUpdated(receiver, "test_update");
        vm.prank(governance);
        beraChef.updateWhitelistedVaultMetadata(receiver, "test_update");
    }

    function test_updateWhitelistedVaultMetadata_FailIfNotWhitelisted() public {
        address notWhitelistedReceiver = makeAddr("notWhitelistedReceiver");
        vm.expectRevert(IPOLErrors.NotWhitelistedVault.selector);
        vm.prank(governance);
        beraChef.updateWhitelistedVaultMetadata(notWhitelistedReceiver, "testNotWhitelisted");
    }

    function test_updateWhitelistedVaultMetadata_FailIfNotOwner() public {
        vm.expectRevert();
        beraChef.updateWhitelistedVaultMetadata(receiver, "testNotOwner");
    }

    function testFuzz_FailUpdateWhitelistedVaultsNotRegistered() public {
        address receiver3 = address(new RewardVault());
        // Fail while whitelisting
        vm.startPrank(governance);
        vm.expectRevert(IPOLErrors.NotFactoryVault.selector);
        beraChef.setVaultWhitelistedStatus(receiver3, true, "");
        // Fail while blacklisting
        vm.startPrank(governance);
        vm.expectRevert(IPOLErrors.NotFactoryVault.selector);
        beraChef.setVaultWhitelistedStatus(receiver3, false, "");
    }

    /// @dev Should revert because invalidating the default reward allocation
    function test_FailIfRemovingAVaultFromWhitelistInvalidatesDefaultRewardAllocation() public {
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](2);
        weights[0] = IBeraChef.Weight(receiver, 5000);
        weights[1] = IBeraChef.Weight(receiver2, 5000);
        vm.startPrank(governance);
        beraChef.setDefaultRewardAllocation(IBeraChef.RewardAllocation(0, weights));
        vm.expectRevert(IPOLErrors.InvalidateDefaultRewardAllocation.selector);
        beraChef.setVaultWhitelistedStatus(receiver, false, "");
    }

    function test_EditDefaultRewardAllocationBeforeRemoveAVaultFromWhitelist() public {
        address stakeTokenVault3 = address(new MockHoney());

        vm.startPrank(governance);
        address receiver3 = factory.createRewardVault(address(stakeTokenVault3));

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](2);
        vm.startPrank(governance);
        beraChef.setVaultWhitelistedStatus(receiver3, true, ""); // Whitelist receiver3

        // Set default reward allocation with receiver and receiver2
        test_FailIfRemovingAVaultFromWhitelistInvalidatesDefaultRewardAllocation();

        weights[0] = IBeraChef.Weight(receiver2, 5000);
        weights[1] = IBeraChef.Weight(receiver3, 5000);
        beraChef.setDefaultRewardAllocation(IBeraChef.RewardAllocation(0, weights));

        beraChef.setVaultWhitelistedStatus(receiver, false, "");
        assertFalse(beraChef.isWhitelistedVault(receiver));
    }

    /// @dev Should update the whitelisted vaults
    function testFuzz_updateWhitelistedVaults(bool isWhitelisted) public {
        vm.prank(governance);
        beraChef.setVaultWhitelistedStatus(receiver, isWhitelisted, "");
        assertEq(beraChef.isWhitelistedVault(receiver), isWhitelisted);
    }

    /// @dev Should set the default reward allocation
    function test_SetDefaultRewardAllocation() public {
        assertFalse(beraChef.isReady());

        vm.prank(governance);
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] = IBeraChef.Weight(receiver2, 10_000);

        vm.expectEmit(true, true, true, true);
        emit IBeraChef.SetDefaultRewardAllocation(IBeraChef.RewardAllocation(1, weights));
        beraChef.setDefaultRewardAllocation(IBeraChef.RewardAllocation(1, weights));

        IBeraChef.RewardAllocation memory ra = beraChef.getDefaultRewardAllocation();
        assertEq(ra.startBlock, 1);
        assertEq(ra.weights.length, 1);
        assertEq(ra.weights[0].receiver, receiver2);
        assertEq(ra.weights[0].percentageNumerator, 10_000);
        assertTrue(beraChef.isReady());
    }

    /* Queueing a new reward allocation */

    /// @dev Should fail if the new reward allocation is not in the future
    function test_FailIfTheNewRewardAllocationIsNotInTheFuture() public {
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] = IBeraChef.Weight(receiver, 10_000);
        vm.prank(operator);
        vm.expectRevert(IPOLErrors.InvalidStartBlock.selector);
        beraChef.queueNewRewardAllocation(valData.pubkey, uint64(block.number), weights);
    }

    /// @dev Should fail if the new reward allocation has too many weights
    function test_FailIfTheNewRewardAllocationHasTooManyWeights() public {
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1000);
        for (uint256 i; i < 1000; ++i) {
            weights[i] = IBeraChef.Weight(receiver, 10);
        }
        vm.prank(operator);
        vm.expectRevert(IPOLErrors.TooManyWeights.selector);
        beraChef.queueNewRewardAllocation(valData.pubkey, uint64(block.number + 1), weights);
    }

    /// @dev Should fail if the new reward allocation weights too high
    function test_FailIfTheNewRewardAllocationHasInvalidWeights() public {
        vm.prank(governance);
        beraChef.setMaxWeightPerVault(uint96(0.2e4));

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](2);

        weights[0] = IBeraChef.Weight(receiver, 5000);
        weights[1] = IBeraChef.Weight(makeAddr("receiverOne"), 5000);

        vm.prank(operator);
        vm.expectRevert(IPOLErrors.InvalidWeight.selector);
        beraChef.queueNewRewardAllocation(valData.pubkey, uint64(block.number + 1), weights);
    }

    /// @dev Should fail if the new reward allocation weights too high TODO
    function test_FallbackToDefaultRAWhenLoweringMaxWeightPerVault() public {
        vm.prank(governance);
        beraChef.setVaultWhitelistedStatus(receiver2, true, "");

        IBeraChef.Weight[] memory defaultWeights = new IBeraChef.Weight[](2);
        defaultWeights[0] = IBeraChef.Weight(receiver, 5000);
        defaultWeights[1] = IBeraChef.Weight(receiver2, 5000);
        vm.prank(governance);
        beraChef.setDefaultRewardAllocation(IBeraChef.RewardAllocation(0, defaultWeights));

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] = IBeraChef.Weight(receiver, 10_000);

        vm.prank(operator);
        beraChef.queueNewRewardAllocation(valData.pubkey, uint64(block.number + 1), weights);

        vm.roll(block.number + 1);
        vm.prank(address(distributor));
        beraChef.activateReadyQueuedRewardAllocation(valData.pubkey);
        IBeraChef.RewardAllocation memory ra = beraChef.getActiveRewardAllocation(valData.pubkey);
        assertEq(1, ra.weights.length);

        vm.prank(governance);
        beraChef.setMaxWeightPerVault(uint96(6000)); // invalidates queued reward allocation

        ra = beraChef.getActiveRewardAllocation(valData.pubkey);
        IBeraChef.RewardAllocation memory dra = beraChef.getDefaultRewardAllocation();
        assertEq(dra.weights.length, ra.weights.length);
        assertEq(dra.weights[0].percentageNumerator, ra.weights[0].percentageNumerator);
        assertEq(dra.weights[1].percentageNumerator, ra.weights[1].percentageNumerator);
    }

    /// @dev Should fail if not a whitelisted vault
    function test_FailIfNotWhitelistedVault() public {
        vm.prank(governance);
        beraChef.setVaultWhitelistedStatus(receiver, false, "");
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] = IBeraChef.Weight(receiver, 10_000);
        vm.prank(operator);
        vm.expectRevert(IPOLErrors.NotWhitelistedVault.selector);
        beraChef.queueNewRewardAllocation(valData.pubkey, uint64(block.number + 1), weights);
    }

    /// @dev Should fail if reward allocation weights don't add up to 100%
    function test_FailIfInvalidRewardAllocationWeights() public {
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] = IBeraChef.Weight(receiver, 5000);
        vm.prank(operator);
        vm.expectRevert(IPOLErrors.InvalidRewardAllocationWeights.selector);
        beraChef.queueNewRewardAllocation(valData.pubkey, uint64(block.number + 1), weights);
    }

    /// @dev Should fail if reward allocation contains a weight percentage equal to 0
    function test_FailIfZeroRewardAllocationWeight() public {
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](3);
        weights[0] = IBeraChef.Weight(receiver, 5000);
        weights[1] = IBeraChef.Weight(makeAddr("receiverOne"), 0);
        weights[2] = IBeraChef.Weight(makeAddr("receiverTwo"), 5000);

        vm.prank(operator);
        vm.expectRevert(IPOLErrors.InvalidWeight.selector);
        beraChef.queueNewRewardAllocation(valData.pubkey, uint64(block.number + 1), weights);
    }

    /// @dev Should queue a new reward allocation
    function test_QueueANewRewardAllocation() public {
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] = IBeraChef.Weight(receiver, 10_000);
        uint64 startBlock = uint64(block.number + 2);
        vm.prank(operator);
        beraChef.queueNewRewardAllocation(valData.pubkey, startBlock, weights);

        IBeraChef.RewardAllocation memory ra = beraChef.getQueuedRewardAllocation(valData.pubkey);
        assertEq(ra.startBlock, startBlock);
        assertEq(ra.weights.length, 1);
        assertEq(ra.weights[0].receiver, receiver);
        assertEq(ra.weights[0].percentageNumerator, 10_000);
    }

    /// @dev Should revert if there exists a queued reward allocation
    function test_FailQueuedRewardAllocationExists() public {
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] = IBeraChef.Weight(receiver, 10_000);
        vm.startPrank(operator);
        // queue a new reward allocation 10000 blocks in the future
        beraChef.queueNewRewardAllocation(valData.pubkey, uint64(block.number + 10_000), weights);
        // override another reward allocation
        vm.expectRevert(IPOLErrors.RewardAllocationAlreadyQueued.selector);
        beraChef.queueNewRewardAllocation(valData.pubkey, uint64(block.number + 2), weights);
    }

    /// @dev Should queue a new reward allocation with multiple weights
    function test_QueueANewRewardAllocationWithMultipleWeights() public {
        vm.prank(governance);
        beraChef.setVaultWhitelistedStatus(receiver2, true, "");

        // queue a new reward allocation with multiple weights
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](2);
        weights[0] = IBeraChef.Weight(receiver, 3000);
        weights[1] = IBeraChef.Weight(receiver2, 7000);
        uint64 startBlock = uint64(block.number + 2);
        vm.prank(operator);
        beraChef.queueNewRewardAllocation(valData.pubkey, startBlock, weights);

        // ensure that the queued reward allocation is set correctly
        IBeraChef.RewardAllocation memory ra = beraChef.getQueuedRewardAllocation(valData.pubkey);
        assertEq(ra.startBlock, startBlock);
        assertEq(ra.weights.length, 2);
        assertEq(ra.weights[0].receiver, receiver);
        assertEq(ra.weights[0].percentageNumerator, 3000);
        assertEq(ra.weights[1].receiver, receiver2);
        assertEq(ra.weights[1].percentageNumerator, 7000);
    }

    /// @dev Should queue a new reward allocation
    // TODO: Fuzz test
    function testFuzz_QueueANewRewardAllocation(uint32 seed) public { }

    // TODO: Invariant test
    // function invariant_test() public { }

    /* Activating a reward allocation */

    /// @dev Should fail if the caller is not the distribution contract
    function test_FailIfCallerNotDistributor() public {
        vm.expectRevert(IPOLErrors.NotDistributor.selector);
        beraChef.activateReadyQueuedRewardAllocation(valData.pubkey);
    }

    /// @dev Should fail if the reward allocation is not queued
    function test_ReturnsIfTheRewardAllocationIsNotQueued() public {
        vm.recordLogs();
        vm.prank(address(distributor));
        beraChef.activateReadyQueuedRewardAllocation(valData.pubkey);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // ensure that no event was emitted
        assertEq(entries.length, 0);
    }

    /// @dev Should fail if start block is greater than current block
    function test_ReturnsfStartBlockGreaterThanCurrentBlock() public {
        test_QueueANewRewardAllocation();
        assertFalse(beraChef.isQueuedRewardAllocationReady(valData.pubkey, block.number));
        vm.recordLogs();
        vm.prank(address(distributor));
        beraChef.activateReadyQueuedRewardAllocation(valData.pubkey);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // ensure that no event was emitted
        assertEq(entries.length, 0);
    }

    /// @dev Should activate a reward allocation
    function test_ActivateARewardAllocation() public {
        // queue and activate a new creward allocation
        test_QueueANewRewardAllocation();
        assertFalse(beraChef.isQueuedRewardAllocationReady(valData.pubkey, block.number));
        IBeraChef.RewardAllocation memory ra = beraChef.getQueuedRewardAllocation(valData.pubkey);
        uint64 startBlock = uint64(block.number + 2);

        vm.roll(startBlock);
        assertTrue(beraChef.isQueuedRewardAllocationReady(valData.pubkey, block.number));
        vm.prank(address(distributor));
        vm.expectEmit(true, true, true, true);
        emit IBeraChef.ActivateRewardAllocation(valData.pubkey, startBlock, ra.weights);
        beraChef.activateReadyQueuedRewardAllocation(valData.pubkey);
        assertFalse(beraChef.isQueuedRewardAllocationReady(valData.pubkey, block.number));

        // ensure that the active reward allocation is set correctly
        ra = beraChef.getActiveRewardAllocation(valData.pubkey);
        assertEq(ra.startBlock, startBlock);
        assertEq(ra.weights.length, 1);
        assertEq(ra.weights[0].receiver, receiver);
        assertEq(ra.weights[0].percentageNumerator, 10_000);
    }

    /// @dev Should delete the queued reward allocation after activation
    function test_DeleteQueuedRewardAllocationAfterActivation() public {
        // queue a new reward allocation
        test_QueueANewRewardAllocationWithMultipleWeights();

        // activate the queued reward allocation
        uint64 startBlock = uint64(block.number + 2);
        vm.roll(startBlock);
        vm.prank(address(distributor));
        beraChef.activateReadyQueuedRewardAllocation(valData.pubkey);

        // ensure that the queued reward allocation is deleted
        IBeraChef.RewardAllocation memory ra = beraChef.getQueuedRewardAllocation(valData.pubkey);
        assertEq(ra.startBlock, 0);
        assertEq(ra.weights.length, 0);
    }

    /* Getters */

    /// @dev Should return the active reward allocation
    function test_GetActiveRewardAllocation() public {
        // ensure that the active reward allocation is empty
        IBeraChef.RewardAllocation memory ra = beraChef.getActiveRewardAllocation(valData.pubkey);
        assertEq(ra.startBlock, 0);
        assertEq(ra.weights.length, 0);

        // queue and activate a new reward allocation
        test_ActivateARewardAllocation();
    }

    /// @dev Should return the default reward allocation
    function test_GetActiveRewardAllocationReturnsDefaultRewardAllocation() public {
        address stakeTokenVault3 = address(new MockHoney());
        test_GetActiveRewardAllocation();

        // remove receiver from whitelist
        vm.startPrank(governance);
        beraChef.setVaultWhitelistedStatus(receiver, false, "");
        address receiver3 = factory.createRewardVault(address(stakeTokenVault3));

        // set default reward allocation
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] = IBeraChef.Weight(receiver3, 10_000);
        beraChef.setVaultWhitelistedStatus(receiver3, true, "");
        beraChef.setDefaultRewardAllocation(IBeraChef.RewardAllocation(1, weights));

        // ensure that the default reward allocation is set correctly
        IBeraChef.RewardAllocation memory ra = beraChef.getActiveRewardAllocation(valData.pubkey);
        assertEq(ra.startBlock, 1);
        assertEq(ra.weights.length, 1);
        assertEq(ra.weights[0].receiver, receiver3);
        assertEq(ra.weights[0].percentageNumerator, 10_000);
    }

    function test_GetSetActiveRewardAllocation() public {
        //set default reward allocation
        test_SetDefaultRewardAllocation();
        // ensure that the set active reward allocation is empty if none is set
        IBeraChef.RewardAllocation memory ra = beraChef.getSetActiveRewardAllocation(valData.pubkey);
        assertEq(ra.startBlock, 0);
        assertEq(ra.weights.length, 0);

        // queue and activate a new reward allocation
        test_ActivateARewardAllocation();

        vm.prank(governance);
        // remove the receiver from the whitelisted vaults
        beraChef.setVaultWhitelistedStatus(receiver, false, "");

        // getActiveRewardAllocation should return the default reward allocation as `receiver` is not whitelisted
        ra = beraChef.getActiveRewardAllocation(valData.pubkey);
        assertEq(ra.weights.length, 1);
        assertEq(ra.weights[0].receiver, receiver2);
        assertEq(ra.weights[0].percentageNumerator, 10_000);

        // getSetActiveRewardAllocation should return the `actual` active reward allocation set by validator
        ra = beraChef.getSetActiveRewardAllocation(valData.pubkey);
        assertEq(ra.weights.length, 1);
        assertEq(ra.weights[0].receiver, receiver);
        assertEq(ra.weights[0].percentageNumerator, 10_000);
    }

    /// @dev Should return the default reward allocation if the active one become invalid after max weights change
    function test_GetActiveRewardAllocationReturnsDefaultRewardAllocationAfterSetMaxWeights() public {
        test_SetDefaultRewardAllocation();
        IBeraChef.RewardAllocation memory defaultRa = beraChef.getDefaultRewardAllocation();

        address stakeTokenVault3 = address(new MockHoney());
        address receiver3 = factory.createRewardVault(address(stakeTokenVault3));
        vm.prank(governance);
        beraChef.setVaultWhitelistedStatus(receiver3, true, "");

        // Activate a reward allocation with custom weights
        IBeraChef.Weight[] memory customWeights = new IBeraChef.Weight[](3);
        customWeights[0] = IBeraChef.Weight(receiver, 2500);
        customWeights[1] = IBeraChef.Weight(receiver2, 2500);
        customWeights[2] = IBeraChef.Weight(receiver3, 5000);
        helper_ActivateRewardAllocation(2, customWeights);

        // Check the active reward allocation
        IBeraChef.RewardAllocation memory activeRa = beraChef.getActiveRewardAllocation(valData.pubkey);
        assertEq(activeRa.startBlock, 2);
        assertEq(activeRa.weights.length, 3);
        assertEq(activeRa.weights[2].receiver, receiver3);
        assertEq(activeRa.weights[2].percentageNumerator, 5000);

        // Update the max weights to 1
        vm.prank(governance);
        beraChef.setMaxNumWeightsPerRewardAllocation(1);

        // Check the active reward allocation is the default one
        activeRa = beraChef.getActiveRewardAllocation(valData.pubkey);
        assertEq(activeRa.weights.length, defaultRa.weights.length);
        assertEq(activeRa.weights[0].receiver, defaultRa.weights[0].receiver);
        assertEq(activeRa.weights[0].percentageNumerator, defaultRa.weights[0].percentageNumerator);
    }

    function helper_ActivateRewardAllocation(uint64 startBlock, IBeraChef.Weight[] memory weights) public {
        vm.prank(operator);
        beraChef.queueNewRewardAllocation(valData.pubkey, startBlock, weights);

        vm.roll(startBlock);
        assertTrue(beraChef.isQueuedRewardAllocationReady(valData.pubkey, block.number));
        vm.prank(address(distributor));
        vm.expectEmit(true, true, true, true);
        emit IBeraChef.ActivateRewardAllocation(valData.pubkey, startBlock, weights);
        beraChef.activateReadyQueuedRewardAllocation(valData.pubkey);
    }

    function test_QueueValCommission() public {
        testFuzz_QueueValCommission(2e3);
    }

    function testFuzz_QueueValCommission(uint256 commission) public {
        commission = bound(commission, 1, 1e4); // capped at 100%
        vm.prank(operator);
        vm.expectEmit();
        emit IBeraChef.QueuedValCommission(valData.pubkey, uint96(commission));
        beraChef.queueValCommission(valData.pubkey, uint96(commission));
        IBeraChef.QueuedCommissionRateChange memory queuedCommission =
            beraChef.getValQueuedCommissionOnIncentiveTokens(valData.pubkey);
        assertEq(queuedCommission.blockNumberLast, block.number);
        assertEq(queuedCommission.commissionRate, uint96(commission));
    }

    function test_QueueValCommission_FailIfAlreadyQueued() public {
        testFuzz_QueueValCommission(2e3);
        vm.prank(operator);
        vm.expectRevert(IPOLErrors.CommissionChangeAlreadyQueued.selector);
        beraChef.queueValCommission(valData.pubkey, uint96(1e4));
    }

    function test_QueueValCommission_FailIfCommissionMoreThanHundredPercent() public {
        vm.prank(operator);
        vm.expectRevert(IPOLErrors.InvalidCommissionValue.selector);
        beraChef.queueValCommission(valData.pubkey, uint96(1e4 + 1));
    }

    function test_QueueValCommission_FailIfCallerNotOperator() public {
        vm.expectRevert(IPOLErrors.NotOperator.selector);
        beraChef.queueValCommission(valData.pubkey, uint96(2e3));
    }

    function test_ActivateQueuedValCommission() public {
        // set commission for the first time
        testFuzz_QueueValCommission(1);
        // old commission will be equal to default 5% because it was never set before.
        assertEq(beraChef.getValCommissionOnIncentiveTokens(valData.pubkey), 0.05e4);

        vm.roll(vm.getBlockNumber() + (2 * 8191));
        vm.expectEmit();
        emit IBeraChef.ValCommissionSet(valData.pubkey, 0.05e4, 1);
        beraChef.activateQueuedValCommission(valData.pubkey);
        // new commission will be equal to the queued commission.
        assertEq(beraChef.getValCommissionOnIncentiveTokens(valData.pubkey), 1);
        // queued commission should be deleted
        IBeraChef.QueuedCommissionRateChange memory queuedCommission =
            beraChef.getValQueuedCommissionOnIncentiveTokens(valData.pubkey);
        assertEq(queuedCommission.blockNumberLast, 0);
        assertEq(queuedCommission.commissionRate, 0);

        testFuzz_QueueValCommission(2e3);
        vm.roll(vm.getBlockNumber() + (2 * 8191));
        vm.expectEmit();
        // old commission will be equal to default 5%.
        emit IBeraChef.ValCommissionSet(valData.pubkey, 1, 0.2e4);
        beraChef.activateQueuedValCommission(valData.pubkey);
        assertEq(beraChef.getValCommissionOnIncentiveTokens(valData.pubkey), 2e3);
        // queued commission should be deleted
        queuedCommission = beraChef.getValQueuedCommissionOnIncentiveTokens(valData.pubkey);
        assertEq(queuedCommission.blockNumberLast, 0);
        assertEq(queuedCommission.commissionRate, 0);
    }

    function test_ActivateQueuedValCommission_FailIfCommissionChangeNotQueued() public {
        vm.expectRevert(IPOLErrors.CommissionNotQueuedOrDelayNotPassed.selector);
        beraChef.activateQueuedValCommission(valData.pubkey);
    }

    function test_ActivateQueuedValCommission_FailIfCommissionChangeDelayNotPassed() public {
        testFuzz_QueueValCommission(2e3);
        vm.roll(block.number + 2 * 8191 - 1);
        vm.expectRevert(IPOLErrors.CommissionNotQueuedOrDelayNotPassed.selector);
        beraChef.activateQueuedValCommission(valData.pubkey);
    }

    function test_SetCommissionChangeDelay() public {
        testFuzz_SetCommissionChangeDelay(8191);
    }

    function testFuzz_SetCommissionChangeDelay(uint256 delay) public {
        delay = bound(delay, 1, 8191 * 2);
        vm.prank(governance);
        vm.expectEmit();
        emit IBeraChef.CommissionChangeDelaySet(uint64(delay));
        beraChef.setCommissionChangeDelay(uint64(delay));
        assertEq(beraChef.commissionChangeDelay(), uint64(delay));
    }

    function test_SetCommissionChangeDelay_FailIfCommissionChangeDelayIsMoreThanMax() public {
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.InvalidCommissionChangeDelay.selector);
        beraChef.setCommissionChangeDelay(8191 * 2 + 1);
    }

    function test_SetCommissionChangeDelay_FailIfCommissionChangeDelayIsZero() public {
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.InvalidCommissionChangeDelay.selector);
        beraChef.setCommissionChangeDelay(0);
    }

    function test_SetCommissionChangeDelay_FailIfNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        beraChef.setCommissionChangeDelay(8191);
    }
}
