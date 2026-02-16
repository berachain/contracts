// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { DistributorTest } from "./Distributor.t.sol";
import { IPOLErrors } from "src/pol/interfaces/IPOLErrors.sol";
import { IDedicatedEmissionStreamManager } from "src/pol/interfaces/IDedicatedEmissionStreamManager.sol";
import { IRewardAllocation } from "src/pol/interfaces/IRewardAllocation.sol";
import { IDistributor } from "src/pol/interfaces/IDistributor.sol";
import { IRewardVault } from "src/pol/interfaces/IRewardVault.sol";
import { MockERC20 } from "@mock/token/MockERC20.sol";

contract DedicatedEmissionStreamManagerTest is DistributorTest {
    bytes32 internal allocationManagerRole;
    address internal allocationManager = makeAddr("allocationManager");

    address public graVault1;
    address public graVault2;

    function setUp() public virtual override {
        // deploy pol
        super.setUp();

        MockERC20 graToken1 = new MockERC20();
        MockERC20 graToken2 = new MockERC20();
        graVault1 = factory.createRewardVault(address(graToken1));
        graVault2 = factory.createRewardVault(address(graToken2));
        vm.startPrank(governance);
        beraChef.setVaultWhitelistedStatus(address(graVault1), true, "");
        beraChef.setVaultWhitelistedStatus(address(graVault2), true, "");
        vm.stopPrank();

        allocationManagerRole = dedicatedEmissionStreamManager.ALLOCATION_MANAGER_ROLE();
        defaultAdminRole = dedicatedEmissionStreamManager.DEFAULT_ADMIN_ROLE();
        vm.prank(governance);
        dedicatedEmissionStreamManager.grantRole(allocationManagerRole, allocationManager);
    }

    function test_deployment() public view {
        assertEq(dedicatedEmissionStreamManager.distributor(), address(distributor));
        assertEq(address(distributor.dedicatedEmissionStreamManager()), address(dedicatedEmissionStreamManager));
        assert(dedicatedEmissionStreamManager.hasRole(allocationManagerRole, allocationManager));
        assert(dedicatedEmissionStreamManager.hasRole(defaultAdminRole, governance));
    }

    function test_grantAllocationManagerRole() public {
        address newAllocationManager = makeAddr("newAllocationManager");
        vm.prank(governance);
        dedicatedEmissionStreamManager.grantRole(allocationManagerRole, newAllocationManager);
        assert(dedicatedEmissionStreamManager.hasRole(allocationManagerRole, allocationManager));
    }

    function test_grantAllocationManagerRoleFailNotAdmin() public {
        address newAllocationManager = makeAddr("newAllocationManager");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), defaultAdminRole
            )
        );
        dedicatedEmissionStreamManager.grantRole(allocationManagerRole, newAllocationManager);
    }

    function test_setDistributor() public {
        address newDistributor = makeAddr("newDistributor");
        vm.prank(governance);
        dedicatedEmissionStreamManager.setDistributor(newDistributor);
        assertEq(dedicatedEmissionStreamManager.distributor(), newDistributor);
    }

    function test_setDistributorFailNotAdmin() public {
        address newDistributor = makeAddr("newDistributor");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), defaultAdminRole
            )
        );
        dedicatedEmissionStreamManager.setDistributor(newDistributor);
    }

    function test_setDistributorFailZeroAddress() public {
        vm.prank(governance);
        vm.expectRevert(abi.encodeWithSelector(IPOLErrors.ZeroAddress.selector));
        dedicatedEmissionStreamManager.setDistributor(address(0));
    }

    function test_setBeraChef() public {
        address newBeraChef = makeAddr("newBeraChef");
        vm.prank(governance);
        dedicatedEmissionStreamManager.setBeraChef(newBeraChef);
        assertEq(address(dedicatedEmissionStreamManager.beraChef()), newBeraChef);
    }

    function test_setBeraChefFailNotAdmin() public {
        address newBeraChef = makeAddr("newBeraChef");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), defaultAdminRole
            )
        );
        dedicatedEmissionStreamManager.setBeraChef(newBeraChef);
    }

    function test_setBeraChefFailZeroAddress() public {
        vm.prank(governance);
        vm.expectRevert(abi.encodeWithSelector(IPOLErrors.ZeroAddress.selector));
        dedicatedEmissionStreamManager.setBeraChef(address(0));
    }

    function testFuzz_setEmissionPerc(uint96 newEmissionPerc) public {
        newEmissionPerc = uint96(bound(uint256(newEmissionPerc), 0, 1e4));
        vm.prank(allocationManager);
        vm.expectEmit();
        emit IDedicatedEmissionStreamManager.EmissionPercSet(newEmissionPerc);
        dedicatedEmissionStreamManager.setEmissionPerc(newEmissionPerc);
        assertEq(dedicatedEmissionStreamManager.emissionPerc(), newEmissionPerc);
    }

    function test_setEmissionPercFailNotAllocationManager() public {
        uint96 newEmissionPerc = 5000;
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), allocationManagerRole
            )
        );
        dedicatedEmissionStreamManager.setEmissionPerc(newEmissionPerc);
    }

    function test_setEmissionPercFailInvalidPercentage() public {
        uint96 newEmissionPerc = 1e5;
        vm.prank(allocationManager);
        vm.expectRevert(abi.encodeWithSelector(IPOLErrors.InvalidEmissionPerc.selector));
        dedicatedEmissionStreamManager.setEmissionPerc(newEmissionPerc);
    }

    function test_setRewardAllocation() public {
        IRewardAllocation.Weight[] memory newRewardAllocation = _helper_getWeights();
        vm.prank(allocationManager);
        vm.expectEmit();
        emit IDedicatedEmissionStreamManager.RewardAllocationSet(newRewardAllocation);
        dedicatedEmissionStreamManager.setRewardAllocation(newRewardAllocation);

        IRewardAllocation.Weight[] memory returnedAllocation = dedicatedEmissionStreamManager.getRewardAllocation();
        assertEq(returnedAllocation.length, newRewardAllocation.length);
        for (uint256 i; i < returnedAllocation.length; ++i) {
            assertEq(returnedAllocation[i].receiver, newRewardAllocation[i].receiver);
            assertEq(returnedAllocation[i].percentageNumerator, newRewardAllocation[i].percentageNumerator);
        }
    }

    function test_setRewardAllocationTwice() public {
        test_setRewardAllocation();

        IRewardAllocation.Weight[] memory newRewardAllocation = new IRewardAllocation.Weight[](2);
        newRewardAllocation[0] = IRewardAllocation.Weight(address(graVault1), 2000);
        newRewardAllocation[1] = IRewardAllocation.Weight(address(graVault2), 8000);
        vm.prank(allocationManager);
        vm.expectEmit();
        emit IDedicatedEmissionStreamManager.RewardAllocationSet(newRewardAllocation);
        dedicatedEmissionStreamManager.setRewardAllocation(newRewardAllocation);

        IRewardAllocation.Weight[] memory returnedAllocation = dedicatedEmissionStreamManager.getRewardAllocation();
        assertEq(returnedAllocation.length, newRewardAllocation.length);
        for (uint256 i; i < returnedAllocation.length; ++i) {
            assertEq(returnedAllocation[i].receiver, newRewardAllocation[i].receiver);
            assertEq(returnedAllocation[i].percentageNumerator, newRewardAllocation[i].percentageNumerator);
        }
    }

    function test_setRewardAllocationFailNotAllocationManager() public {
        IRewardAllocation.Weight[] memory newRewardAllocation = _helper_getWeights();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), allocationManagerRole
            )
        );
        dedicatedEmissionStreamManager.setRewardAllocation(newRewardAllocation);
    }

    function test_setRewardAllocationFailInvalidWeights() public {
        IRewardAllocation.Weight[] memory newRewardAllocation = _helper_getInvalidWeights();
        vm.prank(allocationManager);
        vm.expectRevert(abi.encodeWithSelector(IPOLErrors.InvalidRewardAllocationWeights.selector));
        dedicatedEmissionStreamManager.setRewardAllocation(newRewardAllocation);
    }

    function test_setRewardAllocationFailNotWhitelistedVault() public {
        IRewardAllocation.Weight[] memory newRewardAllocation = _helper_getWeights();

        // blacklist a vault
        vm.prank(governance);
        beraChef.setVaultWhitelistedStatus(address(graVault1), false, "");

        vm.prank(allocationManager);
        vm.expectRevert(abi.encodeWithSelector(IPOLErrors.NotWhitelistedVault.selector));
        dedicatedEmissionStreamManager.setRewardAllocation(newRewardAllocation);
    }

    function test_setTargetEmission() public {
        address vault = makeAddr("vault");
        uint256 targetEmission = 10_000 ether;
        vm.prank(allocationManager);
        vm.expectEmit();
        emit IDedicatedEmissionStreamManager.TargetEmissionSet(vault, targetEmission);
        dedicatedEmissionStreamManager.setTargetEmission(vault, targetEmission);
        assertEq(dedicatedEmissionStreamManager.targetEmission(vault), targetEmission);
    }

    function test_setTargetEmissionFailNotAllocationManager() public {
        address vault = makeAddr("vault");
        uint256 targetEmission = 10_000 ether;
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), allocationManagerRole
            )
        );
        dedicatedEmissionStreamManager.setTargetEmission(vault, targetEmission);
    }

    function test_setTargetEmissionFailInvalidTargetEmission() public {
        // First notify some emission to set the debt.
        testFuzz_notifyEmission(1 ether);

        address vault = makeAddr("vault");
        uint256 targetEmission = 0.5 ether; // Less than the debt.
        vm.prank(allocationManager);
        vm.expectRevert(abi.encodeWithSelector(IPOLErrors.InvalidTargetEmission.selector));
        dedicatedEmissionStreamManager.setTargetEmission(vault, targetEmission);
    }

    function testFuzz_notifyEmission(uint256 amount) public {
        amount = bound(amount, 0, 2 ether);
        address vault = makeAddr("vault");
        vm.prank(address(distributor));
        vm.expectEmit();
        emit IDedicatedEmissionStreamManager.NotifyEmission(vault, amount);
        dedicatedEmissionStreamManager.notifyEmission(vault, amount);
        assertEq(dedicatedEmissionStreamManager.debt(vault), amount);
    }

    function test_notifyEmissionFailNotDistributor() public {
        address vault = makeAddr("vault");
        uint256 amount = 1 ether;
        vm.expectRevert(abi.encodeWithSelector(IPOLErrors.NotDistributor.selector));
        dedicatedEmissionStreamManager.notifyEmission(vault, amount);
    }

    function _helper_getWeights() internal view returns (IRewardAllocation.Weight[] memory) {
        IRewardAllocation.Weight[] memory newRewardAllocation = new IRewardAllocation.Weight[](2);
        newRewardAllocation[0] = IRewardAllocation.Weight(address(graVault1), 5000);
        newRewardAllocation[1] = IRewardAllocation.Weight(address(graVault2), 5000);
        return newRewardAllocation;
    }

    function _helper_getInvalidWeights() internal view returns (IRewardAllocation.Weight[] memory) {
        // Total weight is 11000, which is invalid.
        IRewardAllocation.Weight[] memory newRewardAllocation = new IRewardAllocation.Weight[](2);
        newRewardAllocation[0] = IRewardAllocation.Weight(address(graVault1), 6000);
        newRewardAllocation[1] = IRewardAllocation.Weight(address(graVault2), 5000);
        return newRewardAllocation;
    }

    /// Dedicated emission stream tests

    function test_DistributeWithDedicatedEmissionStream_NoEmissionPerc() public {
        helper_SetDefaultRewardAllocation();

        _helper_setUpRewardAllocation(0, 10_000 ether);

        // Set reward allocation percentage to 0 and set reward allocation to non-zero weights.
        assertEq(dedicatedEmissionStreamManager.emissionPerc(), 0);
        IRewardAllocation.Weight[] memory rewardAllocation = dedicatedEmissionStreamManager.getRewardAllocation();
        assertGt(rewardAllocation.length, 0);

        distributor.distributeFor(
            DISTRIBUTE_FOR_TIMESTAMP, valData.index, valData.pubkey, valData.proposerIndexProof, valData.pubkeyProof
        );

        assertEq(bgt.allowance(address(distributor), address(vault)), TEST_BGT_PER_BLOCK);
        assertEq(bgt.allowance(address(distributor), graVault1), 0);
        assertEq(bgt.allowance(address(distributor), graVault2), 0);
        assertEq(dedicatedEmissionStreamManager.debt(graVault1), 0);
        assertEq(dedicatedEmissionStreamManager.debt(graVault2), 0);
    }

    function test_DistributeWithDedicatedEmissionStream_NoRewardAllocation() public {
        helper_SetDefaultRewardAllocation();

        // Set reward allocation percentage to 10% and set reward allocation to empty weights.
        vm.startPrank(allocationManager);
        dedicatedEmissionStreamManager.setEmissionPerc(1000);
        IRewardAllocation.Weight[] memory rewardAllocation = dedicatedEmissionStreamManager.getRewardAllocation();
        assertGt(dedicatedEmissionStreamManager.emissionPerc(), 0);
        assertEq(rewardAllocation.length, 0);

        distributor.distributeFor(
            DISTRIBUTE_FOR_TIMESTAMP, valData.index, valData.pubkey, valData.proposerIndexProof, valData.pubkeyProof
        );

        assertEq(bgt.allowance(address(distributor), address(vault)), TEST_BGT_PER_BLOCK);
        assertEq(bgt.allowance(address(distributor), graVault1), 0);
        assertEq(bgt.allowance(address(distributor), graVault2), 0);
        assertEq(dedicatedEmissionStreamManager.debt(graVault1), 0);
        assertEq(dedicatedEmissionStreamManager.debt(graVault2), 0);
    }

    /// @dev For test purposes the reward allocation is set to 100% on the available vault.
    function test_DistributeWithDedicatedEmissionStream() public {
        helper_SetDefaultRewardAllocation();
        // Percentage 10%
        // Emission target 10_000 ether for each vault
        _helper_setUpRewardAllocation(1000, 10_000 ether);

        IRewardAllocation.Weight[] memory rewardAllocation = dedicatedEmissionStreamManager.getRewardAllocation();

        uint256 bgtToRewardAllocation = TEST_BGT_PER_BLOCK * 1000 / 10_000; // 0.5 ether
        uint256 bgtToDefaultRewardAllocation = TEST_BGT_PER_BLOCK - bgtToRewardAllocation; // 4.5 ether

        vm.expectEmit(true, true, true, true);
        // expect events for notifying the emission and distributing the rewards to the reward allocation vaults
        for (uint256 i; i < rewardAllocation.length; ++i) {
            uint256 expectedEmission = bgtToRewardAllocation * rewardAllocation[i].percentageNumerator / 10_000;
            emit IDedicatedEmissionStreamManager.NotifyEmission(rewardAllocation[i].receiver, expectedEmission);
            emit IDistributor.Distributed(
                valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, rewardAllocation[i].receiver, expectedEmission
            );
        }
        // vault receives 4.5 ether
        emit IDistributor.Distributed(
            valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, address(vault), bgtToDefaultRewardAllocation
        );
        distributor.distributeFor(
            DISTRIBUTE_FOR_TIMESTAMP, valData.index, valData.pubkey, valData.proposerIndexProof, valData.pubkeyProof
        );

        assertEq(bgt.allowance(address(distributor), address(vault)), bgtToDefaultRewardAllocation);
        for (uint256 i; i < rewardAllocation.length; ++i) {
            uint256 expectedEmission = bgtToRewardAllocation * rewardAllocation[i].percentageNumerator / 10_000;
            assertEq(bgt.allowance(address(distributor), rewardAllocation[i].receiver), expectedEmission);
            assertEq(dedicatedEmissionStreamManager.debt(rewardAllocation[i].receiver), expectedEmission);
        }
    }

    function test_DistributeWithDedicatedEmissionStream_StopDistributing() public {
        helper_SetDefaultRewardAllocation();
        // Percentage 10%
        // Emission target 0.25 ether for each vault
        // This will stop distributing to the reward allocation vaults after the first distribution.
        _helper_setUpRewardAllocation(1000, 0.25 ether);

        IRewardAllocation.Weight[] memory rewardAllocation = dedicatedEmissionStreamManager.getRewardAllocation();

        uint256 bgtToRewardAllocation = TEST_BGT_PER_BLOCK * 1000 / 10_000; // 0.5 ether
        uint256 bgtToDefaultRewardAllocation = TEST_BGT_PER_BLOCK - bgtToRewardAllocation; // 4.5 ether

        for (uint8 i; i < 2; ++i) {
            if (i == 0) {
                vm.expectEmit(true, true, true, true);
                // expect events for notifying the emission and distributing the rewards to the reward
                // allocation vaults
                for (uint8 j; j < rewardAllocation.length; ++j) {
                    uint256 expectedEmission = bgtToRewardAllocation * rewardAllocation[j].percentageNumerator / 10_000;
                    emit IDedicatedEmissionStreamManager.NotifyEmission(rewardAllocation[j].receiver, expectedEmission);
                    emit IDistributor.Distributed(
                        valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, rewardAllocation[j].receiver, expectedEmission
                    );
                }
                // vault receives 4.5 ether
                emit IDistributor.Distributed(
                    valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, address(vault), bgtToDefaultRewardAllocation
                );
            } else {
                vm.expectEmit(true, true, true, true);
                // vault receives 4.5 ether
                emit IDistributor.Distributed(
                    valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP + i, address(vault), TEST_BGT_PER_BLOCK
                );
            }

            distributor.distributeFor(
                DISTRIBUTE_FOR_TIMESTAMP + i,
                valData.index,
                valData.pubkey,
                valData.proposerIndexProof,
                valData.pubkeyProof
            );
        }

        assertEq(
            bgt.allowance(address(distributor), address(vault)), bgtToDefaultRewardAllocation + TEST_BGT_PER_BLOCK
        );
        for (uint256 i; i < rewardAllocation.length; ++i) {
            assertEq(bgt.allowance(address(distributor), rewardAllocation[i].receiver), 0.25 ether);
            assertEq(dedicatedEmissionStreamManager.debt(rewardAllocation[i].receiver), 0.25 ether);
        }
    }

    function test_DistributeWithDedicatedEmissionStream_StopDistributing_DifferentTargetEmissions() public {
        helper_SetDefaultRewardAllocation();

        vm.startPrank(allocationManager);
        dedicatedEmissionStreamManager.setEmissionPerc(1000); // 10%
        dedicatedEmissionStreamManager.setRewardAllocation(_helper_getWeights());
        dedicatedEmissionStreamManager.setTargetEmission(graVault1, 0.25 ether);
        dedicatedEmissionStreamManager.setTargetEmission(graVault2, 0.5 ether);
        vm.stopPrank();

        uint256 bgtToRewardAllocation = TEST_BGT_PER_BLOCK * 1000 / 10_000; // 0.5 ether
        uint256 bgtToDefaultRewardAllocation = TEST_BGT_PER_BLOCK - bgtToRewardAllocation; // 4.5 ether

        // 1st distribution
        // -- graVault1 -> 0.25 ether
        // -- graVault2 -> 0.25 ether
        // -- vault -> 4.5 ether

        // 2nd distribution
        // -- graVault1 -> 0
        // -- graVault2 -> 0.25 ether
        // -- vault -> 4.75 ether

        // 3rd distribution
        // -- graVault1 -> 0
        // -- graVault2 -> 0
        // -- vault -> 5 ether
        for (uint8 i; i < 3; ++i) {
            distributor.distributeFor(
                DISTRIBUTE_FOR_TIMESTAMP + i,
                valData.index,
                valData.pubkey,
                valData.proposerIndexProof,
                valData.pubkeyProof
            );
        }

        assertEq(
            bgt.allowance(address(distributor), address(vault)),
            bgtToDefaultRewardAllocation * 2 + 0.25 ether + TEST_BGT_PER_BLOCK
        );
        assertEq(bgt.allowance(address(distributor), graVault1), 0.25 ether);
        assertEq(bgt.allowance(address(distributor), graVault2), 0.5 ether);
        assertEq(dedicatedEmissionStreamManager.debt(graVault1), 0.25 ether);
        assertEq(dedicatedEmissionStreamManager.debt(graVault2), 0.5 ether);
    }

    function test_DistributeWithDedicatedEmissionStream_RestartDistributing() public {
        test_DistributeWithDedicatedEmissionStream_StopDistributing_DifferentTargetEmissions();

        // Increase the target emission for the vaults after the first target was reached.
        vm.startPrank(allocationManager);
        dedicatedEmissionStreamManager.setTargetEmission(graVault1, 0.5 ether); // 0.25 ether -> 0.5 ether
        dedicatedEmissionStreamManager.setTargetEmission(graVault2, 0.75 ether); // 0.5 ether -> 0.75 ether
        vm.stopPrank();

        uint256 graVault1PreviousDebt = dedicatedEmissionStreamManager.debt(graVault1); // 0.25 ether
        uint256 graVault2PreviousDebt = dedicatedEmissionStreamManager.debt(graVault2); // 0.5 ether
        uint256 vaultPreviousAllowance = bgt.allowance(address(distributor), address(vault)); // 14.25 ether

        // Distribute again
        // -- graVault1 -> 0.25 ether
        // -- graVault2 -> 0.25 ether
        // -- vault -> 4.5 ether
        distributor.distributeFor(
            DISTRIBUTE_FOR_TIMESTAMP + 3,
            valData.index,
            valData.pubkey,
            valData.proposerIndexProof,
            valData.pubkeyProof
        );

        assertEq(bgt.allowance(address(distributor), address(vault)), vaultPreviousAllowance + 4.5 ether);
        assertEq(bgt.allowance(address(distributor), graVault1), graVault1PreviousDebt + 0.25 ether);
        assertEq(bgt.allowance(address(distributor), graVault2), graVault2PreviousDebt + 0.25 ether);
        assertEq(dedicatedEmissionStreamManager.debt(graVault1), graVault1PreviousDebt + 0.25 ether);
        assertEq(dedicatedEmissionStreamManager.debt(graVault2), graVault2PreviousDebt + 0.25 ether);
    }

    function test_DistributeWithDedicatedEmissionStream_OneHundredPercent() public {
        helper_SetDefaultRewardAllocation();
        // Percentage 100%
        // Emission target 10_000 ether for each vault
        _helper_setUpRewardAllocation(10_000, 10_000 ether);

        // expect no call to notifyRewardAmount for the vault
        vm.expectCall(
            address(vault), abi.encodeWithSelector(IRewardVault.notifyRewardAmount.selector, valData.pubkey, 0), 0
        );
        distributor.distributeFor(
            DISTRIBUTE_FOR_TIMESTAMP, valData.index, valData.pubkey, valData.proposerIndexProof, valData.pubkeyProof
        );

        assertEq(bgt.allowance(address(distributor), address(vault)), 0);
        assertEq(bgt.allowance(address(distributor), graVault1), TEST_BGT_PER_BLOCK / 2);
        assertEq(bgt.allowance(address(distributor), graVault2), TEST_BGT_PER_BLOCK / 2);
        assertEq(dedicatedEmissionStreamManager.debt(graVault1), TEST_BGT_PER_BLOCK / 2);
        assertEq(dedicatedEmissionStreamManager.debt(graVault2), TEST_BGT_PER_BLOCK / 2);
    }

    /// @dev target emission will be the same for all vaults
    function _helper_setUpRewardAllocation(uint96 emissionPerc, uint256 targetEmission) internal {
        IRewardAllocation.Weight[] memory newRewardAllocation = _helper_getWeights();
        vm.startPrank(allocationManager);
        dedicatedEmissionStreamManager.setEmissionPerc(emissionPerc); // 10%
        dedicatedEmissionStreamManager.setRewardAllocation(newRewardAllocation);
        for (uint256 i; i < newRewardAllocation.length; ++i) {
            dedicatedEmissionStreamManager.setTargetEmission(newRewardAllocation[i].receiver, targetEmission);
        }
        vm.stopPrank();
    }
}
