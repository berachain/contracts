// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { RBAC } from "../../base/RBAC.sol";
import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";
import { Storage, Honey, HoneyFactory, HoneyFactoryReader } from "../../base/Storage.sol";
import { TIMELOCK_ADDRESS } from "../../gov/GovernanceAddresses.sol";
import { HONEY_ADDRESS, HONEY_FACTORY_ADDRESS, HONEY_FACTORY_READER_ADDRESS } from "../HoneyAddresses.sol";

contract TransferHoneyOwnership is RBAC, BaseScript, Storage {
    // Placeholder. Change before run script
    address constant HONEY_FACTORY_MANAGER = address(0);

    function run() public virtual broadcast {
        require(HONEY_FACTORY_MANAGER != address(0), "HONEY_FACTORY_MANAGER not set");
        _validateCode("TimeLock", TIMELOCK_ADDRESS);

        transferHoneyOwnership();
        transferHoneyFactoryOwnership();
        transferHoneyFactoryBeaconOwnership();
        transferHoneyFactoryReaderOwnership();
    }

    // transfer ownership of Honey to timelock and revoke the default admin role from msg.sender
    function transferHoneyOwnership() internal {
        _validateCode("Honey", HONEY_ADDRESS);
        honey = Honey(HONEY_ADDRESS);

        RBAC.RoleDescription memory adminRole = RBAC.RoleDescription({
            contractName: "Honey",
            contractAddr: HONEY_ADDRESS,
            name: "DEFAULT_ADMIN_ROLE",
            role: honey.DEFAULT_ADMIN_ROLE()
        });

        RBAC.AccountDescription memory governance =
            RBAC.AccountDescription({ name: "governance", addr: TIMELOCK_ADDRESS });

        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        _grantRole(adminRole, governance);
        _revokeRole(adminRole, deployer);
    }

    // transfer ownership of HoneyFactory to timelock and set the manager role to honeyFactoryManager
    // also revoke the manager and default admin roles from msg.sender
    function transferHoneyFactoryOwnership() internal {
        _validateCode("HoneyFactory", HONEY_FACTORY_ADDRESS);
        honeyFactory = HoneyFactory(HONEY_FACTORY_ADDRESS);

        RBAC.RoleDescription memory adminRole = RBAC.RoleDescription({
            contractName: "HoneyFactory",
            contractAddr: HONEY_FACTORY_ADDRESS,
            name: "DEFAULT_ADMIN_ROLE",
            role: honeyFactory.DEFAULT_ADMIN_ROLE()
        });

        RBAC.RoleDescription memory managerRole = RBAC.RoleDescription({
            contractName: "HoneyFactory",
            contractAddr: HONEY_FACTORY_ADDRESS,
            name: "MANAGER_ROLE",
            role: honeyFactory.MANAGER_ROLE()
        });

        RBAC.RoleDescription memory pauserRole = RBAC.RoleDescription({
            contractName: "HoneyFactory",
            contractAddr: HONEY_FACTORY_ADDRESS,
            name: "PAUSER_ROLE",
            role: honeyFactory.PAUSER_ROLE()
        });

        RBAC.AccountDescription memory governance =
            RBAC.AccountDescription({ name: "governance", addr: TIMELOCK_ADDRESS });

        RBAC.AccountDescription memory manager =
            RBAC.AccountDescription({ name: "manager", addr: HONEY_FACTORY_MANAGER });

        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        _grantRole(adminRole, governance);
        _grantRole(managerRole, manager);
        _grantRole(pauserRole, manager);
        _revokeRole(pauserRole, deployer);
        _revokeRole(managerRole, deployer);
        _revokeRole(adminRole, deployer);
    }

    // transfer ownership of HoneyFactory's Beacon to timelock
    function transferHoneyFactoryBeaconOwnership() internal {
        _validateCode("HoneyFactory", HONEY_FACTORY_ADDRESS);
        honeyFactory = HoneyFactory(HONEY_FACTORY_ADDRESS);

        console2.log("Transferring ownership of HoneyFactory's Beacon...");
        UpgradeableBeacon beacon = UpgradeableBeacon(honeyFactory.beacon());
        beacon.transferOwnership(TIMELOCK_ADDRESS);
        require(beacon.owner() == TIMELOCK_ADDRESS, "Ownership of HoneyFactory's Beacon not transferred to timelock");
        console2.log("Ownership of HoneyFactory's Beacon transferred to:", TIMELOCK_ADDRESS);
    }

    // transfer ownership of HoneyFactoryReader to timelock
    function transferHoneyFactoryReaderOwnership() internal {
        _validateCode("HoneyFactoryReader", HONEY_FACTORY_READER_ADDRESS);
        honeyFactoryReader = HoneyFactoryReader(HONEY_FACTORY_READER_ADDRESS);

        RBAC.RoleDescription memory adminRole = RBAC.RoleDescription({
            contractName: "HoneyFactoryReader",
            contractAddr: HONEY_FACTORY_READER_ADDRESS,
            name: "DEFAULT_ADMIN_ROLE",
            role: honeyFactoryReader.DEFAULT_ADMIN_ROLE()
        });

        RBAC.AccountDescription memory governance =
            RBAC.AccountDescription({ name: "governance", addr: TIMELOCK_ADDRESS });

        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        _grantRole(adminRole, governance);
        _revokeRole(adminRole, deployer);
    }
}
