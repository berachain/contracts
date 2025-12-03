// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC1967 } from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import { IBGT } from "src/pol/interfaces/IBGT.sol";
import { IBlockRewardController, IPOLErrors } from "src/pol/interfaces/IBlockRewardController.sol";
import { BlockRewardController } from "src/pol/rewards/BlockRewardController.sol";

import { BeaconDepositMock, POLTest } from "./POL.t.sol";

contract BlockRewardControllerTest is POLTest {
    /// @dev Ensure that the contract is owned by the governance.
    function test_OwnerIsGovernance() public view {
        assertEq(blockRewardController.owner(), governance);
    }

    /// @dev Should fail if not the owner
    function test_FailIfNotOwner() public {
        vm.expectRevert();
        blockRewardController.transferOwnership(address(1));

        vm.expectRevert();
        blockRewardController.setDistributor(address(1));

        vm.expectRevert();
        blockRewardController.setRewardRate(255);

        address newImpl = address(new BlockRewardController());
        vm.expectRevert();
        blockRewardController.upgradeToAndCall(newImpl, bytes(""));
    }

    /// @dev Should upgrade to a new implementation
    function test_UpgradeTo() public {
        address newImpl = address(new BlockRewardController());
        vm.expectEmit(true, true, true, true);
        emit IERC1967.Upgraded(newImpl);
        vm.prank(governance);
        blockRewardController.upgradeToAndCall(newImpl, bytes(""));
        assertEq(
            vm.load(address(blockRewardController), ERC1967Utils.IMPLEMENTATION_SLOT),
            bytes32(uint256(uint160(newImpl)))
        );
    }

    /// @dev Should fail if initialize again
    function test_FailIfInitializeAgain() public {
        vm.expectRevert();
        blockRewardController.initialize(address(bgt), address(distributor), address(beraChef), address(governance));
    }

    function test_SetDistributor_FailIfZeroAddress() public {
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        blockRewardController.setDistributor(address(0));
    }

    /// @dev Ensure that the distributor is set
    function test_SetDistributor() public {
        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        address _distributor = address(distributor);
        emit IBlockRewardController.SetDistributor(_distributor);
        blockRewardController.setDistributor(_distributor);
        assertEq(blockRewardController.distributor(), _distributor);
    }

    /// @dev Ensure that the base rate is set
    function test_SetBaseRate() public {
        testFuzz_SetBaseRate(1 ether);
    }

    /// @dev Ensure that the reward rate is set
    function test_SetRewardRate() public {
        testFuzz_SetRewardRate(1 ether);
    }

    /// @dev Ensure that min boosted reward rate is also set
    function test_SetMinBoostedRewardRate() public {
        testFuzz_SetMinBoostedRewardRate(0.1 ether);
    }

    /// @dev Ensure that boost multiplier is also set
    function test_SetBoostMultiplier() public {
        testFuzz_SetBoostMultiplier(3 ether);
    }

    /// @dev Ensure that reward convexity is also set
    function test_SetRewardConvexity() public {
        testFuzz_SetRewardConvexity(0.5 ether);
    }

    /// @dev Parameterized setter for the base rate
    function testFuzz_SetBaseRate(uint256 baseRate) public {
        baseRate = _bound(baseRate, 0, blockRewardController.MAX_BASE_RATE());
        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit IBlockRewardController.BaseRateChanged(0, baseRate);
        blockRewardController.setBaseRate(baseRate);
        assertEq(blockRewardController.baseRate(), baseRate);
    }

    /// @dev Parameterized setter for the reward rate
    function testFuzz_SetRewardRate(uint256 rewardRate) public {
        rewardRate = _bound(rewardRate, 0, blockRewardController.MAX_REWARD_RATE());
        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit IBlockRewardController.RewardRateChanged(0, rewardRate);
        blockRewardController.setRewardRate(rewardRate);
        assertEq(blockRewardController.rewardRate(), rewardRate);
    }

    /// @dev Parameterized setter for min boosted reward rate
    function testFuzz_SetMinBoostedRewardRate(uint256 min) public {
        min = _bound(min, 0, blockRewardController.MAX_MIN_BOOSTED_REWARD_RATE());
        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit IBlockRewardController.MinBoostedRewardRateChanged(0, min);
        blockRewardController.setMinBoostedRewardRate(min);
        assertEq(blockRewardController.minBoostedRewardRate(), min);
    }

    /// @dev Parameterized setter for boost multiplier
    function testFuzz_SetBoostMultiplier(uint256 multiplier) public {
        multiplier = _bound(multiplier, 0, blockRewardController.MAX_BOOST_MULTIPLIER());
        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit IBlockRewardController.BoostMultiplierChanged(0, multiplier);
        blockRewardController.setBoostMultiplier(multiplier);
        assertEq(blockRewardController.boostMultiplier(), multiplier);
    }

    /// @dev Parameterized setter for reward convexity
    function testFuzz_SetRewardConvexity(uint256 convexity) public {
        convexity = _bound(convexity, 1, blockRewardController.MAX_REWARD_CONVEXITY());
        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit IBlockRewardController.RewardConvexityChanged(0, convexity);
        blockRewardController.setRewardConvexity(convexity);
        assertEq(uint256(blockRewardController.rewardConvexity()), convexity);
    }

    /// @dev Should fail if not the distributor
    function test_FailIfNotDistributor() public {
        vm.expectRevert();
        blockRewardController.processRewards(valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, true);
    }

    /// @dev Should process zero rewards
    function test_ProcessZeroRewards() public {
        test_SetDistributor();

        vm.prank(address(distributor));
        vm.expectEmit(true, true, true, true);
        emit IBlockRewardController.BlockRewardProcessed(valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, 0, 0);
        assertEq(blockRewardController.processRewards(valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, true), 0);
    }

    /// @dev Should process rewards
    function test_ProcessRewards() public {
        test_SetDistributor();
        test_SetBaseRate();
        test_SetRewardRate();
        test_SetMinBoostedRewardRate();
        test_SetBoostMultiplier();
        test_SetRewardConvexity();

        // @dev should process min reward given no boosts
        vm.prank(address(distributor));
        vm.expectEmit(true, true, true, true);
        emit IBlockRewardController.BlockRewardProcessed(valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, 1 ether, 0.1 ether);

        // expect calls to mint BGT to the distributor and operator
        vm.expectCall(address(bgt), abi.encodeCall(IBGT.mint, (operator, 1.0 ether)));
        vm.expectCall(address(bgt), abi.encodeCall(IBGT.mint, (address(distributor), 0.1 ether)));
        assertEq(blockRewardController.processRewards(valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, true), 0.1 ether);
    }

    /// @dev Should process the maximum number of rewards without reverting (100% boost to the validator)
    function test_ProcessRewardsMax() public {
        _helper_ControllerSetters(1.5 ether, 0, 3 ether, 0.5 ether);
        _helper_Boost(address(0x1), 1 ether, valData.pubkey);

        // @dev should process max reward given 100% boosts to the user
        vm.prank(address(distributor));
        vm.expectEmit(true, true, true, true);
        emit IBlockRewardController.BlockRewardProcessed(valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, 1 ether, 4.5 ether);

        // expect calls to mint BGT to the distributor and operator
        vm.expectCall(address(bgt), abi.encodeCall(IBGT.mint, (operator, 1.0 ether)));
        vm.expectCall(address(bgt), abi.encodeCall(IBGT.mint, (address(distributor), 4.5 ether)));
        assertEq(blockRewardController.processRewards(valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, true), 4.5 ether);
    }

    /// @dev Should process the minimum number of rewards without reverting (0% boost to the validator)
    function test_ProcessRewardsMin() public {
        _helper_ControllerSetters(1.5 ether, 0.1 ether, 3 ether, 0.5 ether);

        // @dev should process min reward given no boosts
        vm.prank(address(distributor));
        vm.expectEmit(true, true, true, true);
        emit IBlockRewardController.BlockRewardProcessed(valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, 1 ether, 0.1 ether);

        // expect calls to mint BGT to the distributor and operator
        vm.expectCall(address(bgt), abi.encodeCall(IBGT.mint, (operator, 1.0 ether)));
        vm.expectCall(address(bgt), abi.encodeCall(IBGT.mint, (address(distributor), 0.1 ether)));
        assertEq(blockRewardController.processRewards(valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, true), 0.1 ether);
    }

    /// @dev Should compute rewards correctly (expected values are computed offline)
    function test_ComputeRewards() public view {
        uint256 rewardRate = 1.5 ether;
        uint256 multiplier = 3 ether;
        int256 convexity = 0.5 ether;

        uint256 maxDelta = 0.000_01 ether;

        // check for different values of boosts

        uint256 reward = blockRewardController.computeReward(0, rewardRate, multiplier, convexity);
        assertEq(reward, 0);

        reward = blockRewardController.computeReward(1 ether, rewardRate, multiplier, convexity);
        uint256 expected = 4.5 ether;
        assertEq(reward, expected);

        reward = blockRewardController.computeReward(0.1 ether, rewardRate, multiplier, convexity);
        expected = 2.921 ether;
        assertApproxEqAbs(reward, expected, maxDelta);

        reward = blockRewardController.computeReward(0.01 ether, rewardRate, multiplier, convexity);
        expected = 1.384_62 ether;
        assertApproxEqAbs(reward, expected, maxDelta);

        reward = blockRewardController.computeReward(0.95 ether, rewardRate, multiplier, convexity);
        expected = 4.470_96 ether;
        assertApproxEqAbs(reward, expected, maxDelta);

        // check for different values of convexity

        reward = blockRewardController.computeReward(0, rewardRate, multiplier, 0);
        expected = 0; // should be max, but look at docs inside the function
        assertEq(reward, expected);

        reward = blockRewardController.computeReward(0, rewardRate, multiplier, 1);
        expected = 0;
        assertEq(reward, expected);

        // for any boost value > 0, if reward convexity is small reward is almost flat on max value (minus delta)
        reward = blockRewardController.computeReward(1, rewardRate, multiplier, 0);
        expected = 4.5 ether;
        assertApproxEqAbs(reward, expected, maxDelta);

        reward = blockRewardController.computeReward(1, rewardRate, multiplier, 0.000_000_1 ether);
        expected = 4.5 ether;
        assertApproxEqAbs(reward, expected, maxDelta);
    }

    /// @dev Should bound compute rewards correctly to its theoretical limits
    function testFuzz_ComputeRewards(
        uint256 boostPower,
        uint256 rewardRate,
        uint256 multiplier,
        uint256 _convexity
    )
        public
        view
    {
        rewardRate = _bound(rewardRate, 0, blockRewardController.MAX_REWARD_RATE());
        boostPower = _bound(boostPower, 0, 1 ether);
        multiplier = _bound(multiplier, 0, blockRewardController.MAX_BOOST_MULTIPLIER());
        int256 convexity = int256(_bound(_convexity, 0, blockRewardController.MAX_REWARD_CONVEXITY()));

        uint256 reward = blockRewardController.computeReward(boostPower, rewardRate, multiplier, convexity);
        uint256 maxReward = multiplier * rewardRate / 1e18;
        assertGe(reward, 0);
        assertLe(reward, maxReward);
    }

    /// @dev Should process rewards without reverting (boost distributed among 2 validators)
    function testFuzz_ProcessRewards(
        uint256 rewardRate,
        uint256 minReward,
        uint256 multiplier,
        uint256 convexity,
        uint256 boostVal0,
        uint256 boostVal1
    )
        public
    {
        rewardRate = _bound(rewardRate, 0, blockRewardController.MAX_REWARD_RATE());
        minReward = _bound(minReward, 0, blockRewardController.MAX_MIN_BOOSTED_REWARD_RATE());
        multiplier = _bound(multiplier, 0, blockRewardController.MAX_BOOST_MULTIPLIER());
        convexity = _bound(convexity, 0, blockRewardController.MAX_REWARD_CONVEXITY());

        bytes memory valPubkey1 = "validator 1 pubkey";
        address operator1 = makeAddr("operator");
        BeaconDepositMock(beaconDepositContract).setOperator(valPubkey1, operator1);

        _helper_ControllerSetters(rewardRate, minReward, multiplier, convexity);
        _helper_Boost(address(0x2), boostVal0, valData.pubkey);
        _helper_Boost(address(0x3), boostVal1, valPubkey1);

        vm.prank(address(distributor));
        // expect calls to mint BGT to the distributor
        vm.expectCall(address(bgt), abi.encodeCall(IBGT.mint, (operator, 1.0 ether)));
        // expect reward between formula's min and max
        uint256 reward = blockRewardController.processRewards(valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, true);
        assertGe(reward, minReward);
        uint256 maxReward = multiplier * rewardRate / 1e18;
        maxReward = maxReward > minReward ? maxReward : minReward;

        assertLe(reward, maxReward);
    }

    function _helper_ControllerSetters(
        uint256 rewardRate,
        uint256 minReward,
        uint256 multiplier,
        uint256 convexity
    )
        internal
    {
        test_SetDistributor();
        test_SetBaseRate();
        testFuzz_SetRewardRate(rewardRate);
        testFuzz_SetMinBoostedRewardRate(minReward);
        testFuzz_SetBoostMultiplier(multiplier);
        testFuzz_SetRewardConvexity(convexity);

        vm.deal(address(bgt), address(bgt).balance + rewardRate * multiplier / 1e18); // add max bgt minted in a block
    }

    function _helper_Mint(address user, uint256 amount) internal {
        vm.deal(address(bgt), address(bgt).balance + amount);
        vm.prank(address(blockRewardController));
        bgt.mint(user, amount);
    }

    function _helper_QueueBoost(address user, bytes memory pubkey, uint256 amount) internal {
        _helper_Mint(user, amount);
        vm.prank(user);
        bgt.queueBoost(pubkey, uint128(amount));
    }

    function _helper_ActivateBoost(address caller, address user, bytes memory pubkey, uint256 amount) internal {
        _helper_QueueBoost(user, pubkey, amount);
        (uint32 blockNumberLast,) = bgt.boostedQueue(user, valData.pubkey);
        vm.roll(block.number + blockNumberLast + HISTORY_BUFFER_LENGTH + 1);
        vm.prank(caller);
        bgt.activateBoost(user, pubkey);
    }

    function _helper_Boost(address user, uint256 amount, bytes memory pubkey) internal {
        amount = _bound(amount, 1, type(uint128).max / 2);
        _helper_ActivateBoost(user, user, pubkey, amount);
    }
}
