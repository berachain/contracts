// // SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { ERC20 } from "solady/src/tokens/ERC20.sol";
import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";

import { IPOLErrors } from "src/pol/interfaces/IPOLErrors.sol";
import { BeraChef } from "src/pol/rewards/BeraChef.sol";
import { IBeraChef } from "src/pol/interfaces/IBeraChef.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { RewardVault } from "src/pol/rewards/RewardVault.sol";
import { IDistributor } from "src/pol/interfaces/IDistributor.sol";
import { MockHoney } from "../mock/honey/MockHoney.sol";
import { RewardVaultFactory } from "src/pol/rewards/RewardVaultFactory.sol";
import { BGTIncentiveDistributor } from "src/pol/rewards/BGTIncentiveDistributor.sol";
import { BGTIncentiveDistributorDeployer } from "script/pol/logic/BGTIncentiveDistributorDeployer.sol";

import {
    BGT_ADDRESS,
    BERACHEF_ADDRESS,
    DISTRIBUTOR_ADDRESS,
    BEACON_DEPOSIT_ADDRESS,
    REWARD_VAULT_FACTORY_ADDRESS,
    BGT_INCENTIVE_DISTRIBUTOR_ADDRESS
} from "script/pol/POLAddresses.sol";

import { BGT_INCENTIVE_DISTRIBUTOR_SALT } from "script/pol/POLSalts.sol";

