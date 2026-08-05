// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { RBAC } from "../../base/RBAC.sol";
import { AddressBook } from "../../base/AddressBook.sol";
import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";
import { Storage, BUSD, BUSDFactory, BUSDFactoryReader } from "../../base/Storage.sol";

contract TransferBUSDOwnership is RBAC, BaseScript, Storage, AddressBook {
    // Placeholder. Change before run script
    address constant NEW_OWNER = address(0); // TIMELOCK_ADDRESS
    address constant BUSD_FACTORY_MANAGER = address(0);

    function run() public virtual broadcast {
        require(BUSD_FACTORY_MANAGER != address(0), "BUSD_FACTORY_MANAGER not set");
        require(NEW_OWNER != address(0), "NEW_OWNER not set");
        if (NEW_OWNER == _governanceAddresses.timelock) {
            _validateCode("TimeLock", NEW_OWNER);
        }

        transferBUSDOwnership();
        transferBUSDFactoryOwnership();
        transferBUSDFactoryBeaconOwnership();
        transferBUSDFactoryReaderOwnership();
    }

    // transfer ownership of BUSD to timelock and revoke the default admin role from msg.sender
    function transferBUSDOwnership() internal {
        _validateCode("BUSD", _busdAddresses.busd);
        busd = BUSD(_busdAddresses.busd);

        RBAC.RoleDescription memory adminRole = RBAC.RoleDescription({
            contractName: "BUSD",
            contractAddr: _busdAddresses.busd,
            name: "DEFAULT_ADMIN_ROLE",
            role: busd.DEFAULT_ADMIN_ROLE()
        });

        RBAC.AccountDescription memory governance = RBAC.AccountDescription({ name: "governance", addr: NEW_OWNER });

        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        _transferRole(adminRole, deployer, governance);
    }

    // transfer ownership of BUSDFactory to timelock and set the manager role to busdFactoryManager
    // also revoke the manager and default admin roles from msg.sender
    function transferBUSDFactoryOwnership() internal {
        _validateCode("BUSDFactory", _busdAddresses.busdFactory);
        busdFactory = BUSDFactory(_busdAddresses.busdFactory);

        RBAC.RoleDescription memory adminRole = RBAC.RoleDescription({
            contractName: "BUSDFactory",
            contractAddr: _busdAddresses.busdFactory,
            name: "DEFAULT_ADMIN_ROLE",
            role: busdFactory.DEFAULT_ADMIN_ROLE()
        });

        RBAC.RoleDescription memory managerRole = RBAC.RoleDescription({
            contractName: "BUSDFactory",
            contractAddr: _busdAddresses.busdFactory,
            name: "MANAGER_ROLE",
            role: busdFactory.MANAGER_ROLE()
        });

        RBAC.RoleDescription memory pauserRole = RBAC.RoleDescription({
            contractName: "BUSDFactory",
            contractAddr: _busdAddresses.busdFactory,
            name: "PAUSER_ROLE",
            role: busdFactory.PAUSER_ROLE()
        });

        RBAC.AccountDescription memory governance = RBAC.AccountDescription({ name: "governance", addr: NEW_OWNER });

        RBAC.AccountDescription memory manager =
            RBAC.AccountDescription({ name: "manager", addr: BUSD_FACTORY_MANAGER });

        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        _transferRole(pauserRole, deployer, manager);
        _transferRole(managerRole, deployer, manager);
        _transferRole(adminRole, deployer, governance);
    }

    // transfer ownership of BUSDFactory's Beacon to timelock
    function transferBUSDFactoryBeaconOwnership() internal {
        _validateCode("BUSDFactory", _busdAddresses.busdFactory);
        busdFactory = BUSDFactory(_busdAddresses.busdFactory);

        console2.log("Transferring ownership of BUSDFactory's Beacon...");
        UpgradeableBeacon beacon = UpgradeableBeacon(busdFactory.beacon());
        beacon.transferOwnership(NEW_OWNER);
        require(beacon.owner() == NEW_OWNER, "Ownership of BUSDFactory's Beacon not transferred to timelock");
        console2.log("Ownership of BUSDFactory's Beacon transferred to:", NEW_OWNER);
    }

    // transfer ownership of BUSDFactoryReader to timelock
    function transferBUSDFactoryReaderOwnership() internal {
        _validateCode("BUSDFactoryReader", _busdAddresses.busdFactoryReader);
        busdFactoryReader = BUSDFactoryReader(_busdAddresses.busdFactoryReader);

        RBAC.RoleDescription memory adminRole = RBAC.RoleDescription({
            contractName: "BUSDFactoryReader",
            contractAddr: _busdAddresses.busdFactoryReader,
            name: "DEFAULT_ADMIN_ROLE",
            role: busdFactoryReader.DEFAULT_ADMIN_ROLE()
        });

        RBAC.AccountDescription memory governance = RBAC.AccountDescription({ name: "governance", addr: NEW_OWNER });

        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        _transferRole(adminRole, deployer, governance);
    }
}
