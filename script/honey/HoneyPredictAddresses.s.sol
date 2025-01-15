// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { BasePredictScript, console2 } from "../base/BasePredict.s.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { Honey } from "src/honey/Honey.sol";
import { HoneyFactory } from "src/honey/HoneyFactory.sol";
import { HoneyFactoryReader } from "src/honey/HoneyFactoryReader.sol";
import { HONEY_SALT, HONEY_FACTORY_SALT, HONEY_FACTORY_READER_SALT } from "./HoneySalts.sol";

contract HoneyPredictAddressesScript is BasePredictScript {
    function run() public pure {
        _predictProxyAddress("Honey", type(Honey).creationCode, 0, HONEY_SALT);
        _predictProxyAddress("HoneyFactory", type(HoneyFactory).creationCode, 0, HONEY_FACTORY_SALT);
        _predictProxyAddress("HoneyFactoryReader", type(HoneyFactoryReader).creationCode, 0, HONEY_FACTORY_READER_SALT);
    }
}
