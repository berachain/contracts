// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BaseScript } from "../../base/Base.s.sol";
import { BUSDFactory } from "src/busd/BUSDFactory.sol";
import { AddressBook } from "../../base/AddressBook.sol";

/// @notice Creates a collateral vault for the given token.
contract SetPriceOracleScript is BaseScript, AddressBook {
    function run() public virtual broadcast {
        address priceOracle = _oraclesAddresses.pythPriceOracle; // choose the preferred oracle

        _validateCode("BUSDFactory", _busdAddresses.busdFactory);
        _validateCode("IPriceOracle", priceOracle);

        BUSDFactory factory = BUSDFactory(_busdAddresses.busdFactory);
        factory.setPriceOracle(priceOracle);
    }
}
