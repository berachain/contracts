// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ChainHelper } from "./Chain.sol";
import { HoneyAddressBook } from "../honey/HoneyAddresses.sol";
import { POLAddressBook } from "../pol/POLAddresses.sol";
import { OraclesAddressBook } from "../oracles/OraclesAddresses.sol";
import { GovernanceAddressBook } from "../gov/GovernanceAddresses.sol";

abstract contract AddressBook is HoneyAddressBook, POLAddressBook, OraclesAddressBook, GovernanceAddressBook {
    constructor()
        HoneyAddressBook(ChainHelper.getType())
        POLAddressBook(ChainHelper.getType())
        OraclesAddressBook(ChainHelper.getType())
        GovernanceAddressBook(ChainHelper.getType())
    { }
}
