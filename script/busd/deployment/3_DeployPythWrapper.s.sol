// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseDeployScript } from "../../base/BaseDeploy.s.sol";
import { AddressBook } from "../../base/AddressBook.sol";
import { BUSDFactoryPythWrapper } from "src/busd/BUSDFactoryPythWrapper.sol";

contract DeployPythWrapperScript is BaseDeployScript, AddressBook {
    function run() public virtual broadcast {
        deployBUSDFactoryPythWrapper();
    }

    function deployBUSDFactoryPythWrapper() internal {
        console2.log("Deploying BUSD factory Pyth wrapper...");

        _validateCode("BUSDFactory", _busdAddresses.busdFactory);
        _validateCode("BUSDFactoryReader", _busdAddresses.busdFactoryReader);
        _validateCode("Pyth", _oraclesAddresses.extPyth);

        BUSDFactoryPythWrapper wrapper = BUSDFactoryPythWrapper(
            _deployWithArgs(
                "BUSDFactoryPythWrapper",
                type(BUSDFactoryPythWrapper).creationCode,
                abi.encode(_busdAddresses.busdFactory, _oraclesAddresses.extPyth, _busdAddresses.busdFactoryReader),
                _busdAddresses.busdFactoryPythWrapper
            )
        );

        require(wrapper.busd() == _busdAddresses.busd, "BUSD address mismatch");
        require(wrapper.factory() == _busdAddresses.busdFactory, "BUSDFactory address mismatch");
        require(wrapper.pyth() == _oraclesAddresses.extPyth, "Pyth address mismatch");
        require(wrapper.factoryReader() == _busdAddresses.busdFactoryReader, "BUSDFactoryReader address mismatch");
    }
}
