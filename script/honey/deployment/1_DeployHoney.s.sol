// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { HoneyDeployer } from "src/honey/HoneyDeployer.sol";
import { Honey } from "src/honey/Honey.sol";
import { HoneyFactory } from "src/honey/HoneyFactory.sol";
import { HoneyFactoryReader } from "src/honey/HoneyFactoryReader.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { RBAC } from "../../base/RBAC.sol";
import { AddressBook } from "../../base/AddressBook.sol";
import { Storage } from "../../base/Storage.sol";

contract DeployHoneyScript is RBAC, BaseScript, Storage, AddressBook {
    HoneyDeployer internal honeyDeployer;

    function run() public virtual broadcast {
        deployHoney();
    }

    function deployHoney() internal {
        console2.log("Deploying Honey and HoneyFactory...");
        _validateCode("POL FeeCollector", _polAddresses.feeCollector);
        _validateCode("IPriceOracle", _oraclesAddresses.peggedPriceOracle);

        honeyDeployer = new HoneyDeployer(
            msg.sender,
            _polAddresses.feeCollector,
            _polAddresses.feeCollector,
            _saltsForProxy(type(Honey).creationCode),
            _saltsForProxy(type(HoneyFactory).creationCode),
            _saltsForProxy(type(HoneyFactoryReader).creationCode),
            _oraclesAddresses.peggedPriceOracle
        );

        console2.log("HoneyDeployer deployed at:", address(honeyDeployer));

        honey = honeyDeployer.honey();
        _checkDeploymentAddress("Honey", address(honey), _honeyAddresses.honey);

        honeyFactory = honeyDeployer.honeyFactory();
        _checkDeploymentAddress("HoneyFactory", address(honeyFactory), _honeyAddresses.honeyFactory);

        honeyFactoryReader = honeyDeployer.honeyFactoryReader();
        _checkDeploymentAddress("HoneyFactoryReader", address(honeyFactoryReader), _honeyAddresses.honeyFactoryReader);

        require(honeyFactory.feeReceiver() == _polAddresses.feeCollector, "Fee receiver not set");
        console2.log("Fee receiver set to:", _polAddresses.feeCollector);

        require(honeyFactory.polFeeCollector() == _polAddresses.feeCollector, "Pol fee collector not set");
        console2.log("Pol fee collector set to:", _polAddresses.feeCollector);

        // check roles
        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        RBAC.RoleDescription memory honeyAdminRole = RBAC.RoleDescription({
            contractName: "Honey",
            contractAddr: _honeyAddresses.honey,
            name: "DEFAULT_ADMIN_ROLE",
            role: honey.DEFAULT_ADMIN_ROLE()
        });
        _requireRole(honeyAdminRole, deployer);
        console2.log("Honey's DEFAULT_ADMIN_ROLE granted to:", msg.sender);

        RBAC.RoleDescription memory honeyFactoryAdminRole = RBAC.RoleDescription({
            contractName: "HoneyFactory",
            contractAddr: _honeyAddresses.honeyFactory,
            name: "DEFAULT_ADMIN_ROLE",
            role: honeyFactory.DEFAULT_ADMIN_ROLE()
        });
        _requireRole(honeyFactoryAdminRole, deployer);
        console2.log("HoneyFactory's DEFAULT_ADMIN_ROLE granted to:", msg.sender);

        RBAC.RoleDescription memory honeyFactoryReaderAdminRole = RBAC.RoleDescription({
            contractName: "HoneyFactoryReader",
            contractAddr: _honeyAddresses.honeyFactoryReader,
            name: "DEFAULT_ADMIN_ROLE",
            role: honeyFactoryReader.DEFAULT_ADMIN_ROLE()
        });
        _requireRole(honeyFactoryReaderAdminRole, deployer);
        console2.log("HoneyFactoryReader's DEFAULT_ADMIN_ROLE granted to:", msg.sender);

        // granting MANAGER_ROLE to msg.sender as we need to call
        // setMintRate and setRedeemRate while doing `addCollateral`
        RBAC.RoleDescription memory managerRole = RBAC.RoleDescription({
            contractName: "HoneyFactory",
            contractAddr: _honeyAddresses.honeyFactory,
            name: "MANAGER_ROLE",
            role: honeyFactory.MANAGER_ROLE()
        });
        _grantRole(managerRole, deployer);

        // grant the PAUSER_ROLE to msg.sender
        RBAC.RoleDescription memory pauserRole = RBAC.RoleDescription({
            contractName: "HoneyFactory",
            contractAddr: _honeyAddresses.honeyFactory,
            name: "PAUSER_ROLE",
            role: honeyFactory.PAUSER_ROLE()
        });
        _grantRole(pauserRole, deployer);
    }
}
