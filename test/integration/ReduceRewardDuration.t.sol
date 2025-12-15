// // SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";

import { RewardVault } from "src/pol/rewards/RewardVault.sol";
import { RewardVault_V6 } from "src/old_versions/V6_Contracts/RewardVault_V6.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { BGTStaker } from "src/pol/BGTStaker.sol";
import { RewardVaultFactory } from "src/pol/rewards/RewardVaultFactory.sol";
import { MockERC20 } from "../mock/token/MockERC20.sol";
import { IRewardVault, IPOLErrors } from "src/pol/interfaces/IRewardVault.sol";

import { ChainType } from "script/base/Chain.sol";
import { POLAddressBook } from "script/pol/POLAddresses.sol";

contract ReduceRewardDurationTest is Create2Deployer, Test, POLAddressBook {
    address factoryVaultAdmin = 0xD13948F99525FB271809F45c268D72a3C00a568D;
    address factoryVaultManager = 0xD13948F99525FB271809F45c268D72a3C00a568D;

    uint256 forkBlock = 6_635_409;

    // list of vault with rewardDurationManager set
    address[] whitelistedVaults = [
        0x6649Bc987a7c0fB0199c523de1b1b330cd0457A8,
        0x3Be1bE98eFAcA8c1Eb786Cbf38234c84B5052EeB,
        0x1Fe3C13B009eCfCe196E480180Db5f8990FFf5Fe
    ];

    constructor() POLAddressBook(ChainType.Mainnet) { }

    function setUp() public virtual {
        vm.createSelectFork("berachain");
        vm.rollFork(forkBlock);
    }

    function test_Fork() public view {
        assertEq(block.chainid, 80_094);
        assertEq(block.number, forkBlock);
        assertEq(block.timestamp, 1_750_409_028);
    }

    function test_DefaultRewardDurationOnNewVault() public {
        _upgradeVaultImpl();
        // create a new reward vault
        address stakingToken = address(new MockERC20());
        MockERC20(stakingToken).initialize("StakingToken", "ST");
        address rewardVault = RewardVaultFactory(_polAddresses.rewardVaultFactory).createRewardVault(stakingToken);

        // new reward duration is 7 days
        assertEq(RewardVault(rewardVault).rewardsDuration(), 7 days);
    }

    function test_RewardVaultUpgradeOnWhitelistedVaults() public {
        // store the reward duration manager address of these vaults
        address[] memory rewardDurationManagers = new address[](whitelistedVaults.length);
        for (uint256 i = 0; i < whitelistedVaults.length; i++) {
            rewardDurationManagers[i] = RewardVault_V6(whitelistedVaults[i]).rewardDurationManager();
        }
        // upgrade the vault implementation
        _upgradeVaultImpl();
        // verify that rewardVaultManager on such vault is equal to the rewardDurationManager
        for (uint256 i = 0; i < whitelistedVaults.length; i++) {
            assertEq(RewardVault(whitelistedVaults[i]).rewardVaultManager(), rewardDurationManagers[i]);
        }
    }

    function test_TargetRewardsPerSecondChangeOnWhitelistedVaults() public {
        address whitelistedVault = whitelistedVaults[0];
        // get the duration manager of the first vault
        address rewardDurationManager = RewardVault_V6(whitelistedVault).rewardDurationManager();
        // upgrade the vault implementation to be able to set maxRewardsPerSecond
        _upgradeVaultImpl();
        // default target rewards per second is 0
        assertEq(RewardVault(whitelistedVault).targetRewardsPerSecond(), 0);
        assertEq(RewardVault(whitelistedVault).minRewardDurationForTargetRate(), 0);
        vm.prank(rewardDurationManager);
        // set the max rewards per second to 1 BGT per second i.e 1e18 per second and
        // with precision of 18, it becomes 1e36.
        // This should set the min reward duration for target rate to `MIN_REWARD_DURATION` i.e 3 days.
        vm.expectEmit();
        emit IRewardVault.TargetRewardsPerSecondUpdated(1e36, 0);
        emit IRewardVault.MinRewardDurationForTargetRateUpdated(3 days, 0);
        RewardVault(whitelistedVault).setTargetRewardsPerSecond(1e36);
        // verify that the max rewards per second is 1e36
        assertEq(RewardVault(whitelistedVault).targetRewardsPerSecond(), 1e36);
        // verify min reward duration for target rate is set to 3 days
        assertEq(RewardVault(whitelistedVault).minRewardDurationForTargetRate(), 3 days);
    }

    function _upgradeVaultImpl() internal {
        // upgrade the reward vault
        address newRewardVaultImpl = deployWithCreate2(0, type(RewardVault).creationCode);
        address beacon = RewardVaultFactory(_polAddresses.rewardVaultFactory).beacon();
        vm.prank(factoryVaultAdmin);
        UpgradeableBeacon(beacon).upgradeTo(newRewardVaultImpl);
    }
}
