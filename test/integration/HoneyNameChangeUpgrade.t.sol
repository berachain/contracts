// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { Honey } from "src/honey/Honey.sol";

import { HoneyAddressBook } from "script/honey/HoneyAddresses.sol";
import { ChainType } from "script/base/Chain.sol";

/// @title HoneyNameChangeUpgrade
contract HoneyNameChangeUpgrade is Create2Deployer, Test, HoneyAddressBook {
    address safeOwner = 0xD13948F99525FB271809F45c268D72a3C00a568D;
    uint256 forkBlock = 24_503_087;
    uint256 forkTimestamp = 1_786_020_890;

    constructor() HoneyAddressBook(ChainType.Mainnet) { }

    function setUp() public virtual {
        vm.createSelectFork("berachain");
        vm.rollFork(forkBlock);
    }

    function test_Fork() public view {
        assertEq(block.chainid, 80_094);
        assertEq(block.number, forkBlock);
        assertEq(block.timestamp, forkTimestamp);
    }

    function test_NameChange() public {
        Honey honey = Honey(_honeyAddresses.honey);
        assertEq(honey.name(), "Honey");
        assertEq(honey.symbol(), "HONEY");
        upgrade();
        assertEq(honey.name(), "Bera USD");
        assertEq(honey.symbol(), "BUSD");
    }

    function upgrade() internal {
        address newHoneyImpl = deployWithCreate2(0, type(Honey).creationCode);
        Honey honey = Honey(_honeyAddresses.honey);

        vm.prank(safeOwner);
        honey.upgradeToAndCall(newHoneyImpl, "");
    }
}
