// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BasePredictScript, console2 } from "../base/BasePredict.s.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { Honey } from "src/honey/Honey.sol";
import { HoneyFactory } from "src/honey/HoneyFactory.sol";
import { CollateralVault } from "src/honey/CollateralVault.sol";
import { HoneyFactoryReader } from "src/honey/HoneyFactoryReader.sol";
import { HoneyFactoryPythWrapper } from "src/honey/HoneyFactoryPythWrapper.sol";
import {
    HONEY_SALT,
    HONEY_FACTORY_SALT,
    HONEY_FACTORY_READER_SALT,
    HONEY_FACTORY_PYTH_WRAPPER_SALT
} from "./HoneySalts.sol";
import { HONEY_FACTORY_ADDRESS, HONEY_FACTORY_READER_ADDRESS } from "./HoneyAddresses.sol";
import { EXT_PYTH_ADDRESS } from "../oracles/OraclesAddresses.sol";

contract HoneyPredictAddressesScript is BasePredictScript {
    function run() public pure {
        _predictProxyAddress("Honey", type(Honey).creationCode, 0, HONEY_SALT);
        _predictProxyAddress("HoneyFactory", type(HoneyFactory).creationCode, 0, HONEY_FACTORY_SALT);
        _predictProxyAddress("HoneyFactoryReader", type(HoneyFactoryReader).creationCode, 0, HONEY_FACTORY_READER_SALT);
        // Predict new implementation address for HoneyFactory and Collateral Vault
        _predictAddress("HoneyFactory Implementation", type(HoneyFactory).creationCode, 0);
        _predictAddress("CollateralVault Implementation", type(CollateralVault).creationCode, 0);
        // Beware of needed dependencies: re-run with updated hard-coded addresses if needed:
        _predictAddressWithArgs(
            "HoneyFactoryPythWrapper",
            type(HoneyFactoryPythWrapper).creationCode,
            HONEY_FACTORY_PYTH_WRAPPER_SALT,
            abi.encode(HONEY_FACTORY_ADDRESS, EXT_PYTH_ADDRESS, HONEY_FACTORY_READER_ADDRESS)
        );
        _predictAddress("HoneyFactoryReader Implementation", type(HoneyFactoryReader).creationCode, 0);
    }
}
