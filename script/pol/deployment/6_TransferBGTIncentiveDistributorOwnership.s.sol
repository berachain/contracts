// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { RBAC } from "../../base/RBAC.sol";
import "../../base/Storage.sol";
import { AddressBook } from "../../base/AddressBook.sol";

contract TransferBGTIncentiveDistributorOwnershipScript is RBAC, BaseScript, Storage, AddressBook {
    constructor() AddressBook(_chainType) { }

    // Placholder. Change before running the script.
    address internal constant NEW_OWNER = address(0); // TIMELOCK_ADDRESS;

    function run() public virtual broadcast {
        // Check if the new owner is set
        require(NEW_OWNER != address(0), "NEW_OWNER must be set");

        // create contracts instance from deployed addresses
        if (NEW_OWNER == _governanceAddresses.timelock) {
            _validateCode("TimeLock", NEW_OWNER);
        }
        _loadStorageContracts();

        console2.log("Transferring ownership of BGTIncentiveDistributor contract...");
        transferBGTIncentiveDistributorOwnership();
    }

    function transferBGTIncentiveDistributorOwnership() internal {
        RBAC.RoleDescription memory bgtIncentiveDistributorAdminRole = RBAC.RoleDescription({
            contractName: "BGTIncentiveDistributor",
            contractAddr: _polAddresses.bgtIncentiveDistributor,
            name: "DEFAULT_ADMIN_ROLE",
            role: bgtIncentiveDistributor.DEFAULT_ADMIN_ROLE()
        });
        RBAC.RoleDescription memory bgtIncentiveDistributorManagerRole = RBAC.RoleDescription({
            contractName: "BGTIncentiveDistributor",
            contractAddr: _polAddresses.bgtIncentiveDistributor,
            name: "MANAGER_ROLE",
            role: bgtIncentiveDistributor.MANAGER_ROLE()
        });
        RBAC.RoleDescription memory bgtIncentiveDistributorPauserRole = RBAC.RoleDescription({
            contractName: "BGTIncentiveDistributor",
            contractAddr: _polAddresses.bgtIncentiveDistributor,
            name: "PAUSER_ROLE",
            role: bgtIncentiveDistributor.PAUSER_ROLE()
        });

        RBAC.AccountDescription memory governance = RBAC.AccountDescription({ name: "governance", addr: NEW_OWNER });
        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        _transferRole(bgtIncentiveDistributorPauserRole, deployer, governance);
        _transferRole(bgtIncentiveDistributorManagerRole, deployer, governance);
        _transferRole(bgtIncentiveDistributorAdminRole, deployer, governance);
    }

    function _loadStorageContracts() internal {
        _validateCode("BGTIncentiveDistributor", _polAddresses.bgtIncentiveDistributor);
        bgtIncentiveDistributor = BGTIncentiveDistributor(_polAddresses.bgtIncentiveDistributor);
    }
}
