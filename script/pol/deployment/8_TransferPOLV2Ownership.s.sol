// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { RBAC } from "../../base/RBAC.sol";
import { TIMELOCK_ADDRESS } from "../../gov/GovernanceAddresses.sol";
import { WBERA_STAKER_VAULT_ADDRESS, BGT_INCENTIVE_FEE_COLLECTOR_ADDRESS } from "../POLAddresses.sol";
import "../../base/Storage.sol";

contract TransferPOLV2OwnershipScript is RBAC, BaseScript, Storage {
    function run() public pure {
        console2.log("Please run specific function.");
    }

    function transferPOLV2Ownership(address newOwner) public broadcast {
        console2.log("Transferring ownership of POLV2 contracts...");
        // Check if the new owner is set
        require(newOwner != address(0), "NEW_OWNER must be set");
        console2.log("NEW_OWNER", newOwner);

        // create contracts instance from deployed addresses
        if (newOwner == TIMELOCK_ADDRESS) {
            _validateCode("TimeLock", newOwner);
        }
        _loadStorageContracts();

        RBAC.AccountDescription memory governance = RBAC.AccountDescription({ name: "governance", addr: newOwner });
        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        _transferWBERAStakerVaultOwnership(deployer, governance);
        _transferBGTIncentiveFeeCollectorOwnership(deployer, governance);
    }

    function _transferWBERAStakerVaultOwnership(
        RBAC.AccountDescription memory deployer,
        RBAC.AccountDescription memory governance
    )
        internal
    {
        RBAC.RoleDescription memory wberaStakerVaultAdminRole = RBAC.RoleDescription({
            contractName: "WBERAStakerVault",
            contractAddr: WBERA_STAKER_VAULT_ADDRESS,
            name: "DEFAULT_ADMIN_ROLE",
            role: wberaStakerVault.DEFAULT_ADMIN_ROLE()
        });
        RBAC.RoleDescription memory wberaStakerVaultManagerRole = RBAC.RoleDescription({
            contractName: "WBERAStakerVault",
            contractAddr: WBERA_STAKER_VAULT_ADDRESS,
            name: "MANAGER_ROLE",
            role: wberaStakerVault.MANAGER_ROLE()
        });
        RBAC.RoleDescription memory wberaStakerVaultPauserRole = RBAC.RoleDescription({
            contractName: "WBERAStakerVault",
            contractAddr: WBERA_STAKER_VAULT_ADDRESS,
            name: "PAUSER_ROLE",
            role: wberaStakerVault.PAUSER_ROLE()
        });
        console2.log("Transferring ownership of WBERAStakerVault contract...");
        _transferRole(wberaStakerVaultPauserRole, deployer, governance);
        _transferRole(wberaStakerVaultManagerRole, deployer, governance);
        _transferRole(wberaStakerVaultAdminRole, deployer, governance);
    }

    function _transferBGTIncentiveFeeCollectorOwnership(
        RBAC.AccountDescription memory deployer,
        RBAC.AccountDescription memory governance
    )
        internal
    {
        RBAC.RoleDescription memory bgtIncentiveFeeCollectorAdminRole = RBAC.RoleDescription({
            contractName: "BGTIncentiveFeeCollector",
            contractAddr: BGT_INCENTIVE_FEE_COLLECTOR_ADDRESS,
            name: "DEFAULT_ADMIN_ROLE",
            role: bgtIncentiveFeeCollector.DEFAULT_ADMIN_ROLE()
        });
        RBAC.RoleDescription memory bgtIncentiveFeeCollectorManagerRole = RBAC.RoleDescription({
            contractName: "BGTIncentiveFeeCollector",
            contractAddr: BGT_INCENTIVE_FEE_COLLECTOR_ADDRESS,
            name: "MANAGER_ROLE",
            role: bgtIncentiveFeeCollector.MANAGER_ROLE()
        });
        RBAC.RoleDescription memory bgtIncentiveFeeCollectorPauserRole = RBAC.RoleDescription({
            contractName: "BGTIncentiveFeeCollector",
            contractAddr: BGT_INCENTIVE_FEE_COLLECTOR_ADDRESS,
            name: "PAUSER_ROLE",
            role: bgtIncentiveFeeCollector.PAUSER_ROLE()
        });
        console2.log("Transferring ownership of BGTIncentiveFeeCollector contract...");
        _transferRole(bgtIncentiveFeeCollectorPauserRole, deployer, governance);
        _transferRole(bgtIncentiveFeeCollectorManagerRole, deployer, governance);
        _transferRole(bgtIncentiveFeeCollectorAdminRole, deployer, governance);
    }

    function _loadStorageContracts() internal {
        _validateCode("WBERAStakerVault", WBERA_STAKER_VAULT_ADDRESS);
        _validateCode("BGTIncentiveFeeCollector", BGT_INCENTIVE_FEE_COLLECTOR_ADDRESS);
        wberaStakerVault = WBERAStakerVault(payable(WBERA_STAKER_VAULT_ADDRESS));
        bgtIncentiveFeeCollector = BGTIncentiveFeeCollector(BGT_INCENTIVE_FEE_COLLECTOR_ADDRESS);
    }
}