/// @title BGTIncentiveDistributorUpgradeTest
contract BGTIncentiveDistributorUpgradeTest is Create2Deployer, BGTIncentiveDistributorDeployer, Test {
    address safeOwner = 0xD13948F99525FB271809F45c268D72a3C00a568D;
    // pubkey of BicroStrategy validator, distribution at block 2286450
    // https://berascan.com/tx/0x16592f3381629cea5ada0b1c6fedf98f92088cbe32430cb6067a0b32aa102610
    bytes pubkey =
        hex"83fd53710b75c2115bd0aac128b739eb9fa9e262603dacdf834030abb1bf4c8a6c00bb72b314c123d77f4ff40cd4d49a";

    uint256 forkBlock = 2_269_800;

    // operator of BicroStrategy validator
    address operator = 0x4595D079A06a9628F8384D7f568A29Cc95a14F1e;

    function setUp() public virtual {
        vm.createSelectFork("berachain");
        vm.rollFork(forkBlock);
    }

    function test_Fork() public view {
        assertEq(block.chainid, 80_094);
        assertEq(block.number, forkBlock);
        assertEq(block.timestamp, 1_741_841_001);
    }

    function test_Upgrade() public {
        // Deploy BGTIncentiveDistributor
        address bgtIncentiveDistributor = deployBGTIncentiveDistributor(safeOwner, BGT_INCENTIVE_DISTRIBUTOR_SALT);
        // should be deployed at the precomputed address
        // This check will only pass if code compiled with deploy profile,
        //commenting it as CI does not compile with deploy profile.
        // assertEq(bgtIncentiveDistributor, BGT_INCENTIVE_DISTRIBUTOR_ADDRESS);

        // deploy the new implementations
        address newBeraChefImpl = deployWithCreate2(0, type(BeraChef).creationCode);
        address newRewardVaultImpl = deployWithCreate2(0, type(RewardVault).creationCode);
        address newRewardVaultFactoryImpl = deployWithCreate2(0, type(RewardVaultFactory).creationCode);

        // upgrade the contracts
        vm.startPrank(safeOwner);
        BeraChef(BERACHEF_ADDRESS).upgradeToAndCall(
            newBeraChefImpl, abi.encodeCall(BeraChef.setCommissionChangeDelay, 2 * 8191)
        );
        assertEq(BeraChef(BERACHEF_ADDRESS).commissionChangeDelay(), 2 * 8191);

        // make sure no storage collision
        assertEq(BeraChef(BERACHEF_ADDRESS).distributor(), DISTRIBUTOR_ADDRESS);
        assertEq(BeraChef(BERACHEF_ADDRESS).factory(), REWARD_VAULT_FACTORY_ADDRESS);

        RewardVaultFactory(REWARD_VAULT_FACTORY_ADDRESS).upgradeToAndCall(
            newRewardVaultFactoryImpl,
            abi.encodeCall(RewardVaultFactory.setBGTIncentiveDistributor, bgtIncentiveDistributor)
        );
        assertEq(RewardVaultFactory(REWARD_VAULT_FACTORY_ADDRESS).bgtIncentiveDistributor(), bgtIncentiveDistributor);

        // make sure no storage collision
        assertEq(RewardVaultFactory(REWARD_VAULT_FACTORY_ADDRESS).bgt(), BGT_ADDRESS);
        assertEq(RewardVaultFactory(REWARD_VAULT_FACTORY_ADDRESS).distributor(), DISTRIBUTOR_ADDRESS);

        // get the beacon from the factory
        address beacon = RewardVaultFactory(REWARD_VAULT_FACTORY_ADDRESS).beacon();
        UpgradeableBeacon(beacon).upgradeTo(newRewardVaultImpl);
        assertEq(UpgradeableBeacon(beacon).implementation(), newRewardVaultImpl);
        vm.stopPrank();

        // deploy a new reward vault to check no storage collision
        address stakingToken = address(new MockHoney());
        address mockRewardVault = RewardVaultFactory(REWARD_VAULT_FACTORY_ADDRESS).createRewardVault(stakingToken);
        assertEq(RewardVault(mockRewardVault).distributor(), DISTRIBUTOR_ADDRESS);
        assertEq(address(RewardVault(mockRewardVault).beaconDepositContract()), BEACON_DEPOSIT_ADDRESS);

        // test default commission post upgrade
        assertEq(BeraChef(BERACHEF_ADDRESS).getValCommissionOnIncentiveTokens(pubkey), 0.05e4);
    }

    function test_CommissionChange_PostUpgrade() public {
        test_Upgrade();
        vm.prank(operator);
        // queue new commission rate of 1 wei
        BeraChef(BERACHEF_ADDRESS).queueValCommission(pubkey, 1);

        // check the queued commission
        BeraChef.QueuedCommissionRateChange memory queuedCommission =
            BeraChef(BERACHEF_ADDRESS).getValQueuedCommissionOnIncentiveTokens(pubkey);
        assertEq(queuedCommission.commissionRate, 1);
        assertEq(queuedCommission.blockNumberLast, block.number);

        // will revert if try to activate the queue before the delay
        vm.expectRevert(IPOLErrors.CommissionNotQueuedOrDelayNotPassed.selector);
        BeraChef(BERACHEF_ADDRESS).activateQueuedValCommission(pubkey);

        vm.roll(forkBlock + (2 * 8191));
        vm.expectEmit(true, true, true, true);
        emit IBeraChef.ValCommissionSet(pubkey, 0.05e4, 1);
        BeraChef(BERACHEF_ADDRESS).activateQueuedValCommission(pubkey);
        // check the new commission
        assertEq(BeraChef(BERACHEF_ADDRESS).getValCommissionOnIncentiveTokens(pubkey), 1);

        vm.prank(operator);
        // queue new commission rate of 100%
        BeraChef(BERACHEF_ADDRESS).queueValCommission(pubkey, 1e4);

        // check the queued commission
        queuedCommission = BeraChef(BERACHEF_ADDRESS).getValQueuedCommissionOnIncentiveTokens(pubkey);
        assertEq(queuedCommission.commissionRate, 1e4);
        assertEq(queuedCommission.blockNumberLast, block.number);

        // will revert if try to activate the queue before the delay
        vm.expectRevert(IPOLErrors.CommissionNotQueuedOrDelayNotPassed.selector);
        BeraChef(BERACHEF_ADDRESS).activateQueuedValCommission(pubkey);

        vm.roll(vm.getBlockNumber() + (2 * 8191));
        vm.expectEmit(true, true, true, true);
        emit IBeraChef.ValCommissionSet(pubkey, 1, 1e4);
        BeraChef(BERACHEF_ADDRESS).activateQueuedValCommission(pubkey);
        // check the new commission
        assertEq(BeraChef(BERACHEF_ADDRESS).getValCommissionOnIncentiveTokens(pubkey), 1e4);

        // new 0 commission rate
        vm.prank(operator);
        BeraChef(BERACHEF_ADDRESS).queueValCommission(pubkey, 0);
        vm.roll(vm.getBlockNumber() + (2 * 8191));
        vm.expectEmit(true, true, true, true);
        emit IBeraChef.ValCommissionSet(pubkey, 1e4, 0);
        BeraChef(BERACHEF_ADDRESS).activateQueuedValCommission(pubkey);
        // should allow to set commission to 0.
        // default 5% commission applies only if no custom commission has been set.
        assertEq(BeraChef(BERACHEF_ADDRESS).getValCommissionOnIncentiveTokens(pubkey), 0);

        // activate commission change revert if not queued
        vm.expectRevert(IPOLErrors.CommissionNotQueuedOrDelayNotPassed.selector);
        BeraChef(BERACHEF_ADDRESS).activateQueuedValCommission(pubkey);
    }
}
