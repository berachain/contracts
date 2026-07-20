// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { RBAC } from "../../base/RBAC.sol";
import { RedStonePriceOracleDeployer } from "src/extras/RedStonePriceOracleDeployer.sol";
import { RedStonePriceOracle } from "src/extras/RedStonePriceOracle.sol";
import { AddressBook } from "../../base/AddressBook.sol";

contract DeployRedStonePriceOracleScript is RBAC, BaseScript, AddressBook {
    function run() public pure {
        console2.log("Please run specific function.");
    }

    function deployRedStonePriceOracle(address redstonePriceFeedAdapter, address governance) public broadcast {
        RedStonePriceOracleDeployer oracleDeployer = new RedStonePriceOracleDeployer(
            governance, redstonePriceFeedAdapter, _saltsForProxy(type(RedStonePriceOracle).creationCode)
        );

        RedStonePriceOracle redStonePriceOracle = RedStonePriceOracle(oracleDeployer.oracle());
        _checkDeploymentAddress(
            "RedStonePriceOracle", address(redStonePriceOracle), _oraclesAddresses.redStonePriceOracle
        );

        RBAC.RoleDescription memory adminRole = RBAC.RoleDescription({
            contractName: "RedStonePriceOracle",
            contractAddr: _oraclesAddresses.redStonePriceOracle,
            name: "DEFAULT_ADMIN_ROLE",
            role: redStonePriceOracle.DEFAULT_ADMIN_ROLE()
        });

        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: governance });
        _requireRole(adminRole, deployer);
    }
}
