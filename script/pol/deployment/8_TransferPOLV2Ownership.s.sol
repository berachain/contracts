// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { RBAC } from "../../base/RBAC.sol";
import "../../base/Storage.sol";
import { AddressBook } from "../../base/AddressBook.sol";

contract TransferPOLV2OwnershipScript is RBAC, BaseScript, Storage, AddressBook {
    function run() public pure {
        console2.log("Please run specific function.");
    }

    function transferPOLV2Ownership(address newOwner) public broadcast {
        console2.log("Transferring ownership of POLV2 contracts...");
        // Check if the new owner is set
        require(newOwner != address(0), "NEW_OWNER must be set");
        console2.log("NEW_OWNER", newOwner);

        // create contracts instance from deployed addresses
        if (newOwner == _governanceAddresses.timelock) {
            _validateCode("TimeLock", newOwner);
        }
        _loadStorageContracts();

        RBAC.AccountDescription memory governance = RBAC.AccountDescription({ name: "governance", addr: newOwner });
        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        _transferWBERAStakerVaultOwnership(deployer, governance);
        _transferIncentivesCollectorOwnership(deployer, governance);
    }

    function _transferWBERAStakerVaultOwnership(
        RBAC.AccountDescription memory deployer,
        RBAC.AccountDescription memory governance
    )
        internal
    {
        RBAC.RoleDescription memory wberaStakerVaultAdminRole = RBAC.RoleDescription({
            contractName: "WBERAStakerVault",
            contractAddr: _polAddresses.wberaStakerVault,
            name: "DEFAULT_ADMIN_ROLE",
            role: wberaStakerVault.DEFAULT_ADMIN_ROLE()
        });
        RBAC.RoleDescription memory wberaStakerVaultManagerRole = RBAC.RoleDescription({
            contractName: "WBERAStakerVault",
            contractAddr: _polAddresses.wberaStakerVault,
            name: "MANAGER_ROLE",
            role: wberaStakerVault.MANAGER_ROLE()
        });
        RBAC.RoleDescription memory wberaStakerVaultPauserRole = RBAC.RoleDescription({
            contractName: "WBERAStakerVault",
            contractAddr: _polAddresses.wberaStakerVault,
            name: "PAUSER_ROLE",
            role: wberaStakerVault.PAUSER_ROLE()
        });
        console2.log("Transferring ownership of WBERAStakerVault contract...");
        _transferRole(wberaStakerVaultPauserRole, deployer, governance);
        _transferRole(wberaStakerVaultManagerRole, deployer, governance);
        _transferRole(wberaStakerVaultAdminRole, deployer, governance);
    }

    function _transferIncentivesCollectorOwnership(
        RBAC.AccountDescription memory deployer,
        RBAC.AccountDescription memory governance
    )
        internal
    {
        RBAC.RoleDescription memory incentivesCollectorAdminRole = RBAC.RoleDescription({
            contractName: "IncentivesCollector",
            contractAddr: _polAddresses.incentivesCollector,
            name: "DEFAULT_ADMIN_ROLE",
            role: incentivesCollector.DEFAULT_ADMIN_ROLE()
        });
        RBAC.RoleDescription memory incentivesCollectorManagerRole = RBAC.RoleDescription({
            contractName: "IncentivesCollector",
            contractAddr: _polAddresses.incentivesCollector,
            name: "MANAGER_ROLE",
            role: incentivesCollector.MANAGER_ROLE()
        });
        RBAC.RoleDescription memory incentivesCollectorPauserRole = RBAC.RoleDescription({
            contractName: "IncentivesCollector",
            contractAddr: _polAddresses.incentivesCollector,
            name: "PAUSER_ROLE",
            role: incentivesCollector.PAUSER_ROLE()
        });
        console2.log("Transferring ownership of IncentivesCollector contract...");
        _transferRole(incentivesCollectorPauserRole, deployer, governance);
        _transferRole(incentivesCollectorManagerRole, deployer, governance);
        _transferRole(incentivesCollectorAdminRole, deployer, governance);
    }

    function _loadStorageContracts() internal {
        _validateCode("WBERAStakerVault", _polAddresses.wberaStakerVault);
        _validateCode("IncentivesCollector", _polAddresses.incentivesCollector);
        wberaStakerVault = WBERAStakerVault(payable(_polAddresses.wberaStakerVault));
        incentivesCollector = IncentivesCollector(_polAddresses.incentivesCollector);
    }
}
