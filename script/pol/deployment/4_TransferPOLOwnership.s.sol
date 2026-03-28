// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { RBAC } from "../../base/RBAC.sol";
import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";
import { AddressBook } from "../../base/AddressBook.sol";
import "../../base/Storage.sol";

contract TransferPOLOwnershipScript is RBAC, BaseScript, Storage, AddressBook {
    // Placeholder. Change before running the script.
    address internal constant NEW_OWNER = address(0); // TIMELOCK_ADDRESS;
    address internal constant VAULT_FACTORY_MANAGER = address(0);
    address internal constant FEE_COLLECTOR_MANAGER = address(0);

    function run() public virtual broadcast {
        // Check if the new owner and managers are set
        require(NEW_OWNER != address(0), "NEW_OWNER must be set");
        require(VAULT_FACTORY_MANAGER != address(0), "VAULT_FACTORY_MANAGER must be set");
        require(FEE_COLLECTOR_MANAGER != address(0), "FEE_COLLECTOR_MANAGER must be set");

        // create contracts instance from deployed addresses
        if (NEW_OWNER == _governanceAddresses.timelock) {
            _validateCode("TimeLock", NEW_OWNER);
        }
        _loadStorageContracts();

        console2.log("Transferring ownership of POL contracts...");
        transferPOLOwnership();

        console2.log("Transferring ownership of BGT fees contracts...");
        transferBGTFeesOwnership();
    }

    function transferPOLOwnership() internal {
        // BGT
        console2.log("Transferring ownership of BGT...");
        bgt.transferOwnership(NEW_OWNER);
        require(bgt.owner() == NEW_OWNER, "Ownership transfer failed for BGT");
        console2.log("Ownership of BGT transferred to:", NEW_OWNER);

        RBAC.AccountDescription memory governance = RBAC.AccountDescription({ name: "governance", addr: NEW_OWNER });

        RBAC.AccountDescription memory vaultFactoryManager =
            RBAC.AccountDescription({ name: "vaultFactoryManager", addr: VAULT_FACTORY_MANAGER });

        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        // RewardVaultFactory
        RBAC.RoleDescription memory rewardVaultFactoryAdminRole = RBAC.RoleDescription({
            contractName: "RewardVaultFactory",
            contractAddr: _polAddresses.rewardVaultFactory,
            name: "DEFAULT_ADMIN_ROLE",
            role: rewardVaultFactory.DEFAULT_ADMIN_ROLE()
        });
        RBAC.RoleDescription memory rewardVaultFactoryManagerRole = RBAC.RoleDescription({
            contractName: "RewardVaultFactory",
            contractAddr: _polAddresses.rewardVaultFactory,
            name: "VAULT_MANAGER_ROLE",
            role: rewardVaultFactory.VAULT_MANAGER_ROLE()
        });
        RBAC.RoleDescription memory rewardVaultFactoryPauserRole = RBAC.RoleDescription({
            contractName: "RewardVaultFactory",
            contractAddr: _polAddresses.rewardVaultFactory,
            name: "VAULT_PAUSER_ROLE",
            role: rewardVaultFactory.VAULT_PAUSER_ROLE()
        });

        _transferRole(rewardVaultFactoryPauserRole, deployer, vaultFactoryManager);
        _transferRole(rewardVaultFactoryManagerRole, deployer, vaultFactoryManager);
        _transferRole(rewardVaultFactoryAdminRole, deployer, governance);

        console2.log("Transferring ownership of RewardVault's Beacon...");
        UpgradeableBeacon beacon = UpgradeableBeacon(rewardVaultFactory.beacon());
        beacon.transferOwnership(NEW_OWNER);
        console2.log("Ownership of RewardVault's Beacon transferred to:", NEW_OWNER);

        // Berachef
        console2.log("Transferring ownership of Berachef...");
        beraChef.transferOwnership(NEW_OWNER);
        require(beraChef.owner() == NEW_OWNER, "Ownership transfer failed for Berachef");
        console2.log("Ownership of Berachef transferred to:", NEW_OWNER);

        // BlockRewardController
        console2.log("Transferring ownership of BlockRewardController...");
        blockRewardController.transferOwnership(NEW_OWNER);
        require(blockRewardController.owner() == NEW_OWNER, "Ownership transfer failed for BlockRewardController");
        console2.log("Ownership of BlockRewardController transferred to:", NEW_OWNER);

        // Distributor
        RBAC.RoleDescription memory distributorAdminRole = RBAC.RoleDescription({
            contractName: "Distributor",
            contractAddr: _polAddresses.distributor,
            name: "DEFAULT_ADMIN_ROLE",
            role: distributor.DEFAULT_ADMIN_ROLE()
        });

        _transferRole(distributorAdminRole, deployer, governance);
    }

    function transferBGTFeesOwnership() internal {
        // BGTStaker
        console2.log("Transferring ownership of BGTStaker...");
        bgtStaker.transferOwnership(NEW_OWNER);
        require(bgtStaker.owner() == NEW_OWNER, "Ownership transfer failed for BGTStaker");
        console2.log("Ownership of BGTStaker transferred to:", NEW_OWNER);

        // FeeCollector
        RBAC.RoleDescription memory feeCollectorAdminRole = RBAC.RoleDescription({
            contractName: "FeeCollector",
            contractAddr: _polAddresses.feeCollector,
            name: "DEFAULT_ADMIN_ROLE",
            role: feeCollector.DEFAULT_ADMIN_ROLE()
        });
        RBAC.RoleDescription memory feeCollectorManagerRole = RBAC.RoleDescription({
            contractName: "FeeCollector",
            contractAddr: _polAddresses.feeCollector,
            name: "MANAGER_ROLE",
            role: feeCollector.MANAGER_ROLE()
        });
        RBAC.RoleDescription memory feeCollectorPauserRole = RBAC.RoleDescription({
            contractName: "FeeCollector",
            contractAddr: _polAddresses.feeCollector,
            name: "PAUSER_ROLE",
            role: feeCollector.PAUSER_ROLE()
        });
        RBAC.AccountDescription memory governance = RBAC.AccountDescription({ name: "governance", addr: NEW_OWNER });
        RBAC.AccountDescription memory feeCollectorManager =
            RBAC.AccountDescription({ name: "feeCollectorManager", addr: FEE_COLLECTOR_MANAGER });
        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        _transferRole(feeCollectorPauserRole, deployer, feeCollectorManager);
        _transferRole(feeCollectorManagerRole, deployer, feeCollectorManager);
        _transferRole(feeCollectorAdminRole, deployer, governance);
    }

    function _loadStorageContracts() internal {
        _validateCode("BGT", _polAddresses.bgt);
        bgt = BGT(_polAddresses.bgt);
        _validateCode("BeraChef", _polAddresses.beraChef);
        beraChef = BeraChef(_polAddresses.beraChef);
        _validateCode("BlockRewardController", _polAddresses.blockRewardController);
        blockRewardController = BlockRewardController(_polAddresses.blockRewardController);
        _validateCode("Distributor", _polAddresses.distributor);
        distributor = Distributor(_polAddresses.distributor);
        _validateCode("RewardVaultFactory", _polAddresses.rewardVaultFactory);
        rewardVaultFactory = RewardVaultFactory(_polAddresses.rewardVaultFactory);
        _validateCode("BGTStaker", _polAddresses.bgtStaker);
        bgtStaker = BGTStaker(_polAddresses.bgtStaker);
        _validateCode("FeeCollector", _polAddresses.feeCollector);
        feeCollector = FeeCollector(_polAddresses.feeCollector);
    }
}
