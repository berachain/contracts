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
    address factoryVaultAdmin = 0xD13948F99525FB271809F45c268D72a3C00a568D;
    address factoryVaultManager = 0xD13948F99525FB271809F45c268D72a3C00a568D;

    uint256 forkBlock = 4_772_378;

    function setUp() public virtual {
        vm.createSelectFork("berachain");
        vm.rollFork(forkBlock);
    }

    function test_Fork() public view {
        assertEq(block.chainid, 80_094);
        assertEq(block.number, forkBlock);
        assertEq(block.timestamp, 1_746_777_149);
    }

    function test_RewardVaultUpgrade() public {
        _upgradeVaultImpl();
        // create a new reward vault
        address stakingToken = address(new MockERC20());
        MockERC20(stakingToken).initialize("StakingToken", "ST");
        address rewardVault = RewardVaultFactory(REWARD_VAULT_FACTORY_ADDRESS).createRewardVault(stakingToken);

        // new reward duration is 7 days
        assertEq(RewardVault(rewardVault).rewardsDuration(), 7 days);
    }

    function test_RewardDurationChangeOnExistingVaults() public {
        _upgradeVaultImpl();
        // get total vaults
        uint256 totalVaults = RewardVaultFactory(REWARD_VAULT_FACTORY_ADDRESS).allVaultsLength();

        // check the new logic to change reward duration for 10 vault or totalVaults whichever is less
        // doing less number in test to avoid rpc timeout in case of large number of vaults.
        uint256 vaultsCountToUpgrade = totalVaults < 10 ? totalVaults : 10;
        for (uint256 i = 0; i < vaultsCountToUpgrade; i++) {
            address vault = RewardVaultFactory(REWARD_VAULT_FACTORY_ADDRESS).allVaults(i);

            // set the vault reward duration manager to the test contract
            vm.prank(factoryVaultManager);
            RewardVault(vault).setRewardDurationManager(address(this));

            // let the reward duration manager set the new reward duration to 10 days
            vm.prank(address(this));
            RewardVault(vault).setRewardsDuration(4 days);
            uint256 rewardDuration = RewardVault(vault).rewardsDuration();
            assertEq(rewardDuration, 4 days);
            assertEq(RewardVault(vault).rewardDurationManager(), address(this));
            assertEq(RewardVault(vault).lastRewardDurationChangeTimestamp(), block.timestamp);
            assertFalse(RewardVault(vault).isRewardDurationCoolDownPeriodPassed());
        }
    }

    function _upgradeVaultImpl() internal {
        // upgrade the reward vault
        address newRewardVaultImpl = deployWithCreate2(0, type(RewardVault).creationCode);
        address beacon = RewardVaultFactory(REWARD_VAULT_FACTORY_ADDRESS).beacon();
        vm.prank(factoryVaultAdmin);
        UpgradeableBeacon(beacon).upgradeTo(newRewardVaultImpl);
    }
}
