// // SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { BUSDFactory } from "src/busd/BUSDFactory.sol";

import { BUSDAddressBook } from "script/busd/BUSDAddresses.sol";
import { ChainType } from "script/base/Chain.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IBUSDFactory } from "src/busd/BUSDFactory.sol";

interface IBUSDFactoryOld {
    function honey() external view returns (address);
}

/// @title BUSDFactory_ReName_Upgrade
contract BUSDFactory_ReName_Upgrade is Create2Deployer, Test, BUSDAddressBook {
    address safeOwner = 0xD13948F99525FB271809F45c268D72a3C00a568D;
    address usdc = 0x549943e04f40284185054145c6E4e9568C1D3241;
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

    // Factory earlier honey function has been renamed to busd.
    function test_FunctionNameChange() public {
        BUSDFactory factory = BUSDFactory(_busdAddresses.busdFactory);
        address oldFunctionAddress = address(IBUSDFactoryOld(address(factory)).honey());
        // upgrade
        upgrade();
        assertEq(address(factory.busd()), oldFunctionAddress);
    }

    function test_MintEventRename() public {
        BUSDFactory factory = BUSDFactory(_busdAddresses.busdFactory);
        // upgrade
        upgrade();
        vm.startPrank(safeOwner);
        IERC20(usdc).approve(address(factory), type(uint256).max);
        uint256 assetAmount = 100;
        uint256 assetAmountPostDecimalNormalization = assetAmount * 1e12;
        uint256 mintAmount = (assetAmountPostDecimalNormalization * factory.mintRates(usdc)) / 1e18;
        vm.expectEmit(true, true, true, true);
        emit IBUSDFactory.BUSDMinted(safeOwner, safeOwner, usdc, assetAmount, mintAmount);
        factory.mint(usdc, assetAmount, safeOwner, false);
        vm.stopPrank();
    }

    function test_RedeemEventRename() public {
        BUSDFactory factory = BUSDFactory(_busdAddresses.busdFactory);
        // upgrade
        upgrade();
        vm.startPrank(safeOwner);
        IERC20(address(_busdAddresses.busd)).approve(address(factory), type(uint256).max);
        uint256 busdRedeemAmount = 1e14;
        uint256 busdRedeemAmountPostDecimalNormalization = busdRedeemAmount / 1e12; // redeem for USDC
        uint256 redeemAssetAmount = (busdRedeemAmountPostDecimalNormalization * factory.redeemRates(usdc)) / 1e18;
        vm.expectEmit(true, true, true, true);
        emit IBUSDFactory.BUSDRedeemed(safeOwner, safeOwner, usdc, redeemAssetAmount, busdRedeemAmount);
        factory.redeem(usdc, busdRedeemAmount, safeOwner, false);
        vm.stopPrank();
    }

    function upgrade() internal {
        BUSDFactory factory = BUSDFactory(_busdAddresses.busdFactory);
        // deploy new implementation
        address newFactoryImpl = deployWithCreate2(0, type(BUSDFactory).creationCode);

        vm.prank(safeOwner);
        factory.upgradeToAndCall(newFactoryImpl, "");
    }
}
