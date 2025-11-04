// // SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { Honey } from "src/honey/Honey.sol";

import { HONEY_ADDRESS } from "script/honey/HoneyAddresses.sol";

/// @title HoneyV0Upgrade
contract HoneyV0Upgrade is Create2Deployer, Test {
    address safeOwner = 0xD13948F99525FB271809F45c268D72a3C00a568D;
    uint256 forkBlock = 12_627_746;
    uint256 forkTimestamp = 1_762_164_265;

    function setUp() public virtual {
        vm.createSelectFork("berachain");
        vm.rollFork(forkBlock);
    }

    function test_Fork() public view {
        assertEq(block.chainid, 80_094);
        assertEq(block.number, forkBlock);
        assertEq(block.timestamp, forkTimestamp);
    }

    function test_Upgrade() public {
        address newHoneyImpl = deployWithCreate2(0, type(Honey).creationCode);
        Honey honey = Honey(HONEY_ADDRESS);

        vm.startPrank(safeOwner);
        honey.upgradeToAndCall(newHoneyImpl, "");
        honey.initializeV1Update();

        assertEq(false, honey.paused());
        assertEq(false, honey.isBlacklistedWallet(safeOwner));

        honey.setPaused(true);
        assertEq(true, honey.paused());
        vm.stopPrank();
    }
}
