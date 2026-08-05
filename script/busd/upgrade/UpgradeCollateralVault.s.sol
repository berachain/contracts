// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";
import { BaseDeployScript } from "../../base/BaseDeploy.s.sol";
import { CollateralVault } from "src/busd/CollateralVault.sol";
import { BUSDFactory } from "src/busd/BUSDFactory.sol";
import { AddressBook } from "../../base/AddressBook.sol";

contract DeployCollateralVaultImplScript is BaseDeployScript, AddressBook {
    function run() public broadcast {
        _deploy("CollateralVault", type(CollateralVault).creationCode, _busdAddresses.collateralVaultImpl);
    }

    /// @dev This function is only for testnet or test purposes.
    function upgradeToTestnet() public broadcast {
        console2.log("New CollateralVault implementation address:", _busdAddresses.collateralVaultImpl);
        _validateCode("CollateralVault", _busdAddresses.collateralVaultImpl);

        address beacon = BUSDFactory(_busdAddresses.busdFactory).beacon();
        UpgradeableBeacon(beacon).upgradeTo(_busdAddresses.collateralVaultImpl);
        console2.log("CollateralVault upgraded successfully");
    }
}
