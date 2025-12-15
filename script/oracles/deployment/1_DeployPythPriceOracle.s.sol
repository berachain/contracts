// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BaseScript } from "../../base/Base.s.sol";
import { RBAC } from "../../base/RBAC.sol";
import { PythPriceOracleDeployer } from "src/extras/PythPriceOracleDeployer.sol";
import { PythPriceOracle } from "src/extras/PythPriceOracle.sol";
import { AddressBook } from "../../base/AddressBook.sol";

contract DeployPythPriceOracleScript is RBAC, BaseScript, AddressBook {
    function run() public broadcast {
        PythPriceOracleDeployer oracleDeployer =
            new PythPriceOracleDeployer(msg.sender, _saltsForProxy(type(PythPriceOracle).creationCode));

        PythPriceOracle pythPriceOracle = PythPriceOracle(oracleDeployer.oracle());
        _checkDeploymentAddress("PythPriceOracle", address(pythPriceOracle), _oraclesAddresses.pythPriceOracle);

        RBAC.RoleDescription memory adminRole = RBAC.RoleDescription({
            contractName: "PythPriceOracle",
            contractAddr: _oraclesAddresses.pythPriceOracle,
            name: "DEFAULT_ADMIN_ROLE",
            role: pythPriceOracle.DEFAULT_ADMIN_ROLE()
        });

        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        _requireRole(adminRole, deployer);
    }
}
