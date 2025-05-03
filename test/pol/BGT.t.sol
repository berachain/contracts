// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ERC20VotesUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { IBGT, IERC20 } from "src/pol/interfaces/IBGT.sol";
import { IPOLErrors, IStakingRewardsErrors } from "src/pol/interfaces/IPOLErrors.sol";
import { BlockRewardController } from "src/pol/rewards/BlockRewardController.sol";
import { POLTest } from "./POL.t.sol";

contract BGTTest is POLTest {
    uint256 internal constant MAX_SUPPLY = type(uint208).max;
    uint256 internal constant ONE_HUNDRED_PERCENT = 1e4;
    uint256 internal constant TEN_PERCENT = 1e3;
    uint32 private constant BOOST_MAX_BLOCK_DELAY = 8191;

    address internal receiverAddr = makeAddr("receiverAddr");
    bytes valPubkey2 = "validator pubkey 2";

    /* Admin functions */

    /// @dev Ensure that the contract is owned by the governance.
    function test_OwnerIsGovernance() public view {
        assertEq(bgt.owner(), governance);
    }

    /// @dev Should fail if not the owner
    function test_FailIfNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        bgt.transferOwnership(address(1));

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        bgt.whitelistSender(address(0), true);

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        bgt.setMinter(address(1));
    }

    /// @dev Ensure that the minter is set to the block reward controller.
    function test_MinterIsBlockRewardController() public view {
        assertEq(bgt.minter(), address(blockRewardController));
    }

    /// @dev Should revert if the minter is set to zero.
    function test_FailIfMinterIsZero() public {
        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        vm.prank(governance);
        bgt.setMinter(address(0));
    }

    /// @dev Ensure that the minter is set to the given address.
    function test_SetMinter() public {
        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit IBGT.MinterChanged(address(blockRewardController), address(this));
        bgt.setMinter(address(this));
        assertEq(bgt.minter(), address(this));
    }

    /// @dev Ensure that the minter is set to the given address.
    function testFuzz_SetMinter(address minter) public {
        vm.assume(minter != address(0));
        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit IBGT.MinterChanged(address(blockRewardController), minter);
        bgt.setMinter(minter);
        assertEq(bgt.minter(), minter);
    }

    /// @dev Ensure that the governance can approve a sender to send BGT.
    function test_WhitelistSender() public {
        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit IBGT.SenderWhitelisted(address(this), true);
        bgt.whitelistSender(address(this), true);
        assertEq(bgt.isWhitelistedSender(address(this)), true);
    }

    /// @dev Test sender whitelisting.
    function testFuzz_WhitelistSender(address sender, bool approved) public {
        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit IBGT.SenderWhitelisted(sender, approved);
        bgt.whitelistSender(sender, approved);
        assertEq(bgt.isWhitelistedSender(sender), approved);
    }

    /// @dev Should fail if not the block reward controller.
    function test_FailMintIfNotMinter() public {
        vm.expectRevert(IPOLErrors.NotBlockRewardController.selector);
        bgt.mint(address(distributor), 1);
    }

    /// @dev Should fail if total supply is over max uint.
    function test_FailMintOverMaxUint() public {
        vm.deal(address(bgt), MAX_SUPPLY);
        vm.startPrank(address(blockRewardController));
        bgt.mint(address(this), MAX_SUPPLY);

        vm.expectRevert(
            abi.encodeWithSelector(ERC20VotesUpgradeable.ERC20ExceededSafeSupply.selector, MAX_SUPPLY + 1, MAX_SUPPLY)
        );
        bgt.mint(address(this), 1);
    }

    function test_Mint_FailsIfInvariantCheckFails() public {
        uint256 redemptionContractBal = address(bgt).balance;
        vm.prank(address(blockRewardController));
        vm.expectRevert(IPOLErrors.InvariantCheckFailed.selector);
        bgt.mint(address(distributor), redemptionContractBal + 1);
    }

    /// @dev Ensure that the minter can mint BGT.
    function test_Mint() public {
        testFuzz_Mint(address(distributor), 1);
    }

    /// @dev Ensure that the minter can mint BGT.
    function testFuzz_Mint(address distributor, uint256 amount) public {
        vm.assume(distributor != address(0));
        amount = _bound(amount, 0, MAX_SUPPLY);
        vm.deal(address(bgt), amount);
        vm.prank(address(blockRewardController));

        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(0), distributor, amount);
        bgt.mint(distributor, amount);

        assertEq(bgt.balanceOf(distributor), amount);
        assertEq(bgt.totalSupply(), amount);
    }

    /* Boost functions */

    function test_QueueBoost() public {
        testFuzz_QueueBoost(address(distributor), 1);
    }

    function testFuzz_QueueBoost(address user, uint256 amount) public {
        vm.assume(user != address(0));
        amount = _bound(amount, 0, type(uint128).max);
        testFuzz_Mint(user, amount);

        vm.prank(user);

        vm.expectEmit(true, true, true, true);
        emit IBGT.QueueBoost(user, valData.pubkey, uint128(amount));
        bgt.queueBoost(valData.pubkey, uint128(amount));

        // check the states after queuing the boost.
        _checkAfterQueuedBoost(user, amount);
    }

    function test_CancelBoost_FailsIfCancelledMoreThanQueuedBoost() public {
        testFuzz_CancelBoost_FailsIfCancelledMoreThanQueuedBoost(1, 2);
    }

    function testFuzz_CancelBoost_FailsIfCancelledMoreThanQueuedBoost(
        uint256 queueAmount,
        uint256 cancelAmount
    )
        public
    {
        queueAmount = _bound(queueAmount, 0, type(uint128).max - 1);
        cancelAmount = _bound(cancelAmount, queueAmount + 1, type(uint128).max);
        testFuzz_QueueBoost(address(distributor), queueAmount);
        vm.prank(address(distributor));
        vm.expectRevert(stdError.arithmeticError);
        bgt.cancelBoost(valData.pubkey, uint128(cancelAmount));
    }

    function test_CancelBoost() public {
        testFuzz_CancelBoost(address(distributor), 1, 1);
    }

    function testFuzz_CancelBoost(address user, uint256 queuedAmount, uint256 cancelAmount) public {
        vm.assume(user != address(0));
        queuedAmount = _bound(queuedAmount, 0, type(uint128).max);
        cancelAmount = _bound(cancelAmount, 0, queuedAmount);
        testFuzz_QueueBoost(user, queuedAmount);

        (uint32 blockNumberLast,) = bgt.boostedQueue(user, valData.pubkey);

        vm.prank(user);

        vm.expectEmit(true, true, true, true);
        emit IBGT.CancelBoost(user, valData.pubkey, uint128(cancelAmount));
        bgt.cancelBoost(valData.pubkey, uint128(cancelAmount));

        // check the states after cancelling the boost.
        _checkAfterCancelBoost(user, queuedAmount, cancelAmount, blockNumberLast);
    }

    function test_ActivateBoost_ReturnsFalseIfNotQueued() public {
        // advance blocks
        vm.roll(10_000);
        // This should return false as it try to activate a 0 boost amount
        bool result = bgt.activateBoost(address(this), valData.pubkey);
        assertFalse(result);
    }

    function test_ActivateBoost_ReturnsFalseIfNotEnoughTimePassed() public {
        testFuzz_ActivateBoost_ReturnsFalseIfNotEnoughTimePassed(BOOST_MAX_BLOCK_DELAY);
    }

    function testFuzz_ActivateBoost_ReturnsFalseIfNotEnoughTimePassed(uint256 blockDelta) public {
        // set the delay to half of the history buffer length
        testFuzz_SetActivateBoostDelay(BOOST_MAX_BLOCK_DELAY / 2);
        blockDelta = _bound(blockDelta, 0, BOOST_MAX_BLOCK_DELAY / 2);
        test_QueueBoost();
        vm.roll(block.number + blockDelta);
        vm.prank(address(distributor));
        bool result = bgt.activateBoost(address(distributor), valData.pubkey);
        assertFalse(result);
    }

    function test_ActivateBoost() public {
        testFuzz_ActivateBoost(address(this), address(distributor), 1);
    }

    function testFuzz_ActivateBoost(address caller, address user, uint256 amount) public {
        vm.assume(caller != address(0));
        vm.assume(user != address(0));
        amount = _bound(amount, 1, type(uint128).max);
        testFuzz_QueueBoost(user, amount);
        // set the activate boostdelay to 100 blocks
        testFuzz_SetActivateBoostDelay(100);
        (uint32 blockNumberLast,) = bgt.boostedQueue(user, valData.pubkey);
        vm.roll(blockNumberLast + 100 + 1);

        vm.prank(caller);
        vm.expectEmit(true, true, true, true);
        emit IBGT.ActivateBoost(caller, user, valData.pubkey, uint128(amount));
        bgt.activateBoost(user, valData.pubkey);

        // check the states after activating the boost.
        _checkAfterActivateBoost(user, amount);
        assertEq(bgt.boostees(valData.pubkey), amount);
        assertEq(bgt.totalBoosts(), amount);
    }

    function test_SetActivateBoostDelay() public {
        testFuzz_SetActivateBoostDelay(1);
    }

    function testFuzz_SetActivateBoostDelay(uint256 delay) public {
        delay = _bound(delay, 1, BOOST_MAX_BLOCK_DELAY);
        vm.prank(governance);
        bgt.setActivateBoostDelay(uint32(delay));
        assertEq(bgt.activateBoostDelay(), uint32(delay));
    }

    function test_SetActivateBoostDelay_FailsIfNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        bgt.setActivateBoostDelay(uint32(1));
    }

    function test_SetActivateBoostDelay_FailsIfZero() public {
        vm.prank(governance);
        vm.expectRevert(abi.encodeWithSelector(IPOLErrors.InvalidActivateBoostDelay.selector));
        bgt.setActivateBoostDelay(0);
    }

    function test_SetActivateBoostDelay_FailsIfGreaterThanHistoryBufferLength() public {
        vm.prank(governance);
        vm.expectRevert(abi.encodeWithSelector(IPOLErrors.InvalidActivateBoostDelay.selector));
        bgt.setActivateBoostDelay(uint32(BOOST_MAX_BLOCK_DELAY + 1));
    }

    function test_SetDropBoostDelay_FailsIfZero() public {
        vm.prank(governance);
        vm.expectRevert(abi.encodeWithSelector(IPOLErrors.InvalidDropBoostDelay.selector));
        bgt.setDropBoostDelay(0);
    }

    function test_SetDropBoostDelay_FailsIfGreaterThanHistoryBufferLength() public {
        vm.prank(governance);
        vm.expectRevert(abi.encodeWithSelector(IPOLErrors.InvalidDropBoostDelay.selector));
        bgt.setDropBoostDelay(uint32(BOOST_MAX_BLOCK_DELAY + 1));
    }

    function test_SetDropBoostDelay_FailsIfNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        bgt.setDropBoostDelay(uint32(1));
    }

    function test_SetDropBoostDelay() public {
        testFuzz_SetDropBoostDelay(1);
    }

    function testFuzz_SetDropBoostDelay(uint256 delay) public {
        delay = _bound(delay, 1, BOOST_MAX_BLOCK_DELAY);
        vm.prank(governance);
        bgt.setDropBoostDelay(uint32(delay));
        assertEq(bgt.dropBoostDelay(), uint32(delay));
    }

    function test_QueueDropBoost_FailsIfDroppedMoreThanBoost() public {
        testFuzz_QueueDropBoost_FailsIfDroppedMoreThanBoost(1, 2);
    }

    function testFuzz_QueueDropBoost_FailsIfDroppedMoreThanBoost(uint256 boostAmount, uint256 dropAmount) public {
        boostAmount = _bound(boostAmount, 1, type(uint128).max - 1);
        dropAmount = _bound(dropAmount, boostAmount + 1, type(uint128).max);
        testFuzz_ActivateBoost(address(this), address(distributor), boostAmount);
        vm.prank(address(distributor));
        vm.expectRevert(IPOLErrors.NotEnoughBoostedBalance.selector);
        bgt.queueDropBoost(valData.pubkey, uint128(dropAmount));
    }

    function test_QueueDropBoost() public {
        testFuzz_QueueDropBoost(address(distributor), 100, 80);
    }

    function testFuzz_QueueDropBoost(address user, uint256 boostAmount, uint256 dropAmount) public {
        vm.assume(user != address(0));
        boostAmount = _bound(boostAmount, 0, type(uint128).max);
        dropAmount = _bound(dropAmount, 0, boostAmount);
        testFuzz_ActivateBoost(address(this), user, boostAmount);

        uint256 dropAmount1 = dropAmount / 2;
        vm.startPrank(user);
        vm.expectEmit(true, true, true, true);
        emit IBGT.QueueDropBoost(user, valData.pubkey, uint128(dropAmount1));
        bgt.queueDropBoost(valData.pubkey, uint128(dropAmount1));
        (uint32 blockNumberLast, uint224 balance) = bgt.dropBoostQueue(user, valData.pubkey);
        assertEq(blockNumberLast, uint32(block.number));
        assertEq(balance, uint224(dropAmount1));
        uint256 blockNumber = block.number;

        vm.roll(blockNumber + 100);

        // again queue drop boost
        uint128 dropAmount2 = uint128(dropAmount - dropAmount1);
        vm.expectEmit(true, true, true, true);
        emit IBGT.QueueDropBoost(user, valData.pubkey, dropAmount2);
        bgt.queueDropBoost(valData.pubkey, dropAmount2);
        vm.stopPrank();
        (blockNumberLast, balance) = bgt.dropBoostQueue(user, valData.pubkey);
        assertEq(blockNumberLast, uint32(blockNumber + 100));
        assertEq(balance, uint224(dropAmount));
    }

    function test_CancelDropBoost_FailsIfCancelledMoreThanQueuedDropBoost() public {
        testFuzz_CancelDropBoost_FailsIfCancelledMoreThanQueuedDropBoost(1, 2);
    }

    function testFuzz_CancelDropBoost_FailsIfCancelledMoreThanQueuedDropBoost(
        uint256 queueAmount,
        uint256 cancelAmount
    )
        public
    {
        queueAmount = _bound(queueAmount, 1, type(uint128).max - 1);
        cancelAmount = _bound(cancelAmount, queueAmount + 1, type(uint128).max);
        testFuzz_QueueDropBoost(address(distributor), queueAmount, queueAmount);
        vm.prank(address(distributor));
        vm.expectRevert(stdError.arithmeticError);
        bgt.cancelDropBoost(valData.pubkey, uint128(cancelAmount));
    }

    function test_CancelDropBoost() public {
        testFuzz_CancelDropBoost(address(distributor), 100, 50);
    }

    function testFuzz_CancelDropBoost(address user, uint256 queueAmount, uint256 cancelAmount) public {
        vm.assume(user != address(0));
        queueAmount = _bound(queueAmount, 1, type(uint128).max);
        cancelAmount = _bound(cancelAmount, 1, queueAmount);
        testFuzz_QueueDropBoost(user, queueAmount, queueAmount);

        (uint32 blockNumberLast,) = bgt.dropBoostQueue(user, valData.pubkey);
        vm.roll(blockNumberLast + 1000); // roll to future
        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit IBGT.CancelDropBoost(user, valData.pubkey, uint128(cancelAmount));
        bgt.cancelDropBoost(valData.pubkey, uint128(cancelAmount));

        (uint32 blockNumberLastLatest, uint224 balance) = bgt.dropBoostQueue(user, valData.pubkey);
        // block number last should not change after cancelling the drop boost
        assertEq(blockNumberLastLatest, uint32(blockNumberLast));
        // queue drop boost balance should be updated
        assertEq(balance, uint224(queueAmount - cancelAmount));
    }

    function test_DropBoost_ReturnsFalseIfNotEnoughTimePassed() public {
        testFuzz_DropBoost_ReturnsFalseIfNotEnoughTimePassed(BOOST_MAX_BLOCK_DELAY);
    }

    function testFuzz_DropBoost_ReturnsFalseIfNotEnoughTimePassed(uint256 blockDelta) public {
        blockDelta = _bound(blockDelta, 0, BOOST_MAX_BLOCK_DELAY);
        testFuzz_QueueDropBoost(address(this), 100, 50);
        vm.roll(block.number + blockDelta);
        bool result = bgt.dropBoost(address(this), valData.pubkey);
        assertFalse(result);
    }

    function test_DropBoost_FailsIfQueueAmountIsZero() public {
        vm.roll(block.number + 1_000_000); // roll to a future block after deployment

        // Return false if nothing is queued to drop
        bool result = bgt.dropBoost(address(this), valData.pubkey);
        assertFalse(result);

        // This should return false if queue drop boost amount is zero.
        testFuzz_QueueDropBoost(address(this), 100, 0);
        vm.roll(block.number + BOOST_MAX_BLOCK_DELAY + 1);
        result = bgt.dropBoost(address(this), valData.pubkey);
        assertFalse(result);
    }

    function test_DropBoost() public {
        testFuzz_DropBoost(address(this), 100, 50);
    }

    function testFuzz_DropBoost(address user, uint256 boostAmount, uint256 dropAmount) public {
        vm.assume(user != address(0));
        boostAmount = _bound(boostAmount, 1, type(uint128).max);
        dropAmount = _bound(dropAmount, 1, boostAmount);
        testFuzz_QueueDropBoost(user, boostAmount, dropAmount);
        // set the drop boost delay to 1/5 of the history buffer length
        testFuzz_SetDropBoostDelay(BOOST_MAX_BLOCK_DELAY / 5);

        (uint32 blockNumberLast,) = bgt.dropBoostQueue(user, valData.pubkey);
        vm.roll(blockNumberLast + BOOST_MAX_BLOCK_DELAY / 5 + 1);

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit IBGT.DropBoost(user, user, valData.pubkey, uint128(dropAmount));
        bgt.dropBoost(user, valData.pubkey);

        // check the states after dropping the boost.
        _checkAfterDropBoost(user, boostAmount, dropAmount);
    }

    /* Multicallable functions */

    function test_MultiCall_SetPramsInBatch_FailsIfNotOwner() public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(IBGT.setStaker, (address(this)));
        data[1] = abi.encodeCall(IBGT.setMinter, (address(this)));
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        bgt.multicall(data);
    }

    function test_MultiCall_SetPramsInBatch() public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(IBGT.setStaker, (address(this)));
        data[1] = abi.encodeCall(IBGT.setMinter, (address(this)));
        vm.prank(governance);
        bgt.multicall(data);
        assertEq(address(bgt.staker()), address(this));
        assertEq(address(bgt.minter()), address(this));
    }

    function test_MultiCall_QueueBoostInBatch_FailsIfNotEnoughUnboostedBalance() public {
        // multicall queue boosts
        bytes[] memory data = new bytes[](2);
        //  `address(this)` tries to queue 2 BGT boosts, but it has 0 BGT balance.
        data[0] = abi.encodeCall(IBGT.queueBoost, (valData.pubkey, 1));
        data[1] = abi.encodeCall(IBGT.queueBoost, (valData.pubkey, 1));
        vm.expectRevert(IPOLErrors.NotEnoughBalance.selector);
        bgt.multicall(data);
    }

    function test_MultiCall_QueueBoostInBatch() public {
        testFuzz_MultiCall_QueueBoostInBatch(address(distributor), 1, 1);
    }

    function testFuzz_MultiCall_QueueBoostInBatch(address user, uint256 amount1, uint256 amount2) public {
        vm.assume(user != address(0));
        amount1 = _bound(amount1, 0, type(uint128).max);
        amount2 = _bound(amount2, 0, type(uint128).max - amount1);
        // multicall queue boosts
        deal(address(bgt), user, amount1 + amount2);
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(IBGT.queueBoost, (valData.pubkey, uint128(amount1)));
        data[1] = abi.encodeCall(IBGT.queueBoost, (valPubkey2, uint128(amount2)));
        vm.prank(user);
        bgt.multicall(data);

        // check the states after queuing the boosts.
        assertEq(bgt.balanceOf(user), amount1 + amount2);
        assertEq(bgt.unboostedBalanceOf(user), 0);

        (uint32 blockNumberLast, uint224 balance) = bgt.boostedQueue(user, valData.pubkey);
        (uint32 blockNumberLast2, uint224 balance2) = bgt.boostedQueue(user, valPubkey2);
        assertEq(blockNumberLast, uint32(block.number));
        assertEq(balance, amount1);
        assertEq(blockNumberLast2, uint32(block.number));
        assertEq(balance2, amount2);
    }

    function test_MultiCall_CancelBoostInBatch() public {
        testFuzz_MultiCall_CancelBoostInBatch(address(distributor), 1, 1);
    }

    function testFuzz_MultiCall_CancelBoostInBatch(address user, uint256 amount1, uint256 amount2) public {
        vm.assume(user != address(0));
        amount1 = _bound(amount1, 0, type(uint128).max);
        amount2 = _bound(amount2, 0, type(uint128).max - amount1);
        testFuzz_MultiCall_QueueBoostInBatch(user, amount1, amount2);
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(IBGT.cancelBoost, (valData.pubkey, uint128(amount1)));
        data[1] = abi.encodeCall(IBGT.cancelBoost, (valPubkey2, uint128(amount2)));
        vm.prank(user);
        bgt.multicall(data);

        // check the states after cancelling the boosts.
        assertEq(bgt.balanceOf(user), amount1 + amount2);
        assertEq(bgt.unboostedBalanceOf(user), amount1 + amount2);

        (uint32 blockNumberLast, uint224 balance) = bgt.boostedQueue(user, valData.pubkey);
        (uint32 blockNumberLast2, uint224 balance2) = bgt.boostedQueue(user, valPubkey2);
        // block number last should not change after cancelling the boost
        assertEq(blockNumberLast, uint32(block.number));
        assertEq(balance, 0);
        assertEq(blockNumberLast2, uint32(block.number));
        assertEq(balance2, 0);
    }

    function test_MultiCall_ActivateBoostInBatch_DoesNotFailIfNotEnoughTimePassed() public {
        // queue boosts
        (address user1, address user2) = _setUpUserAndMintBGT();

        uint256 currentBlockNumber = block.number;
        vm.prank(user1);
        bgt.queueBoost(valData.pubkey, 1);

        vm.roll(currentBlockNumber + BOOST_MAX_BLOCK_DELAY + 1); // user1 can activate boost
        vm.prank(user2);
        bgt.queueBoost(valData.pubkey, 1);
        vm.roll(currentBlockNumber + BOOST_MAX_BLOCK_DELAY + 2); // user2 can not activate boost
        // multicall activate boosts
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(IBGT.activateBoost, (user1, valData.pubkey));
        data[1] = abi.encodeCall(IBGT.activateBoost, (user2, valData.pubkey));
        bgt.multicall(data);
    }

    function test_MultiCall_ActivateBoostInBatch() public {
        // queue boosts
        (address user1, address user2) = _setUpUserAndMintBGT();

        vm.prank(user1);
        bgt.queueBoost(valData.pubkey, 1);
        vm.prank(user2);
        bgt.queueBoost(valData.pubkey, 1);

        (uint32 blockNumberLast,) = bgt.boostedQueue(user2, valData.pubkey);
        vm.roll(blockNumberLast + BOOST_MAX_BLOCK_DELAY + 1);

        // multicall activate boosts
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(IBGT.activateBoost, (user1, valData.pubkey));
        data[1] = abi.encodeCall(IBGT.activateBoost, (user2, valData.pubkey));
        bgt.multicall(data);

        // check user1
        _checkAfterActivateBoost(user1, 1);
        // check user2
        _checkAfterActivateBoost(user2, 1);
        // check validator and total boosts
        assertEq(bgt.boostees(valData.pubkey), 2);
        assertEq(bgt.totalBoosts(), 2);
    }

    function test_MultiCall_QueueDropBoostInBatch() public {
        testFuzz_MultiCall_QueueDropBoostInBatch(100, 40, 30);
    }

    function testFuzz_MultiCall_QueueDropBoostInBatch(
        uint256 boostAmount,
        uint256 dropAmount1,
        uint256 dropAmount2
    )
        public
    {
        boostAmount = _bound(boostAmount, 2, type(uint128).max - 1);
        dropAmount1 = _bound(dropAmount1, 1, boostAmount / 2);
        dropAmount2 = _bound(dropAmount2, 1, boostAmount / 2);
        // multicall drop boosts
        testFuzz_ActivateBoost(address(this), address(this), boostAmount);
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(IBGT.queueDropBoost, (valData.pubkey, uint128(dropAmount1)));
        data[1] = abi.encodeCall(IBGT.queueDropBoost, (valData.pubkey, uint128(dropAmount2)));

        bgt.multicall(data);
        (uint32 blockNumberLast, uint224 balance) = bgt.dropBoostQueue(address(this), valData.pubkey);
        assertEq(blockNumberLast, uint32(block.number));
        assertEq(balance, uint224(dropAmount1 + dropAmount2));
    }

    /* ERC20 functions */

    /// @dev Ensure that the contract has the correct metadata.
    function testMetadata() public view {
        assertEq(bgt.name(), "Bera Governance Token");
        assertEq(bgt.symbol(), "BGT");
        assertEq(bgt.decimals(), 18);
    }

    /// @dev Should fail if not called by an approved sender.
    function test_FailIfNotApprovedSender() public {
        address receiver = makeAddr("receiver");
        vm.expectRevert(IPOLErrors.NotApprovedSender.selector);
        bgt.approve(receiver, 1);

        vm.expectRevert(IPOLErrors.NotApprovedSender.selector);
        bgt.transfer(receiver, 1);

        vm.expectRevert(IPOLErrors.NotApprovedSender.selector);
        bgt.transferFrom(address(this), receiver, 1);
    }

    /// @dev Ensure that the distributor can approve an address to spend BGT.
    function test_Approve() public {
        vm.prank(address(distributor));
        vm.expectEmit(true, true, true, true);
        emit IERC20.Approval(address(distributor), address(this), 1);
        bgt.approve(address(this), 1);
        assertEq(bgt.allowance(address(distributor), address(this)), 1);
    }

    /// @dev Ensure that the sender can approve an address to spend BGT.
    function testFuzz_Approve(address owner, address spender, uint256 amount) public {
        vm.assume(owner != address(0));
        vm.assume(spender != address(0));
        vm.prank(governance);
        bgt.whitelistSender(owner, true);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IERC20.Approval(owner, spender, amount);
        bgt.approve(spender, amount);
        assertEq(bgt.allowance(owner, spender), amount);
    }

    /// @dev Should fail if the sender has insufficient balance.
    function test_FailTransferInsufficientBalance() public {
        vm.prank(address(distributor));
        vm.expectRevert(IPOLErrors.NotEnoughBalance.selector);
        bgt.transfer(address(this), 1);
    }

    /// @dev Ensure that the distributor can transfer BGT.
    function test_Transfer() public {
        vm.prank(address(blockRewardController));
        bgt.mint(address(distributor), 1);

        vm.prank(address(distributor));
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(distributor), address(this), 1);
        assertTrue(bgt.transfer(address(this), 1));
        assertEq(bgt.totalSupply(), 1);
        assertEq(bgt.balanceOf(address(this)), 1);
        assertEq(bgt.balanceOf(address(distributor)), 0);
    }

    /// @dev Ensure that the sender can transfer BGT.
    function testFuzz_Transfer(address sender, address receiver, uint256 amount) public {
        vm.assume(sender != address(0));
        vm.assume(receiver != address(0));
        amount = _bound(amount, 0, MAX_SUPPLY);
        vm.deal(address(bgt), amount);
        vm.prank(address(blockRewardController));
        bgt.mint(sender, amount);

        vm.prank(governance);
        bgt.whitelistSender(sender, true);

        vm.prank(sender);
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(sender, receiver, amount);
        assertTrue(bgt.transfer(receiver, amount));
        assertEq(bgt.totalSupply(), amount);

        if (sender == receiver) {
            assertEq(bgt.balanceOf(sender), amount);
        } else {
            assertEq(bgt.balanceOf(receiver), amount);
            assertEq(bgt.balanceOf(sender), 0);
        }
    }

    /// @dev Should fail if the sender has insufficient allowance.
    function test_FailTransferFromInsufficientAllowance() public {
        vm.prank(address(blockRewardController));
        bgt.mint(address(distributor), 1e18);

        vm.prank(address(distributor));
        bgt.approve(address(this), 0.9e18);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0.9e18, 1e18)
        );
        bgt.transferFrom(address(distributor), address(this), 1e18);
    }

    /// @dev Should fail if the caller has insufficient balance for indirect transfer.
    function test_FailIndirectTransferFromInsufficientAllowance() public {
        vm.prank(address(blockRewardController));
        bgt.mint(address(distributor), 1e18);

        vm.prank(address(distributor));
        bgt.approve(address(this), 0.9e18);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0.9e18, 1e18)
        );
        bgt.transferFrom(address(distributor), makeAddr("receiver"), 1e18);
    }

    /// @dev Should fail if the sender has insufficient balance.
    function test_FailTransferFromInsufficientBalance() public {
        vm.prank(address(distributor));
        bgt.approve(address(this), 1e18);

        vm.expectRevert(IPOLErrors.NotEnoughBalance.selector);
        bgt.transferFrom(address(distributor), address(this), 1e18);
    }

    /// @dev Ensure that the call can pull BGT from the distributor.
    function test_TransferFrom() public {
        vm.prank(address(blockRewardController));
        bgt.mint(address(distributor), 1e18);

        vm.prank(address(distributor));
        bgt.approve(address(this), 1e18);

        vm.prank(address(this));
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(distributor), address(this), 1e18);
        assertTrue(bgt.transferFrom(address(distributor), address(this), 1e18));
        assertEq(bgt.totalSupply(), 1e18);
        assertEq(bgt.balanceOf(address(this)), 1e18);
    }

    /// @dev Ensure that the sender can transfer BGT on behalf of the distributor.
    function testFuzz_TransferFrom(address sender, address receiver, uint256 approval, uint256 amount) public {
        vm.assume(sender != address(0));
        vm.assume(receiver != address(0));
        amount = _bound(amount, 0, MAX_SUPPLY);
        amount = _bound(amount, 0, approval);
        vm.deal(address(bgt), amount);
        vm.prank(address(blockRewardController));
        bgt.mint(address(distributor), amount);

        vm.prank(address(distributor));
        bgt.approve(sender, approval);
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(distributor), receiver, amount);

        vm.prank(sender);
        assertTrue(bgt.transferFrom(address(distributor), receiver, amount));
        assertEq(bgt.totalSupply(), amount);
        assertEq(bgt.balanceOf(receiver), amount);

        if (approval == type(uint256).max) {
            assertEq(bgt.allowance(address(distributor), sender), type(uint256).max);
        } else {
            assertEq(bgt.allowance(address(distributor), sender), approval - amount);
        }
    }

    /// @dev should fail as this contract does not have any receive function to receive ETH
    function test_Redeem_FailsWithETHTransferFail() public {
        testFuzz_Mint(address(distributor), 1 ether);
        vm.prank(address(distributor));
        vm.expectRevert(abi.encodeWithSelector(SafeTransferLib.ETHTransferFailed.selector));
        bgt.redeem(address(this), 1 ether);
    }

    /**
     * @dev There's a potential bug in the BGT redeem function's invariant check.
     * The current implementation may not properly verify ETH balance availability,
     * which could lead to insufficient ETH backing for remaining tokens.
     * 
     * Proposed fix:
     * function redeem(address to, uint256 amount) external {
     *     // Check if the sender has enough unboosted balance
     *     require(unboostedBalanceOf(msg.sender) >= amount, "Not enough unboosted balance");
     *     
     *     // Check if the contract has enough ETH for this redemption
     *     require(address(this).balance >= amount, "Insufficient ETH for redemption");
     *     
     *     // Then check if the remaining ETH will be sufficient for remaining supply
     *     require(address(this).balance - amount >= totalSupply() - amount, "Invariant violation");
     *     
     *     // Burn tokens from sender
     *     _burn(msg.sender, amount);
     *     
     *     // Send ETH to the specified recipient
     *     SafeTransferLib.safeTransferETH(to, amount);
     *     
     *     // Emit redemption event
     *     emit Redeem(msg.sender, to, amount);
     * }
     */
    function test_Redeem_FailsIfInvariantCheckFails() public {
        testFuzz_Mint(receiverAddr, 1 ether);
        vm.deal(address(bgt), 1 ether - 1);
        vm.prank(receiverAddr);
        vm.expectRevert(IPOLErrors.InvariantCheckFailed.selector);
        bgt.redeem(receiverAddr, 0.5 ether);
    }

    function test_Redeem_FailsIfNotEnoughUnboostedBalance() public {
        test_QueueBoost();
        vm.prank(address(distributor));
        vm.expectRevert(IPOLErrors.NotEnoughBalance.selector);
        bgt.redeem(address(distributor), 1);
    }

    function test_Redeem() public {
        testFuzz_Mint(address(distributor), 1000 ether);
        // should not revert because invariant check passes
        vm.prank(address(distributor));
        vm.expectEmit();
        emit IBGT.Redeem(address(distributor), receiverAddr, 10 ether);
        bgt.redeem(receiverAddr, 10 ether);
        assertEq(bgt.balanceOf(address(distributor)), 990 ether);
        assertEq(bgt.totalSupply(), 990 ether);
        assertEq(address(bgt).balance, 990 ether);
        assertEq(receiverAddr.balance, 10 ether);
    }

    function testFuzz_Redeem(uint256 amount) public {
        amount = _bound(amount, 0, 1000 ether);
        testFuzz_Mint(address(distributor), 1000 ether);
        vm.prank(address(distributor));
        vm.expectEmit();
        emit IBGT.Redeem(address(distributor), receiverAddr, amount);
        bgt.redeem(receiverAddr, amount);
        assertEq(bgt.totalSupply(), 1000 ether - amount);
        assertEq(address(bgt).balance, 1000 ether - amount);
        assertEq(bgt.balanceOf(address(distributor)), 1000 ether - amount);
        assertEq(receiverAddr.balance, amount);
    }

    function testFuzz_SetBgtTermsAndConditions(string memory termsAndConditions) public {
        // add a random character to the end of the string to ensure that the string is not empty
        termsAndConditions = string.concat(termsAndConditions, "+");
        string memory _oldTermsAndConditions = bgt.bgtTermsAndConditions();
        vm.expectEmit();
        emit IBGT.BgtTermsAndConditionsChanged(termsAndConditions);
        vm.prank(governance);
        bgt.setBgtTermsAndConditions(termsAndConditions);
        assertEq(bgt.bgtTermsAndConditions(), termsAndConditions);
        assertNotEq(bgt.bgtTermsAndConditions(), _oldTermsAndConditions);
    }

    function test_SetBgtTermsAndConditions() public {
        testFuzz_SetBgtTermsAndConditions("BGT TERMS AND CONDITIONS");
    }

    function test_SetBgtTermsAndConditions_FailsIfNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        bgt.setBgtTermsAndConditions("BGT TERMS AND CONDITIONS");
    }

    function testFuzz_BurnExcess(
        address caller,
        uint256 nativeTokenBalance,
        uint256 bgtSupply,
        uint256 minRewardPerBlock
    )
        public
    {
        uint256 baseRate = 0.5 ether;
        minRewardPerBlock =
            _bound(minRewardPerBlock, 0, BlockRewardController(blockRewardController).MAX_MIN_BOOSTED_REWARD_RATE());

        uint256 maxBgtPerBlock = minRewardPerBlock + baseRate;
        uint256 potentialMintableAmountInBuffer = 8191 * maxBgtPerBlock;

        bgtSupply = _bound(bgtSupply, 0, 1e6 ether - potentialMintableAmountInBuffer);
        nativeTokenBalance = _bound(nativeTokenBalance, bgtSupply + potentialMintableAmountInBuffer, 1e6 ether);

        // Simulate amount of BGT circulating
        testFuzz_Mint(address(distributor), bgtSupply);

        // Simulate native token accumulated in BGT contract
        vm.deal(address(bgt), nativeTokenBalance);

        vm.startPrank(governance);
        BlockRewardController(blockRewardController).setMinBoostedRewardRate(minRewardPerBlock);
        BlockRewardController(blockRewardController).setBaseRate(baseRate);
        vm.stopPrank();

        vm.prank(caller);
        if (nativeTokenBalance > bgtSupply + potentialMintableAmountInBuffer) {
            vm.expectEmit();
            emit IBGT.ExceedingReservesBurnt(caller, nativeTokenBalance - bgtSupply - potentialMintableAmountInBuffer);
        }
        bgt.burnExceedingReserves();

        assertGe(address(bgt).balance, bgt.totalSupply());
        assertEq(address(bgt).balance, bgt.totalSupply() + potentialMintableAmountInBuffer);
    }

    // Internal Helper functions

    function _setUpUserAndMintBGT() internal returns (address user1, address user2) {
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        vm.startPrank(address(blockRewardController));
        bgt.mint(user1, 1);
        bgt.mint(user2, 1);
        vm.stopPrank();
        return (user1, user2);
    }

    // perform checks on the output data

    function _checkAfterQueuedBoost(address user, uint256 amount) internal view {
        // bgt balance should stay same, but credit balance to queued boost maps
        assertEq(bgt.balanceOf(user), amount);
        // unboosted balance should be debited
        assertEq(bgt.unboostedBalanceOf(user), 0);

        (uint32 blockNumberLast, uint224 balance) = bgt.boostedQueue(user, valData.pubkey);
        assertEq(blockNumberLast, uint32(block.number));
        assertEq(balance, amount);
        assertEq(bgt.queuedBoost(user), amount);

        assertEq(bgt.boosted(user, valData.pubkey), 0);
        assertEq(bgt.boosts(user), 0);
        assertEq(bgt.boostees(valData.pubkey), 0);
        assertEq(bgt.totalBoosts(), 0);
    }

    function _checkAfterCancelBoost(
        address user,
        uint256 queuedAmount,
        uint256 cancelAmount,
        uint32 blockNumberLast
    )
        internal
        view
    {
        // bgt balance should stay same, but debit balance from queued boost maps
        assertEq(bgt.balanceOf(user), queuedAmount);

        (uint32 blockNumberAfter, uint224 balanceAfter) = bgt.boostedQueue(user, valData.pubkey);
        // cancel boost does not change the stored block number of boost queue
        assertEq(blockNumberAfter, blockNumberLast);
        assertEq(balanceAfter, uint224(queuedAmount - cancelAmount));
        assertEq(bgt.queuedBoost(user), uint224(queuedAmount - cancelAmount));

        assertEq(bgt.boosted(user, valData.pubkey), 0);
        assertEq(bgt.boosts(user), 0);
        assertEq(bgt.boostees(valData.pubkey), 0);
        assertEq(bgt.totalBoosts(), 0);
    }

    function _checkAfterActivateBoost(address user, uint256 amount) internal view {
        // bgt balance should stay the same, but credit balance to boost maps
        assertEq(bgt.balanceOf(user), amount);
        (uint32 blockNumberAfter, uint128 balanceAfter) = bgt.boostedQueue(user, valData.pubkey);
        assertEq(blockNumberAfter, 0);
        assertEq(balanceAfter, 0);
        assertEq(bgt.queuedBoost(user), 0);
        assertEq(bgt.boosted(user, valData.pubkey), amount);
        assertEq(bgt.boosts(user), amount);
    }

    function _checkAfterDropBoost(address user, uint256 boostAmount, uint256 dropAmount) internal view {
        // bgt balance should stay the same, but debit balance from boost maps
        assertEq(bgt.balanceOf(user), boostAmount);
        assertEq(bgt.boosted(user, valData.pubkey), boostAmount - dropAmount);
        assertEq(bgt.boosts(user), boostAmount - dropAmount);
        assertEq(bgt.boostees(valData.pubkey), boostAmount - dropAmount);
        assertEq(bgt.totalBoosts(), boostAmount - dropAmount);
    }
}
