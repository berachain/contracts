// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BaseScript } from "../../base/Base.s.sol";
import { RBAC } from "../../base/RBAC.sol";
import { PythPriceOracle } from "src/extras/PythPriceOracle.sol";
import { AddressBook } from "../../base/AddressBook.sol";

contract TransferPythPriceOracleOwnershipScript is RBAC, BaseScript, AddressBook {
    // Placholder. Change before running the script.
    address internal constant NEW_OWNER = address(0); // TIMELOCK_ADDRESS;
    address internal constant PYTH_PRICE_ORACLE_MANAGER = address(0);

    function run() public virtual broadcast {
        require(NEW_OWNER != address(0), "NEW_OWNER must be set");
        require(PYTH_PRICE_ORACLE_MANAGER != address(0), "Pyth price oracle manager address not set");
        if (NEW_OWNER == _governanceAddresses.timelock) {
            _validateCode("TimeLock", NEW_OWNER);
        }
        _validateCode("PythPriceOracle", _oraclesAddresses.pythPriceOracle);

        PythPriceOracle pythPriceOracle = PythPriceOracle(_oraclesAddresses.pythPriceOracle);

        RBAC.RoleDescription memory adminRole = RBAC.RoleDescription({
            contractName: "PythPriceOracle",
            contractAddr: _oraclesAddresses.pythPriceOracle,
            name: "DEFAULT_ADMIN_ROLE",
            role: pythPriceOracle.DEFAULT_ADMIN_ROLE()
        });

        RBAC.RoleDescription memory managerRole = RBAC.RoleDescription({
            contractName: "PythPriceOracle",
            contractAddr: _oraclesAddresses.pythPriceOracle,
            name: "MANAGER_ROLE",
            role: pythPriceOracle.MANAGER_ROLE()
        });

        RBAC.AccountDescription memory governance = RBAC.AccountDescription({ name: "governance", addr: NEW_OWNER });

        RBAC.AccountDescription memory manager =
            RBAC.AccountDescription({ name: "manager", addr: PYTH_PRICE_ORACLE_MANAGER });

        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        _transferRole(managerRole, deployer, manager);
        _transferRole(adminRole, deployer, governance);
    }
}
