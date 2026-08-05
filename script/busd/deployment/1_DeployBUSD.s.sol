// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BUSDDeployer } from "src/busd/BUSDDeployer.sol";
import { BUSD } from "src/busd/BUSD.sol";
import { BUSDFactory } from "src/busd/BUSDFactory.sol";
import { BUSDFactoryReader } from "src/busd/BUSDFactoryReader.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { RBAC } from "../../base/RBAC.sol";
import { AddressBook } from "../../base/AddressBook.sol";
import { Storage } from "../../base/Storage.sol";

contract DeployBUSDScript is RBAC, BaseScript, Storage, AddressBook {
    BUSDDeployer internal busdDeployer;

    function run() public virtual broadcast {
        deployBUSD();
    }

    function deployBUSD() internal {
        console2.log("Deploying BUSD and BUSDFactory...");
        _validateCode("POL FeeCollector", _polAddresses.feeCollector);
        _validateCode("IPriceOracle", _oraclesAddresses.peggedPriceOracle);

        busdDeployer = new BUSDDeployer(
            msg.sender,
            _polAddresses.feeCollector,
            _polAddresses.feeCollector,
            _saltsForProxy(type(BUSD).creationCode),
            _saltsForProxy(type(BUSDFactory).creationCode),
            _saltsForProxy(type(BUSDFactoryReader).creationCode),
            _oraclesAddresses.peggedPriceOracle
        );

        console2.log("BUSDDeployer deployed at:", address(busdDeployer));

        busd = busdDeployer.busd();
        _checkDeploymentAddress("BUSD", address(busd), _busdAddresses.busd);

        busdFactory = busdDeployer.busdFactory();
        _checkDeploymentAddress("BUSDFactory", address(busdFactory), _busdAddresses.busdFactory);

        busdFactoryReader = busdDeployer.busdFactoryReader();
        _checkDeploymentAddress("BUSDFactoryReader", address(busdFactoryReader), _busdAddresses.busdFactoryReader);

        require(busdFactory.feeReceiver() == _polAddresses.feeCollector, "Fee receiver not set");
        console2.log("Fee receiver set to:", _polAddresses.feeCollector);

        require(busdFactory.polFeeCollector() == _polAddresses.feeCollector, "Pol fee collector not set");
        console2.log("Pol fee collector set to:", _polAddresses.feeCollector);

        // check roles
        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        RBAC.RoleDescription memory busdAdminRole = RBAC.RoleDescription({
            contractName: "BUSD",
            contractAddr: _busdAddresses.busd,
            name: "DEFAULT_ADMIN_ROLE",
            role: busd.DEFAULT_ADMIN_ROLE()
        });
        _requireRole(busdAdminRole, deployer);
        console2.log("BUSD's DEFAULT_ADMIN_ROLE granted to:", msg.sender);

        RBAC.RoleDescription memory busdFactoryAdminRole = RBAC.RoleDescription({
            contractName: "BUSDFactory",
            contractAddr: _busdAddresses.busdFactory,
            name: "DEFAULT_ADMIN_ROLE",
            role: busdFactory.DEFAULT_ADMIN_ROLE()
        });
        _requireRole(busdFactoryAdminRole, deployer);
        console2.log("BUSDFactory's DEFAULT_ADMIN_ROLE granted to:", msg.sender);

        RBAC.RoleDescription memory busdFactoryReaderAdminRole = RBAC.RoleDescription({
            contractName: "BUSDFactoryReader",
            contractAddr: _busdAddresses.busdFactoryReader,
            name: "DEFAULT_ADMIN_ROLE",
            role: busdFactoryReader.DEFAULT_ADMIN_ROLE()
        });
        _requireRole(busdFactoryReaderAdminRole, deployer);
        console2.log("BUSDFactoryReader's DEFAULT_ADMIN_ROLE granted to:", msg.sender);

        // granting MANAGER_ROLE to msg.sender as we need to call
        // setMintRate and setRedeemRate while doing `addCollateral`
        RBAC.RoleDescription memory managerRole = RBAC.RoleDescription({
            contractName: "BUSDFactory",
            contractAddr: _busdAddresses.busdFactory,
            name: "MANAGER_ROLE",
            role: busdFactory.MANAGER_ROLE()
        });
        _grantRole(managerRole, deployer);

        // grant the PAUSER_ROLE to msg.sender
        RBAC.RoleDescription memory pauserRole = RBAC.RoleDescription({
            contractName: "BUSDFactory",
            contractAddr: _busdAddresses.busdFactory,
            name: "PAUSER_ROLE",
            role: busdFactory.PAUSER_ROLE()
        });
        _grantRole(pauserRole, deployer);
    }
}
