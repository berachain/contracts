// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BasePredictScript, console2 } from "../base/BasePredict.s.sol";
import { PythPriceOracle } from "src/extras/PythPriceOracle.sol";
import { PeggedPriceOracle } from "src/extras/PeggedPriceOracle.sol";
import { RootPriceOracle } from "src/extras/RootPriceOracle.sol";

contract OraclesPredictAddressesScript is BasePredictScript {
    function run() public view {
        console2.log("Price oracles contracts will be deployed at: ");
        _predictProxyAddress("PythPriceOracle", type(PythPriceOracle).creationCode);
        _predictAddress("PeggedPriceOracle", type(PeggedPriceOracle).creationCode);
        _predictAddress("RootPriceOracle", type(RootPriceOracle).creationCode);
    }
}
