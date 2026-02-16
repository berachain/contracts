// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import { POLTest, Vm } from "./POL.t.sol";
import { IERC1967 } from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import { MockHoney } from "@mock/honey/MockHoney.sol";
import { IRewardAllocation } from "src/pol/interfaces/IRewardAllocation.sol";
import { IPOLErrors } from "src/pol/interfaces/IPOLErrors.sol";
import { RewardAllocatorFactory } from "src/pol/rewards/RewardAllocatorFactory.sol";

contract RewardAllocatorFactoryTest is POLTest {
    address internal allocationBot = makeAddr("allocationBot");

    address internal _stakeTokenVault;
    address internal _stakeTokenVault2;

    address internal _receiver;
    address internal _receiver2;

    function setUp() public override {
        super.setUp();

        _stakeTokenVault = address(new MockHoney());
        _stakeTokenVault2 = address(new MockHoney());

        vm.startPrank(governance);
        rewardAllocatorFactory.grantRole(rewardAllocatorFactory.ALLOCATION_SETTER_ROLE(), allocationBot);

        _receiver = factory.createRewardVault(address(_stakeTokenVault));
        _receiver2 = factory.createRewardVault(address(_stakeTokenVault2));

        beraChef.setVaultWhitelistedStatus(_receiver, true, "");
        beraChef.setVaultWhitelistedStatus(_receiver2, true, "");
        vm.stopPrank();
    }

    function test_setBaselineAllocation() public {
        IRewardAllocation.Weight[] memory weights = new IRewardAllocation.Weight[](2);
        weights[0] = IRewardAllocation.Weight({ receiver: _receiver, percentageNumerator: 6000 });
        weights[1] = IRewardAllocation.Weight({ receiver: _receiver2, percentageNumerator: 4000 });

        vm.prank(allocationBot);
        rewardAllocatorFactory.setBaselineAllocation(weights);

        uint256 currentBlock = block.number;

        IRewardAllocation.RewardAllocation memory alloc = rewardAllocatorFactory.getBaselineAllocation();
        assertEq(alloc.startBlock, uint64(currentBlock));
        assertEq(alloc.weights[0].receiver, _receiver);
        assertEq(alloc.weights[0].percentageNumerator, 6000);
        assertEq(alloc.weights[1].receiver, _receiver2);
        assertEq(alloc.weights[1].percentageNumerator, 4000);
    }

    function test_getBaselineAllocation_defaultIsEmpty() public view {
        IRewardAllocation.RewardAllocation memory alloc = rewardAllocatorFactory.getBaselineAllocation();
        // startBlock is 0 and no weights set yet in a fresh factory before setBaselineAllocation
        // Note: setUp() called initialize only; we did not set allocation yet in this test
        assertEq(alloc.startBlock, 0);
        assertEq(alloc.weights.length, 0);
    }

    function test_setBaselineAllocation_requiresAllocationSetter() public {
        IRewardAllocation.Weight[] memory weights = new IRewardAllocation.Weight[](1);
        weights[0] = IRewardAllocation.Weight({ receiver: makeAddr("vault1"), percentageNumerator: 10_000 });

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                rewardAllocatorFactory.ALLOCATION_SETTER_ROLE()
            )
        );
        rewardAllocatorFactory.setBaselineAllocation(weights);
    }

    function test_setBaselineAllocation_revertsIfWeightsAreInvalid() public {
        address invalidReceiver = makeAddr("invalidReceiver");
        IRewardAllocation.Weight[] memory weights = new IRewardAllocation.Weight[](2);
        weights[0] = IRewardAllocation.Weight({ receiver: invalidReceiver, percentageNumerator: 5000 });
        weights[1] = IRewardAllocation.Weight({ receiver: _receiver2, percentageNumerator: 5000 });

        vm.prank(allocationBot);
        vm.expectRevert();
        rewardAllocatorFactory.setBaselineAllocation(weights);
    }

    function test_upgradeTo_FailIfNotAdmin() public {
        address newImplementation = address(new RewardAllocatorFactory());
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                rewardAllocatorFactory.DEFAULT_ADMIN_ROLE()
            )
        );
        rewardAllocatorFactory.upgradeToAndCall(newImplementation, bytes(""));
    }

    function test_upgradeToAndCall() public {
        address newImplementation = address(new RewardAllocatorFactory());
        vm.prank(governance);
        vm.expectEmit();
        emit IERC1967.Upgraded(newImplementation);
        rewardAllocatorFactory.upgradeToAndCall(newImplementation, bytes(""));
        assertEq(
            vm.load(address(rewardAllocatorFactory), ERC1967Utils.IMPLEMENTATION_SLOT),
            bytes32(uint256(uint160(newImplementation)))
        );
    }
}
