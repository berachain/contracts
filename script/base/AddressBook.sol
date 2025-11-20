// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ChainType } from "./Chain.sol";
import { HoneyAddressBook } from "../honey/HoneyAddresses.sol";
import { POLAddressBook } from "../pol/POLAddresses.sol";
import { OraclesAddressBook } from "../oracles/OraclesAddresses.sol";
import { GovernanceAddressBook } from "../gov/GovernanceAddresses.sol";

abstract contract AddressBook is HoneyAddressBook, POLAddressBook, OraclesAddressBook, GovernanceAddressBook {
    constructor(ChainType chainType)
        HoneyAddressBook(chainType)
        POLAddressBook(chainType)
        OraclesAddressBook(chainType)
        GovernanceAddressBook(chainType)
    { }
}
