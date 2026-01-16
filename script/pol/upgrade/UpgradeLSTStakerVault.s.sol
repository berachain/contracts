// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";

import { AddressBook } from "script/base/AddressBook.sol";
import { BaseDeployScript } from "script/base/BaseDeploy.s.sol";
import { ChainHelper } from "script/base/Chain.sol";
import { LSTStakerVault } from "src/pol/lst/LSTStakerVault.sol";
import { LSTStakerVaultFactory } from "src/pol/lst/LSTStakerVaultFactory.sol";
import { LSTStakerVaultWithdrawalRequest } from "src/pol/lst/LSTStakerVaultWithdrawalRequest.sol";

contract UpgradeLSTStakerVaultScript is BaseDeployScript, AddressBook {
    function run() public pure {
        console2.log("Please run specific function.");
    }

    function deployNewVaultImplementation() public broadcast {
        address newLSTStakerVaultImpl = _deployVaultNewImpl();
        console2.log("New LSTStakerVault implementation address:", newLSTStakerVaultImpl);
    }

    function deployNewWithdrawal721Implementation() public broadcast {
        address newLSTStakerVaultWithdrawalRequestImpl = _deployWithdrawal721NewImpl();
        console2.log(
            "New LSTStakerVaultWithdrawalRequest implementation address:", newLSTStakerVaultWithdrawalRequestImpl
        );
    }

    /// @dev This function is only for testnet or test purposes.
    function vaultUpgradeToTestnet() public broadcast {
        LSTStakerVaultFactory factory = LSTStakerVaultFactory(_polAddresses.lstStakerVaultFactory);
        address beacon = factory.vaultBeacon();
        console2.log("Upgrading beacon at:", beacon);

        address newImpl = _deployVaultNewImpl();
        console2.log("New LSTStakerVault implementation address:", newImpl);
        UpgradeableBeacon(beacon).upgradeTo(newImpl);
        console2.log("LSTStakerVault upgraded successfully");
    }

    /// @dev This function is only for testnet or test purposes.
    function withdrawal721UpgradeToTestnet() public broadcast {
        LSTStakerVaultFactory factory = LSTStakerVaultFactory(_polAddresses.lstStakerVaultFactory);
        address beacon = factory.withdrawalBeacon();
        console2.log("Upgrading beacon at:", beacon);

        address newImpl = _deployWithdrawal721NewImpl();
        console2.log("New LSTStakerVaultWithdrawalRequest implementation address:", newImpl);
        UpgradeableBeacon(beacon).upgradeTo(newImpl);
        console2.log("LSTStakerVaultWithdrawalRequest upgraded successfully");
    }

    function _deployVaultNewImpl() internal returns (address) {
        return _deploy("LSTStakerVault", type(LSTStakerVault).creationCode, _polAddresses.lstStakerVaultImpl);
    }

    function _deployWithdrawal721NewImpl() internal returns (address) {
        return _deploy(
            "LSTStakerVaultWithdrawalRequest",
            type(LSTStakerVaultWithdrawalRequest).creationCode,
            _polAddresses.lstStakerVaultWithdrawalRequestImpl
        );
    }
}
