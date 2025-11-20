// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BaseScript } from "../../base/Base.s.sol";
import { HoneyFactory } from "src/honey/HoneyFactory.sol";
import { AddressBook } from "../../base/AddressBook.sol";

/// @notice Creates a collateral vault for the given token.
contract SetPriceOracleScript is BaseScript, AddressBook {
    constructor() AddressBook(_chainType) { }

    function run() public virtual broadcast {
        address priceOracle = _oraclesAddresses.pythPriceOracle; // choose the preferred oracle

        _validateCode("HoneyFactory", _honeyAddresses.honeyFactory);
        _validateCode("IPriceOracle", priceOracle);

        HoneyFactory factory = HoneyFactory(_honeyAddresses.honeyFactory);
        factory.setPriceOracle(priceOracle);
    }
}
