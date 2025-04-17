// // SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { ERC20 } from "solady/src/tokens/ERC20.sol";
import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";

import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { HoneyFactory } from "src/honey/HoneyFactory.sol";
import { CollateralVault } from "src/honey/CollateralVault.sol";

import { HONEY_FACTORY_ADDRESS } from "script/honey/HoneyAddresses.sol";

/// @title HoneyCollateralVaultCustodyUpgrade
contract HoneyCollateralVaultCustodyUpgrade is Create2Deployer, Test {
    address safeOwner = 0xD13948F99525FB271809F45c268D72a3C00a568D;
    address usdc = 0x549943e04f40284185054145c6E4e9568C1D3241;
    address usdcVault = 0x90bc07408f5b5eAc4dE38Af76EA6069e1fcEe363;
    address usdcHolder = 0x65310aBbb93B7f59A1cb628738358607F89BB869; // holds ~1.6M at fork block
    address usdcCustody = 0x3F00Ec0764d8bD9BE594E4560D5f1b4D6E07E349;
    uint256 forkBlock = 3_161_514;

    function setUp() public virtual {
        vm.createSelectFork("berachain");
        vm.rollFork(forkBlock);
    }

    function test_Fork() public view {
        assertEq(block.chainid, 80_094);
        assertEq(block.number, forkBlock);
        assertEq(block.timestamp, 1_743_586_908);
    }

    function test_Upgrade() public {
        // deploy new implementations
        address newHoneyFactoryImpl = deployWithCreate2(0, type(HoneyFactory).creationCode);
        address newCollateralVaultImpl = deployWithCreate2(0, type(CollateralVault).creationCode);

        vm.startPrank(safeOwner);
        HoneyFactory(HONEY_FACTORY_ADDRESS).upgradeToAndCall(newHoneyFactoryImpl, "");
        address beacon = HoneyFactory(HONEY_FACTORY_ADDRESS).beacon();
        UpgradeableBeacon(beacon).upgradeTo(newCollateralVaultImpl);
        vm.stopPrank();

        // balance of USDC in usdcVault before setting custody info
        uint256 usdcBalance = ERC20(usdc).balanceOf(address(usdcVault));

        // post upgrade we should be able to set the custody info
        vm.prank(usdcCustody);
        ERC20(usdc).approve(usdcVault, type(uint256).max);

        vm.prank(safeOwner);
        HoneyFactory(HONEY_FACTORY_ADDRESS).setCustodyInfo(usdc, true, usdcCustody);
        // post setting custody info, the balance of USDC in usdcVault should move to custody
        assertEq(ERC20(usdc).balanceOf(address(usdcVault)), 0);
        assertEq(ERC20(usdc).balanceOf(usdcCustody), usdcBalance);

        // verify that the custody info is set correctly
        (bool isCustody, address custodyAddress) = CollateralVault(usdcVault).custodyInfo();
        assertEq(isCustody, true);
        assertEq(custodyAddress, usdcCustody);
        vm.stopPrank();

        // test mint and redeem flow
        vm.startPrank(usdcHolder);
        // approve 100 USDC
        ERC20(usdc).approve(HONEY_FACTORY_ADDRESS, 100e6);
        HoneyFactory(HONEY_FACTORY_ADDRESS).mint(usdc, 10e6, usdcHolder, false);
        // given mint rate is 1e18, no fee will be charged
        // custody balance should increase by 10e6 (10 USDC)
        assertEq(ERC20(usdc).balanceOf(usdcCustody), usdcBalance + 10e6);
        assertEq(ERC20(usdc).balanceOf(usdcVault), 0);

        // redeem 5e18 HONEY (5 Honey)
        HoneyFactory(HONEY_FACTORY_ADDRESS).redeem(usdc, 5e18, usdcHolder, false);
        // custody balance should decrease by 5e6 (5 USDC)
        assertEq(ERC20(usdc).balanceOf(usdcCustody), usdcBalance + 5e6);
        assertEq(ERC20(usdc).balanceOf(usdcVault), 0);
        vm.stopPrank();

        // test the removal of custody info
        vm.prank(safeOwner);
        HoneyFactory(HONEY_FACTORY_ADDRESS).setCustodyInfo(usdc, false, usdcCustody);
        // This should move back all the USDC to usdcVault
        assertEq(ERC20(usdc).balanceOf(usdcCustody), 0);
        assertEq(ERC20(usdc).balanceOf(usdcVault), usdcBalance + 5e6);
        // verify that the custody info is removed correctly
        (isCustody, custodyAddress) = CollateralVault(usdcVault).custodyInfo();
        assertEq(isCustody, false);
        assertEq(custodyAddress, address(0));

        // test deposit post removal of custody info
        vm.startPrank(usdcHolder);
        HoneyFactory(HONEY_FACTORY_ADDRESS).mint(usdc, 10e6, usdcHolder, false);
        assertEq(ERC20(usdc).balanceOf(usdcVault), usdcBalance + 15e6);

        // test redeem post removal of custody info
        // redeem all the minted HONEY of usdcHolder
        HoneyFactory(HONEY_FACTORY_ADDRESS).redeem(usdc, 15e18, usdcHolder, false);
        assertEq(ERC20(usdc).balanceOf(usdcVault), usdcBalance);
    }
}
