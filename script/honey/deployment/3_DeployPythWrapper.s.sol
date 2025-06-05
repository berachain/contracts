// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import {
    HONEY_ADDRESS,
    HONEY_FACTORY_ADDRESS,
    HONEY_FACTORY_READER_ADDRESS,
    HONEY_FACTORY_PYTH_WRAPPER_ADDRESS
} from "../HoneyAddresses.sol";
import { EXT_PYTH_ADDRESS } from "../../oracles/OraclesAddresses.sol";
import { HONEY_FACTORY_PYTH_WRAPPER_SALT } from "../HoneySalts.sol";

import { HoneyFactoryPythWrapper } from "src/honey/HoneyFactoryPythWrapper.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";

contract DeployPythWrapperScript is Create2Deployer, BaseScript {
    function run() public virtual broadcast {
        deployHoneyFactoryPythWrapper();
    }

    function deployHoneyFactoryPythWrapper() internal {
        console2.log("Deploying Honey factory Pyth wrapper...");

        _validateCode("HoneyFactory", HONEY_FACTORY_ADDRESS);
        _validateCode("HoneyFactoryReader", HONEY_FACTORY_READER_ADDRESS);
        _validateCode("Pyth", EXT_PYTH_ADDRESS);

        HoneyFactoryPythWrapper wrapper = HoneyFactoryPythWrapper(
            deployWithCreate2WithArgs(
                HONEY_FACTORY_PYTH_WRAPPER_SALT,
                type(HoneyFactoryPythWrapper).creationCode,
                abi.encode(HONEY_FACTORY_ADDRESS, EXT_PYTH_ADDRESS, HONEY_FACTORY_READER_ADDRESS)
            )
        );
        _checkDeploymentAddress("HoneyFactoryPythWrapper", address(wrapper), HONEY_FACTORY_PYTH_WRAPPER_ADDRESS);

        require(wrapper.honey() == HONEY_ADDRESS, "Honey address mismatch");
        require(wrapper.factory() == HONEY_FACTORY_ADDRESS, "HoneyFactory address mismatch");
        require(wrapper.pyth() == EXT_PYTH_ADDRESS, "Pyth address mismatch");
        require(wrapper.factoryReader() == HONEY_FACTORY_READER_ADDRESS, "HoneyFactoryReader address mismatch");
    }
}
