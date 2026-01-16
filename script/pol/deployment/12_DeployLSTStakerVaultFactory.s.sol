// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";

import { AddressBook } from "script/base/AddressBook.sol";
import { BaseScript } from "script/base/Base.s.sol";
import { ChainHelper } from "script/base/Chain.sol";
import { RBAC } from "script/base/RBAC.sol";
import { Storage } from "script/base/Storage.sol";

import { MockTestnetLSTDeployer } from "test/mock/pol/lst/MockTestnetLST.sol";
import { LSTStakerVault } from "src/pol/lst/LSTStakerVault.sol";
import { LSTStakerVaultFactory } from "src/pol/lst/LSTStakerVaultFactory.sol";
import { LSTStakerVaultFactoryDeployer } from "src/pol/lst/LSTStakerVaultFactoryDeployer.sol";
import { LSTStakerVaultWithdrawalRequest } from "src/pol/lst/LSTStakerVaultWithdrawalRequest.sol";
import { InfraredBeraAdapter } from "src/pol/lst/InfraredBeraAdapter.sol";

contract DeployLSTStakerVaultFactoryScript is BaseScript, RBAC, Storage, AddressBook {
    // Placeholder. Change before running the transferFactoryOwnership function.
    address internal constant NEW_OWNER = address(0);
    address internal constant VAULT_FACTORY_MANAGER = address(0);

    function run() public pure {
        console2.log("Please run specific function.");
    }

    function deployFactory(address governance) public broadcast {
        console2.log("\n\nDeploying LSTStakerVaultFactory...");

        LSTStakerVaultFactoryDeployer deployerContract = new LSTStakerVaultFactoryDeployer(
            governance,
            _saltsForProxy(type(LSTStakerVaultFactory).creationCode),
            _salt(type(LSTStakerVault).creationCode),
            _salt(type(LSTStakerVaultWithdrawalRequest).creationCode)
        );

        lstStakerVaultFactory = deployerContract.lstVaultFactory();
        _checkDeploymentAddress(
            "LSTStakerVaultFactory", address(lstStakerVaultFactory), _polAddresses.lstStakerVaultFactory
        );
    }

    function deployInfraredBeraAdapter() public broadcast {
        console2.log("\n\nDeploying InfraredBeraAdapter...");

        address adapter = address(new InfraredBeraAdapter());
        console2.log("InfraredBeraAdapter deployed at:", adapter);
    }

    function transferFactoryOwnership() public broadcast {
        console2.log("\n\nTransferring roles of LSTStakerVaultFactory...");

        _loadAccounts();
        _loadStorageContracts();

        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });
        RBAC.AccountDescription memory governance = RBAC.AccountDescription({ name: "governance", addr: NEW_OWNER });
        RBAC.AccountDescription memory vaultFactoryManager =
            RBAC.AccountDescription({ name: "vaultFactoryManager", addr: VAULT_FACTORY_MANAGER });

        RBAC.RoleDescription memory lstStakerVaultFactoryAdminRole = RBAC.RoleDescription({
            contractName: "LSTStakerVaultFactory",
            contractAddr: _polAddresses.lstStakerVaultFactory,
            name: "DEFAULT_ADMIN_ROLE",
            role: lstStakerVaultFactory.DEFAULT_ADMIN_ROLE()
        });
        RBAC.RoleDescription memory lstStakerVaultFactoryManagerRole = RBAC.RoleDescription({
            contractName: "LSTStakerVaultFactory",
            contractAddr: _polAddresses.lstStakerVaultFactory,
            name: "VAULT_MANAGER_ROLE",
            role: lstStakerVaultFactory.VAULT_MANAGER_ROLE()
        });
        RBAC.RoleDescription memory lstStakerVaultFactoryPauserRole = RBAC.RoleDescription({
            contractName: "LSTStakerVaultFactory",
            contractAddr: _polAddresses.lstStakerVaultFactory,
            name: "VAULT_PAUSER_ROLE",
            role: lstStakerVaultFactory.VAULT_PAUSER_ROLE()
        });

        _transferRole(lstStakerVaultFactoryPauserRole, deployer, vaultFactoryManager);
        _transferRole(lstStakerVaultFactoryManagerRole, deployer, vaultFactoryManager);
        _transferRole(lstStakerVaultFactoryAdminRole, deployer, governance);

        console2.log("\n\nTransferring ownership of LSTStakerVaultFactory beacons...");

        LSTStakerVaultFactory factory = LSTStakerVaultFactory(_polAddresses.lstStakerVaultFactory);
        UpgradeableBeacon vaultBeacon = UpgradeableBeacon(factory.vaultBeacon());
        UpgradeableBeacon withdrawalBeacon = UpgradeableBeacon(factory.withdrawalBeacon());
        vaultBeacon.transferOwnership(NEW_OWNER);
        withdrawalBeacon.transferOwnership(NEW_OWNER);
    }

    function deployMockTestnetLST() public broadcast {
        console2.log("\n\nDeploying MockTestnetLST...");

        MockTestnetLSTDeployer deployer = new MockTestnetLSTDeployer(msg.sender);
        console2.log("MockTestnetLST deployed at:", deployer.lst());
    }

    function _loadAccounts() internal view {
        // Check if the new owner and manager are set
        require(NEW_OWNER != address(0), "NEW_OWNER must be set");
        require(VAULT_FACTORY_MANAGER != address(0), "VAULT_FACTORY_MANAGER must be set");

        // Create contracts instance from deployed addresses
        if (NEW_OWNER == _governanceAddresses.timelock) {
            _validateCode("TimeLock", NEW_OWNER);
        }
    }

    function _loadStorageContracts() internal {
        _validateCode("LSTStakerVaultFactory", _polAddresses.lstStakerVaultFactory);
        lstStakerVaultFactory = LSTStakerVaultFactory(_polAddresses.lstStakerVaultFactory);
    }
}
