// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./POLGasSim.t.sol";
import { IRewardAllocation } from "src/pol/interfaces/IRewardAllocation.sol";

contract POLGasSimulationMax is POLGasSimulationSimple {
    function setUp() public override {
        super.setUp();

        // Create reward vaults with consensus assets
        RewardVault[] memory vaults = createVaults(10);

        // configure reward allocation with multiple consensus assets
        uint96[] memory weights = new uint96[](10);
        weights[0] = 1000;
        weights[1] = 1000;
        weights[2] = 1000;
        weights[3] = 1000;
        weights[4] = 1000;
        weights[5] = 1000;
        weights[6] = 1000;
        weights[7] = 1000;
        weights[8] = 1000;
        weights[9] = 1000;

        configureWeights(vaults, weights);

        // whitelist and add validator incentives
        addIncentives(vaults, 2);

        _setupDedicatedEmissionStream(vaults);
    }

    /// @dev Test reward distribution for multiple blocks
    /// @notice 11.75% of Arbitrum block gas limit
    function testGasPOLDistributionCatchUp() public {
        for (uint256 i; i < 10; ++i) {
            validateAndDistribute(proof, signature, abi.encode(valData.pubkey, block.number - 1));
        }
    }

    function _setupDedicatedEmissionStream(RewardVault[] memory vaults) internal {
        assertGe(vaults.length, 5);

        address allocationManager = makeAddr("allocationManager");
        bytes32 allocationManagerRole = dedicatedEmissionStreamManager.ALLOCATION_MANAGER_ROLE();

        vm.startPrank(address(timelock));
        distributor.setDedicatedEmissionStreamManager(address(dedicatedEmissionStreamManager));
        dedicatedEmissionStreamManager.grantRole(allocationManagerRole, allocationManager);
        vm.stopPrank();

        vm.startPrank(allocationManager);
        dedicatedEmissionStreamManager.setEmissionPerc(1000);
        IRewardAllocation.Weight[] memory gesWeights = new IRewardAllocation.Weight[](5);
        gesWeights[0] = IRewardAllocation.Weight(address(vaults[0]), 2000);
        gesWeights[1] = IRewardAllocation.Weight(address(vaults[1]), 2000);
        gesWeights[2] = IRewardAllocation.Weight(address(vaults[2]), 2000);
        gesWeights[3] = IRewardAllocation.Weight(address(vaults[3]), 2000);
        gesWeights[4] = IRewardAllocation.Weight(address(vaults[4]), 2000);
        dedicatedEmissionStreamManager.setRewardAllocation(gesWeights);

        dedicatedEmissionStreamManager.setTargetEmission(address(vaults[0]), 100 ether);
        dedicatedEmissionStreamManager.setTargetEmission(address(vaults[1]), 100 ether);
        dedicatedEmissionStreamManager.setTargetEmission(address(vaults[2]), 100 ether);
        dedicatedEmissionStreamManager.setTargetEmission(address(vaults[3]), 100 ether);
        dedicatedEmissionStreamManager.setTargetEmission(address(vaults[4]), 100 ether);
        vm.stopPrank();
    }
}
