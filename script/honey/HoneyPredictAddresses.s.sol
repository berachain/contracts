// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BasePredictScript } from "../base/BasePredict.s.sol";
import { Honey } from "src/honey/Honey.sol";
import { HoneyFactory } from "src/honey/HoneyFactory.sol";
import { CollateralVault } from "src/honey/CollateralVault.sol";
import { HoneyFactoryReader } from "src/honey/HoneyFactoryReader.sol";
import { HoneyFactoryPythWrapper } from "src/honey/HoneyFactoryPythWrapper.sol";
import { AddressBook } from "../base/AddressBook.sol";

contract HoneyPredictAddressesScript is BasePredictScript, AddressBook {
    constructor() AddressBook(_chainType) { }

    function run() public view {
        // Proxies:
        _predictProxyAddress("Honey", type(Honey).creationCode);
        _predictProxyAddress("HoneyFactory", type(HoneyFactory).creationCode);
        _predictProxyAddress("HoneyFactoryReader", type(HoneyFactoryReader).creationCode);

        // Implementations:
        _predictAddress("Honey Implementation", type(Honey).creationCode);
        _predictAddress("HoneyFactory Implementation", type(HoneyFactory).creationCode);
        _predictAddress("CollateralVault Implementation", type(CollateralVault).creationCode);
        _predictAddress("HoneyFactoryReader Implementation", type(HoneyFactoryReader).creationCode);

        // Beware of needed dependencies: re-run with updated hard-coded addresses if needed
        _predictAddressWithArgs(
            "HoneyFactoryPythWrapper",
            type(HoneyFactoryPythWrapper).creationCode,
            abi.encode(_honeyAddresses.honeyFactory, _oraclesAddresses.extPyth, _honeyAddresses.honeyFactoryReader)
        );
    }
}
