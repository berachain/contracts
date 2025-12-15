// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { RBAC } from "../../base/RBAC.sol";
import { RootPriceOracle } from "src/extras/RootPriceOracle.sol";
import { RootPriceOracleDeployer } from "src/extras/RootPriceOracleDeployer.sol";
import { AddressBook } from "../../base/AddressBook.sol";

contract DeployRootPriceOracleScript is RBAC, BaseScript, AddressBook {
    function run() public broadcast {
        RootPriceOracleDeployer oracleDeployer =
            new RootPriceOracleDeployer(msg.sender, _salt(type(RootPriceOracle).creationCode));

        RootPriceOracle rootPriceOracle = oracleDeployer.rootPriceOracle();
        console2.log("RootPriceOracle deployed at:", address(rootPriceOracle));
        _checkDeploymentAddress("RootPriceOracle", address(rootPriceOracle), _oraclesAddresses.rootPriceOracle);

        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        RBAC.RoleDescription memory adminRole = RBAC.RoleDescription({
            contractName: "RootPriceOracle",
            contractAddr: _oraclesAddresses.rootPriceOracle,
            name: "DEFAULT_ADMIN_ROLE",
            role: rootPriceOracle.DEFAULT_ADMIN_ROLE()
        });

        _requireRole(adminRole, deployer);

        RBAC.RoleDescription memory managerRole = RBAC.RoleDescription({
            contractName: "RootPriceOracle",
            contractAddr: _oraclesAddresses.rootPriceOracle,
            name: "MANAGER_ROLE",
            role: rootPriceOracle.MANAGER_ROLE()
        });

        _grantRole(managerRole, deployer);
    }
}
