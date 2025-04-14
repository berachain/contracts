// // SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";

import { RewardVault } from "src/pol/rewards/RewardVault.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { BGTStaker } from "src/pol/BGTStaker.sol";
import { RewardVaultFactory } from "src/pol/rewards/RewardVaultFactory.sol";
import { MockERC20 } from "../mock/token/MockERC20.sol";

import { REWARD_VAULT_FACTORY_ADDRESS, BGT_STAKER_ADDRESS } from "script/pol/POLAddresses.sol";

contract ReduceRewardDurationTest is Create2Deployer, Test {
    address safeOwner = 0xD13948F99525FB271809F45c268D72a3C00a568D;

    uint256 forkBlock = 2_634_388;

    function setUp() public virtual {
        vm.createSelectFork("berachain");
        vm.rollFork(forkBlock);
    }

    function test_Fork() public view {
        assertEq(block.chainid, 80_094);
        assertEq(block.number, forkBlock);
        assertEq(block.timestamp, 1_742_552_262);
    }

    function test_RewardVaultUpgrade() public {
        // upgrade the reward vault
        address newRewardVaultImpl = deployWithCreate2(0, type(RewardVault).creationCode);
        address beacon = RewardVaultFactory(REWARD_VAULT_FACTORY_ADDRESS).beacon();
        vm.prank(safeOwner);
        UpgradeableBeacon(beacon).upgradeTo(newRewardVaultImpl);

        // create a new reward vault
        address stakingToken = address(new MockERC20());
        MockERC20(stakingToken).initialize("StakingToken", "ST");
        address rewardVault = RewardVaultFactory(REWARD_VAULT_FACTORY_ADDRESS).createRewardVault(stakingToken);

        // new reward duration is 3 days
        assertEq(RewardVault(rewardVault).rewardsDuration(), 3 days);
    }

    function test_RewardDurationChangeOnBGTStaker() public {
        vm.prank(safeOwner);
        BGTStaker(BGT_STAKER_ADDRESS).setRewardsDuration(3 days);
        assertEq(BGTStaker(BGT_STAKER_ADDRESS).rewardsDuration(), 3 days);
    }

    function test_RewardDurationChangeOnExistingVaults() public {
        // get total vaults
        uint256 totalVaults = RewardVaultFactory(REWARD_VAULT_FACTORY_ADDRESS).allVaultsLength();

        // upgrade first 10 vault or totalVaults whichever is less
        // doing less number in test to avoid rpc timeout in case of large number of vaults.
        uint256 vaultsCountToUpgrade = totalVaults < 10 ? totalVaults : 10;
        for (uint256 i = 0; i < vaultsCountToUpgrade; i++) {
            address vault = RewardVaultFactory(REWARD_VAULT_FACTORY_ADDRESS).allVaults(i);
            uint256 rewardDuration = RewardVault(vault).rewardsDuration();
            // current reward duration is 7 days
            assertEq(rewardDuration, 7 days);

            vm.prank(safeOwner);
            RewardVault(vault).setRewardsDuration(3 days);
            rewardDuration = RewardVault(vault).rewardsDuration();
            // new reward duration is 3 days
            assertEq(rewardDuration, 3 days);
        }
    }
}
