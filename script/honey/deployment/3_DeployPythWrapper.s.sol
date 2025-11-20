// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseDeployScript } from "../../base/BaseDeploy.s.sol";
import { AddressBook } from "../../base/AddressBook.sol";
import { HoneyFactoryPythWrapper } from "src/honey/HoneyFactoryPythWrapper.sol";

contract DeployPythWrapperScript is BaseDeployScript, AddressBook {
    constructor() AddressBook(_chainType) { }

    function run() public virtual broadcast {
        deployHoneyFactoryPythWrapper();
    }

    function deployHoneyFactoryPythWrapper() internal {
        console2.log("Deploying Honey factory Pyth wrapper...");

        _validateCode("HoneyFactory", _honeyAddresses.honeyFactory);
        _validateCode("HoneyFactoryReader", _honeyAddresses.honeyFactoryReader);
        _validateCode("Pyth", _oraclesAddresses.extPyth);

        HoneyFactoryPythWrapper wrapper = HoneyFactoryPythWrapper(
            _deployWithArgs(
                "HoneyFactoryPythWrapper",
                type(HoneyFactoryPythWrapper).creationCode,
                abi.encode(_honeyAddresses.honeyFactory, _oraclesAddresses.extPyth, _honeyAddresses.honeyFactoryReader),
                _honeyAddresses.honeyFactoryPythWrapper
            )
        );

        require(wrapper.honey() == _honeyAddresses.honey, "Honey address mismatch");
        require(wrapper.factory() == _honeyAddresses.honeyFactory, "HoneyFactory address mismatch");
        require(wrapper.pyth() == _oraclesAddresses.extPyth, "Pyth address mismatch");
        require(wrapper.factoryReader() == _honeyAddresses.honeyFactoryReader, "HoneyFactoryReader address mismatch");
    }
}
