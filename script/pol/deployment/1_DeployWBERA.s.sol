// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BaseScript } from "../../base/Base.s.sol";
import { WBERA } from "src/WBERA.sol";
import { WBERADeployer } from "../logic/WBERADeployer.sol";
import { AddressBook } from "../../base/AddressBook.sol";

/// @dev Deprecated. WBERA is deployed during genesis.
contract DeployWBERAScript is BaseScript, WBERADeployer, AddressBook {
    constructor() AddressBook(_chainType) { }

    function run() public broadcast {
        address wbera = deployWBERA(_salt(type(WBERA).creationCode));
        _checkDeploymentAddress("WBERA", wbera, _polAddresses.wbera);
    }
}
