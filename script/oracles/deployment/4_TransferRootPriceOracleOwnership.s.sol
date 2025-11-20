// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BaseScript } from "../../base/Base.s.sol";
import { RBAC } from "../../base/RBAC.sol";
import { RootPriceOracle } from "src/extras/RootPriceOracle.sol";
import { AddressBook } from "../../base/AddressBook.sol";

contract TransferRootPriceOracleOwnershipScript is RBAC, BaseScript, AddressBook {
    // Placholder. Change before running the script.
    address internal constant NEW_OWNER = address(0); // TIMELOCK_ADDRESS;
    address internal constant ROOT_PRICE_ORACLE_MANAGER = address(0);

    constructor() AddressBook(_chainType) { }

    function run() public virtual broadcast {
        require(NEW_OWNER != address(0), "NEW_OWNER must be set");
        require(ROOT_PRICE_ORACLE_MANAGER != address(0), "Root price oracle manager address not set");
        if (NEW_OWNER == _governanceAddresses.timelock) {
            _validateCode("TimeLock", NEW_OWNER);
        }
        _validateCode("RootPriceOracle", _oraclesAddresses.rootPriceOracle);

        RootPriceOracle rootPriceOracle = RootPriceOracle(_oraclesAddresses.rootPriceOracle);

        RBAC.RoleDescription memory adminRole = RBAC.RoleDescription({
            contractName: "RootPriceOracle",
            contractAddr: _oraclesAddresses.rootPriceOracle,
            name: "DEFAULT_ADMIN_ROLE",
            role: rootPriceOracle.DEFAULT_ADMIN_ROLE()
        });

        RBAC.RoleDescription memory managerRole = RBAC.RoleDescription({
            contractName: "RootPriceOracle",
            contractAddr: _oraclesAddresses.rootPriceOracle,
            name: "MANAGER_ROLE",
            role: rootPriceOracle.MANAGER_ROLE()
        });

        RBAC.AccountDescription memory governance = RBAC.AccountDescription({ name: "governance", addr: NEW_OWNER });

        RBAC.AccountDescription memory manager =
            RBAC.AccountDescription({ name: "manager", addr: ROOT_PRICE_ORACLE_MANAGER });

        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        _transferRole(managerRole, deployer, manager);
        _transferRole(adminRole, deployer, governance);
    }
}
