// // SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { BUSD } from "src/busd/BUSD.sol";

import { BUSDAddressBook } from "script/busd/BUSDAddresses.sol";
import { ChainType } from "script/base/Chain.sol";

/// @title BUSD_ReName_Upgrade
contract BUSD_ReName_Upgrade is Create2Deployer, Test, BUSDAddressBook {
    address safeOwner = 0xD13948F99525FB271809F45c268D72a3C00a568D;
    uint256 forkBlock = 24_404_408;
    uint256 forkTimestamp = 1_785_823_532;

    constructor() BUSDAddressBook(ChainType.Mainnet) { }

    function setUp() public virtual {
        vm.createSelectFork("berachain");
        vm.rollFork(forkBlock);
    }

    function test_Fork() public view {
        assertEq(block.chainid, 80_094);
        assertEq(block.number, forkBlock);
        assertEq(block.timestamp, forkTimestamp);
    }

    function test_CheckRename() public {
        BUSD busd = BUSD(_busdAddresses.busd);
        assertEq(busd.name(), "Honey");
        assertEq(busd.symbol(), "HONEY");
        upgrade();
        assertEq(busd.name(), "Bera USD");
        assertEq(busd.symbol(), "BUSD");
    }

    function test_UserBalancePostUpgrade() public {
        BUSD busd = BUSD(_busdAddresses.busd);
        uint256 preUpgradeBalance = busd.balanceOf(safeOwner);
        upgrade();
        assertEq(busd.balanceOf(safeOwner), preUpgradeBalance);
    }

    function test_TotalSupplyPostUpgrade() public {
        BUSD busd = BUSD(_busdAddresses.busd);
        uint256 preUpgradeTotalSupply = busd.totalSupply();
        upgrade();
        assertEq(busd.totalSupply(), preUpgradeTotalSupply);
    }

    function test_TransferPostUpgrade() public {
        address dummyUser = makeAddr("dummyUser");
        BUSD busd = BUSD(_busdAddresses.busd);
        uint256 preUpgradeBalance = busd.balanceOf(safeOwner);
        upgrade();
        vm.prank(safeOwner);
        busd.transfer(dummyUser, preUpgradeBalance);
        assertEq(busd.balanceOf(dummyUser), preUpgradeBalance);
        assertEq(busd.balanceOf(safeOwner), 0);
    }

    function upgrade() internal {
        address newBUSDImpl = deployWithCreate2(0, type(BUSD).creationCode);
        BUSD busd = BUSD(_busdAddresses.busd);

        vm.prank(safeOwner);
        busd.upgradeToAndCall(newBUSDImpl, "");
    }
}
