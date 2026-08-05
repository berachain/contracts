// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { IBUSDErrors } from "src/busd/IBUSDErrors.sol";
import { BUSD } from "src/busd/BUSD.sol";
import { BUSDDeployer } from "src/busd/BUSDDeployer.sol";
import { BUSDFactory } from "src/busd/BUSDFactory.sol";
import { BUSDFactoryReader } from "src/busd/BUSDFactoryReader.sol";
import { MockOracle } from "@mock/oracle/MockOracle.sol";
import { Salt } from "src/base/Salt.sol";

contract BUSDDeployerTest is Test {
    address private immutable GOVERNANCE = makeAddr("governance");
    address private immutable FEE_RECEIVER = makeAddr("feeReceiver");
    address private immutable POL_FEE_COLLECTOR = makeAddr("polFeeCollector");

    MockOracle oracle = new MockOracle();

    Salt internal _busdSalt = Salt({ implementation: 0, proxy: 0 });
    Salt internal _busdFactorySalt = Salt({ implementation: 0, proxy: 1 });
    Salt internal _busdFactoryReaderSalt = Salt({ implementation: 0, proxy: 1 });

    function test_BUSDDeployRevertGovernanceIsAddressZero() public {
        vm.expectRevert(abi.encodeWithSelector(IBUSDErrors.ZeroAddress.selector));
        new BUSDDeployer(
            address(0),
            POL_FEE_COLLECTOR,
            FEE_RECEIVER,
            _busdSalt,
            _busdFactorySalt,
            _busdFactoryReaderSalt,
            address(oracle)
        );
    }

    function test_BUSDDeployRevertFeeReceiverIsAddressZero() public {
        vm.expectRevert(abi.encodeWithSelector(IBUSDErrors.ZeroAddress.selector));
        new BUSDDeployer(
            GOVERNANCE,
            address(0),
            POL_FEE_COLLECTOR,
            _busdSalt,
            _busdFactorySalt,
            _busdFactoryReaderSalt,
            address(oracle)
        );
    }

    function test_BUSDDeployRevertPolFeeCollectorIsAddressZero() public {
        vm.expectRevert(abi.encodeWithSelector(IBUSDErrors.ZeroAddress.selector));
        new BUSDDeployer(
            GOVERNANCE, address(0), FEE_RECEIVER, _busdSalt, _busdFactorySalt, _busdFactoryReaderSalt, address(oracle)
        );
    }

    function test_BUSDDeployer() public {
        BUSDDeployer deployer = new BUSDDeployer(
            GOVERNANCE,
            POL_FEE_COLLECTOR,
            FEE_RECEIVER,
            _busdSalt,
            _busdFactorySalt,
            _busdFactoryReaderSalt,
            address(oracle)
        );
        BUSD busd = deployer.busd();
        BUSDFactory factory = deployer.busdFactory();
        BUSDFactoryReader factoryReader = deployer.busdFactoryReader();

        assertEq(busd.factory(), address(factory));
        assertTrue(busd.hasRole(factory.DEFAULT_ADMIN_ROLE(), GOVERNANCE));

        assertEq(address(factory.busd()), address(busd));
        assertTrue(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), GOVERNANCE));
        assertEq(factory.feeReceiver(), FEE_RECEIVER);
        assertEq(factory.polFeeCollector(), POL_FEE_COLLECTOR);
        assertEq(address(factory), address(factoryReader.busdFactory()));
    }
}
