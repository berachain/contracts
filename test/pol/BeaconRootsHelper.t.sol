// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import { IPOLErrors } from "src/pol/interfaces/IPOLErrors.sol";
import { RewardVault } from "src/pol/rewards/RewardVault.sol";
import { BeaconRoots } from "src/libraries/BeaconRoots.sol";

import { MockHoney } from "@mock/honey/MockHoney.sol";
import { Mock4788BeaconRoots } from "@mock/pol/Mock4788BeaconRoots.sol";
import { IRewardAllocation } from "src/pol/interfaces/IRewardAllocation.sol";

import "./POL.t.sol";

/// @dev This test sets up the mock BeaconRoots contract and other infrastructure for POL distribution tests.
/// @dev The permissionless distributeFor(timestamp, proofs...) path was removed post-Pectra11.
/// Only the system-call distributeFor(pubkey) path remains.
abstract contract BeaconRootsHelperTest is POLTest {
    MockHoney internal honey;
    RewardVault internal vault;
    Mock4788BeaconRoots internal mockBeaconRoots;
    bool internal initDefaultRewardAllocation = false;

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual override {
        super.setUp();

        assertEq(address(distributor.beraChef()), address(beraChef));
        assertEq(address(distributor.blockRewardController()), address(blockRewardController));
        assertEq(address(distributor.bgt()), address(bgt));

        // Mock calls to BeaconRoots.ADDRESS to use our mock contract.
        vm.etch(BeaconRoots.ADDRESS, address(new Mock4788BeaconRoots()).code);
        mockBeaconRoots = Mock4788BeaconRoots(BeaconRoots.ADDRESS);
        mockBeaconRoots.setIsTimestampValid(true);
        mockBeaconRoots.setMockBeaconBlockRoot(valData.beaconBlockRoot);

        vm.startPrank(governance);
        // Set the reward rate to be 5 bgt per block.
        blockRewardController.setRewardRate(TEST_BGT_PER_BLOCK);
        // Set the min boosted reward rate to be 5 bgt per block.
        blockRewardController.setMinBoostedRewardRate(TEST_BGT_PER_BLOCK);

        // Allow the distributor to send BGT.
        bgt.whitelistSender(address(distributor), true);

        // Setup the reward allocation and vault for the honey token.
        honey = new MockHoney();
        vault = RewardVault(factory.createRewardVault(address(honey)));
        vm.stopPrank();

        if (initDefaultRewardAllocation) {
            helper_SetDefaultRewardAllocation();
        }
    }

    function helper_SetDefaultRewardAllocation() public virtual {
        // Set up the default reward allocation with weight 1 on the available vault.
        vm.startPrank(governance);
        IRewardAllocation.Weight[] memory weights = new IRewardAllocation.Weight[](1);
        weights[0] = IRewardAllocation.Weight(address(vault), 10_000);
        beraChef.setVaultWhitelistedStatus(address(vault), true, "");
        beraChef.setDefaultRewardAllocation(IRewardAllocation.RewardAllocation(1, weights));
        vm.stopPrank();
    }
}
