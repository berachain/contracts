// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ChainHelper } from "./Chain.sol";
import { BUSDAddressBook } from "../busd/BUSDAddresses.sol";
import { POLAddressBook } from "../pol/POLAddresses.sol";
import { OraclesAddressBook } from "../oracles/OraclesAddresses.sol";
import { GovernanceAddressBook } from "../gov/GovernanceAddresses.sol";

abstract contract AddressBook is BUSDAddressBook, POLAddressBook, OraclesAddressBook, GovernanceAddressBook {
    constructor()
        BUSDAddressBook(ChainHelper.getType())
        POLAddressBook(ChainHelper.getType())
        OraclesAddressBook(ChainHelper.getType())
        GovernanceAddressBook(ChainHelper.getType())
    { }
}
