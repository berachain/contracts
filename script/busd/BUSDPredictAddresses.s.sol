// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BasePredictScript } from "../base/BasePredict.s.sol";
import { BUSD } from "src/busd/BUSD.sol";
import { BUSDFactory } from "src/busd/BUSDFactory.sol";
import { CollateralVault } from "src/busd/CollateralVault.sol";
import { BUSDFactoryReader } from "src/busd/BUSDFactoryReader.sol";
import { BUSDFactoryPythWrapper } from "src/busd/BUSDFactoryPythWrapper.sol";
import { AddressBook } from "../base/AddressBook.sol";

contract BUSDAddressesScript is BasePredictScript, AddressBook {
    function run() public view {
        // Proxies:
        _predictProxyAddress("BUSD", type(BUSD).creationCode);
        _predictProxyAddress("BUSDFactory", type(BUSDFactory).creationCode);
        _predictProxyAddress("BUSDFactoryReader", type(BUSDFactoryReader).creationCode);

        // Implementations:
        _predictAddress("BUSD Implementation", type(BUSD).creationCode);
        _predictAddress("BUSDFactory Implementation", type(BUSDFactory).creationCode);
        _predictAddress("CollateralVault Implementation", type(CollateralVault).creationCode);
        _predictAddress("BUSDFactoryReader Implementation", type(BUSDFactoryReader).creationCode);

        // Beware of needed dependencies: re-run with updated hard-coded addresses if needed
        _predictAddressWithArgs(
            "BUSDFactoryPythWrapper",
            type(BUSDFactoryPythWrapper).creationCode,
            abi.encode(_busdAddresses.busdFactory, _oraclesAddresses.extPyth, _busdAddresses.busdFactoryReader)
        );
    }
}
