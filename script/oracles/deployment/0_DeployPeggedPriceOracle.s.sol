// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BaseDeployScript } from "../../base/BaseDeploy.s.sol";
import { PeggedPriceOracle } from "src/extras/PeggedPriceOracle.sol";
import { AddressBook } from "../../base/AddressBook.sol";

contract DeployPeggedPriceOracleScript is BaseDeployScript, AddressBook {
    function run() public broadcast {
        _deploy("PeggedPriceOracle", type(PeggedPriceOracle).creationCode, _oraclesAddresses.peggedPriceOracle);
    }
}
