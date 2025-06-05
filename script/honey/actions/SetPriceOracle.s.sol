// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BaseScript } from "../../base/Base.s.sol";
import { HoneyFactory } from "src/honey/HoneyFactory.sol";
import { HONEY_FACTORY_ADDRESS } from "../HoneyAddresses.sol";
import { PYTH_PRICE_ORACLE_ADDRESS } from "../../oracles/OraclesAddresses.sol";

/// @notice Creates a collateral vault for the given token.
contract SetPriceOracleScript is BaseScript {
    // Placeholders. Change before run script.
    address constant PRICE_ORACLE = PYTH_PRICE_ORACLE_ADDRESS; // choose the preferred one

    function run() public virtual broadcast {
        _validateCode("HoneyFactory", HONEY_FACTORY_ADDRESS);
        _validateCode("IPriceOracle", PRICE_ORACLE);

        HoneyFactory factory = HoneyFactory(HONEY_FACTORY_ADDRESS);
        factory.setPriceOracle(PRICE_ORACLE);
    }
}
