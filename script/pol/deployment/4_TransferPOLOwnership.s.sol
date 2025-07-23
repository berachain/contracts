// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { RBAC } from "../../base/RBAC.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";
import { TIMELOCK_ADDRESS } from "../../gov/GovernanceAddresses.sol";
import {
    BGT_ADDRESS,
    BERACHEF_ADDRESS,
    BLOCK_REWARD_CONTROLLER_ADDRESS,
    DISTRIBUTOR_ADDRESS,
    REWARD_VAULT_FACTORY_ADDRESS,
    BGT_STAKER_ADDRESS,
    FEE_COLLECTOR_ADDRESS
} from "../POLAddresses.sol";
import "../../base/Storage.sol";

contract TransferPOLOwnershipScript is RBAC, BaseScript, Storage {
    // Placholder. Change before running the script.
    address internal constant NEW_OWNER = address(0); // TIMELOCK_ADDRESS;
    address internal constant VAULT_FACTORY_MANAGER = address(0);
    address internal constant DISTRIBUTOR_MANAGER = address(0);
    address internal constant FEE_COLLECTOR_MANAGER = address(0);

    function run() public virtual broadcast {
        // Check if the new owner and managers are set
        require(NEW_OWNER != address(0), "NEW_OWNER must be set");
        require(VAULT_FACTORY_MANAGER != address(0), "VAULT_FACTORY_MANAGER must be set");
        require(DISTRIBUTOR_MANAGER != address(0), "DISTRIBUTOR_MANAGER must be set");
        require(FEE_COLLECTOR_MANAGER != address(0), "FEE_COLLECTOR_MANAGER must be set");

        // create contracts instance from deployed addresses
        if (NEW_OWNER == TIMELOCK_ADDRESS) {
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

        RBAC.AccountDescription memory distributorManager =
            RBAC.AccountDescription({ name: "distributorManager", addr: DISTRIBUTOR_MANAGER });

        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        // RewardVaultFactory
        RBAC.RoleDescription memory rewardVaultFactoryAdminRole = RBAC.RoleDescription({
            contractName: "RewardVaultFactory",
            contractAddr: REWARD_VAULT_FACTORY_ADDRESS,
            name: "DEFAULT_ADMIN_ROLE",
            role: rewardVaultFactory.DEFAULT_ADMIN_ROLE()
        });
        RBAC.RoleDescription memory rewardVaultFactoryManagerRole = RBAC.RoleDescription({
            contractName: "RewardVaultFactory",
            contractAddr: REWARD_VAULT_FACTORY_ADDRESS,
            name: "VAULT_MANAGER_ROLE",
            role: rewardVaultFactory.VAULT_MANAGER_ROLE()
        });
        RBAC.RoleDescription memory rewardVaultFactoryPauserRole = RBAC.RoleDescription({
            contractName: "RewardVaultFactory",
            contractAddr: REWARD_VAULT_FACTORY_ADDRESS,
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
            contractAddr: DISTRIBUTOR_ADDRESS,
            name: "DEFAULT_ADMIN_ROLE",
            role: distributor.DEFAULT_ADMIN_ROLE()
        });

        // NOTE: the manager role on the distributor is not assigned to anyone, hence there is no need to revoke it.
        RBAC.RoleDescription memory distributorManagerRole = RBAC.RoleDescription({
            contractName: "Distributor",
            contractAddr: DISTRIBUTOR_ADDRESS,
            name: "MANAGER_ROLE",
            role: distributor.MANAGER_ROLE()
        });

        _transferRole(distributorManagerRole, deployer, distributorManager);
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
            contractAddr: FEE_COLLECTOR_ADDRESS,
            name: "DEFAULT_ADMIN_ROLE",
            role: feeCollector.DEFAULT_ADMIN_ROLE()
        });
        RBAC.RoleDescription memory feeCollectorManagerRole = RBAC.RoleDescription({
            contractName: "FeeCollector",
            contractAddr: FEE_COLLECTOR_ADDRESS,
            name: "MANAGER_ROLE",
            role: feeCollector.MANAGER_ROLE()
        });
        RBAC.RoleDescription memory feeCollectorPauserRole = RBAC.RoleDescription({
            contractName: "FeeCollector",
            contractAddr: FEE_COLLECTOR_ADDRESS,
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
        _validateCode("BGT", BGT_ADDRESS);
        bgt = BGT(BGT_ADDRESS);
        _validateCode("BeraChef", BERACHEF_ADDRESS);
        beraChef = BeraChef(BERACHEF_ADDRESS);
        _validateCode("BlockRewardController", BLOCK_REWARD_CONTROLLER_ADDRESS);
        blockRewardController = BlockRewardController(BLOCK_REWARD_CONTROLLER_ADDRESS);
        _validateCode("Distributor", DISTRIBUTOR_ADDRESS);
        distributor = Distributor(DISTRIBUTOR_ADDRESS);
        _validateCode("RewardVaultFactory", REWARD_VAULT_FACTORY_ADDRESS);
        rewardVaultFactory = RewardVaultFactory(REWARD_VAULT_FACTORY_ADDRESS);
        _validateCode("BGTStaker", BGT_STAKER_ADDRESS);
        bgtStaker = BGTStaker(BGT_STAKER_ADDRESS);
        _validateCode("FeeCollector", FEE_COLLECTOR_ADDRESS);
        feeCollector = FeeCollector(FEE_COLLECTOR_ADDRESS);
    }
}
