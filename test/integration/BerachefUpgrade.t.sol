// // SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { IPOLErrors } from "src/pol/interfaces/IPOLErrors.sol";
import { IBeraChef } from "src/pol/interfaces/IBeraChef.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { BeraChef } from "src/pol/rewards/BeraChef.sol";

import { POLAddressBook } from "script/pol/POLAddresses.sol";
import { ChainType } from "script/base/Chain.sol";

contract BeraChefUpgradeTest is Create2Deployer, Test, POLAddressBook {
    address safeOwner = 0xD13948F99525FB271809F45c268D72a3C00a568D;
    // pubkey of Infrared by Stakelab which has 100% of commission rate
    bytes pubkey =
        hex"88be126bfda4eee190e6c01a224272ed706424851e203791c7279aeecb6b503059901db35b1821f1efe4e6b445f5cc9f";

    uint256 forkBlock = 6_951_320;

    // operator of  Infrared by Stakelab validator
    address operator = 0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126;

    constructor() POLAddressBook(ChainType.Mainnet) { }

    function setUp() public virtual {
        vm.createSelectFork("berachain");
        vm.rollFork(forkBlock);
    }

    function test_Fork() public view {
        assertEq(block.chainid, 80_094);
        assertEq(block.number, forkBlock);
        assertEq(block.timestamp, 1_751_017_666);
    }

    function test_Upgrade() public {
        // deploy the new implementation of BeraChef
        address newBeraChefImpl = deployWithCreate2(0, type(BeraChef).creationCode);

        // upgrade the BeraChef implementation
        vm.prank(safeOwner);
        BeraChef(_polAddresses.beraChef).upgradeToAndCall(newBeraChefImpl, bytes(""));

        // check if there is the MAX_COMMISSION_RATE constant
        uint256 maxCommissionRate = BeraChef(_polAddresses.beraChef).MAX_COMMISSION_RATE();
        assertEq(maxCommissionRate, 0.2e4); // 20% commission rate
    }

    function test_CommissionRate_PostUpdate() public {
        // check if commission rate of validator is 100% before the upgrade
        uint96 commissionRate = BeraChef(_polAddresses.beraChef).getValCommissionOnIncentiveTokens(pubkey);
        assertEq(commissionRate, 1e4); // 100% commission

        // upgrade the BeraChef implementation
        // check if MAX_COMMISSION_RATE constant is set to 20% after the upgrade
        // has been done in the test_Upgrade function
        test_Upgrade();

        uint96 maxCommissionRate = 0.2e4; // 20% commission rate

        // commission rate should automatically be set to 20% after the upgrade
        commissionRate = BeraChef(_polAddresses.beraChef).getValCommissionOnIncentiveTokens(pubkey);
        assertEq(commissionRate, maxCommissionRate); // 20% commission

        // try to queue a commission change higher than 20%
        uint96 newCommissionRate = maxCommissionRate + 0.1e4; // 30% commission
        // expect revert with InvalidCommissionValue error
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(IPOLErrors.InvalidCommissionValue.selector, newCommissionRate, maxCommissionRate)
        );
        BeraChef(_polAddresses.beraChef).queueValCommission(pubkey, newCommissionRate);

        // try to queue a commission change lower than 20%
        newCommissionRate = maxCommissionRate - 0.1e4; // 10% commission

        // it should succeed
        vm.prank(operator);
        BeraChef(_polAddresses.beraChef).queueValCommission(pubkey, newCommissionRate);

        // check the queued commission
        BeraChef.QueuedCommissionRateChange memory queuedCommission =
            BeraChef(_polAddresses.beraChef).getValQueuedCommissionOnIncentiveTokens(pubkey);
        assertEq(queuedCommission.commissionRate, newCommissionRate);
        assertEq(queuedCommission.blockNumberLast, block.number);

        vm.roll(vm.getBlockNumber() + (2 * 8191));
        vm.expectEmit(true, true, true, true);
        // 20% (maxCommissionRate) is the old commission rate after the upgrade
        emit IBeraChef.ValCommissionSet(pubkey, maxCommissionRate, newCommissionRate);
        BeraChef(_polAddresses.beraChef).activateQueuedValCommission(pubkey);
        // check the new commission
        assertEq(BeraChef(_polAddresses.beraChef).getValCommissionOnIncentiveTokens(pubkey), newCommissionRate);
    }
}
