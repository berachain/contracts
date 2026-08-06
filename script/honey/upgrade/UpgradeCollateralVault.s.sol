// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";
import { BaseDeployScript } from "../../base/BaseDeploy.s.sol";
import { CollateralVault } from "src/honey/CollateralVault.sol";
import { HoneyFactory } from "src/honey/HoneyFactory.sol";
import { AddressBook } from "../../base/AddressBook.sol";

contract DeployCollateralVaultImplScript is BaseDeployScript, AddressBook {
    function run() public broadcast {
        _deploy("CollateralVault", type(CollateralVault).creationCode, _honeyAddresses.collateralVaultImpl);
    }

    /// @dev This function is only for testnet or test purposes.
    function upgradeToTestnet() public broadcast {
        console2.log("New CollateralVault implementation address:", _honeyAddresses.collateralVaultImpl);
        _validateCode("CollateralVault", _honeyAddresses.collateralVaultImpl);

        address beacon = HoneyFactory(_honeyAddresses.honeyFactory).beacon();
        UpgradeableBeacon(beacon).upgradeTo(_honeyAddresses.collateralVaultImpl);
        console2.log("CollateralVault upgraded successfully");
    }
}
