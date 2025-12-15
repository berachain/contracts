// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { RBAC } from "../../base/RBAC.sol";
import { AddressBook } from "../../base/AddressBook.sol";
import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";
import { Storage, Honey, HoneyFactory, HoneyFactoryReader } from "../../base/Storage.sol";

contract TransferHoneyOwnership is RBAC, BaseScript, Storage, AddressBook {
    // Placeholder. Change before run script
    address constant NEW_OWNER = address(0); // TIMELOCK_ADDRESS
    address constant HONEY_FACTORY_MANAGER = address(0);

    function run() public virtual broadcast {
        require(HONEY_FACTORY_MANAGER != address(0), "HONEY_FACTORY_MANAGER not set");
        require(NEW_OWNER != address(0), "NEW_OWNER not set");
        if (NEW_OWNER == _governanceAddresses.timelock) {
            _validateCode("TimeLock", NEW_OWNER);
        }

        transferHoneyOwnership();
        transferHoneyFactoryOwnership();
        transferHoneyFactoryBeaconOwnership();
        transferHoneyFactoryReaderOwnership();
    }

    // transfer ownership of Honey to timelock and revoke the default admin role from msg.sender
    function transferHoneyOwnership() internal {
        _validateCode("Honey", _honeyAddresses.honey);
        honey = Honey(_honeyAddresses.honey);

        RBAC.RoleDescription memory adminRole = RBAC.RoleDescription({
            contractName: "Honey",
            contractAddr: _honeyAddresses.honey,
            name: "DEFAULT_ADMIN_ROLE",
            role: honey.DEFAULT_ADMIN_ROLE()
        });

        RBAC.AccountDescription memory governance = RBAC.AccountDescription({ name: "governance", addr: NEW_OWNER });

        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        _transferRole(adminRole, deployer, governance);
    }

    // transfer ownership of HoneyFactory to timelock and set the manager role to honeyFactoryManager
    // also revoke the manager and default admin roles from msg.sender
    function transferHoneyFactoryOwnership() internal {
        _validateCode("HoneyFactory", _honeyAddresses.honeyFactory);
        honeyFactory = HoneyFactory(_honeyAddresses.honeyFactory);

        RBAC.RoleDescription memory adminRole = RBAC.RoleDescription({
            contractName: "HoneyFactory",
            contractAddr: _honeyAddresses.honeyFactory,
            name: "DEFAULT_ADMIN_ROLE",
            role: honeyFactory.DEFAULT_ADMIN_ROLE()
        });

        RBAC.RoleDescription memory managerRole = RBAC.RoleDescription({
            contractName: "HoneyFactory",
            contractAddr: _honeyAddresses.honeyFactory,
            name: "MANAGER_ROLE",
            role: honeyFactory.MANAGER_ROLE()
        });

        RBAC.RoleDescription memory pauserRole = RBAC.RoleDescription({
            contractName: "HoneyFactory",
            contractAddr: _honeyAddresses.honeyFactory,
            name: "PAUSER_ROLE",
            role: honeyFactory.PAUSER_ROLE()
        });

        RBAC.AccountDescription memory governance = RBAC.AccountDescription({ name: "governance", addr: NEW_OWNER });

        RBAC.AccountDescription memory manager =
            RBAC.AccountDescription({ name: "manager", addr: HONEY_FACTORY_MANAGER });

        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        _transferRole(pauserRole, deployer, manager);
        _transferRole(managerRole, deployer, manager);
        _transferRole(adminRole, deployer, governance);
    }

    // transfer ownership of HoneyFactory's Beacon to timelock
    function transferHoneyFactoryBeaconOwnership() internal {
        _validateCode("HoneyFactory", _honeyAddresses.honeyFactory);
        honeyFactory = HoneyFactory(_honeyAddresses.honeyFactory);

        console2.log("Transferring ownership of HoneyFactory's Beacon...");
        UpgradeableBeacon beacon = UpgradeableBeacon(honeyFactory.beacon());
        beacon.transferOwnership(NEW_OWNER);
        require(beacon.owner() == NEW_OWNER, "Ownership of HoneyFactory's Beacon not transferred to timelock");
        console2.log("Ownership of HoneyFactory's Beacon transferred to:", NEW_OWNER);
    }

    // transfer ownership of HoneyFactoryReader to timelock
    function transferHoneyFactoryReaderOwnership() internal {
        _validateCode("HoneyFactoryReader", _honeyAddresses.honeyFactoryReader);
        honeyFactoryReader = HoneyFactoryReader(_honeyAddresses.honeyFactoryReader);

        RBAC.RoleDescription memory adminRole = RBAC.RoleDescription({
            contractName: "HoneyFactoryReader",
            contractAddr: _honeyAddresses.honeyFactoryReader,
            name: "DEFAULT_ADMIN_ROLE",
            role: honeyFactoryReader.DEFAULT_ADMIN_ROLE()
        });

        RBAC.AccountDescription memory governance = RBAC.AccountDescription({ name: "governance", addr: NEW_OWNER });

        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        _transferRole(adminRole, deployer, governance);
    }
}
