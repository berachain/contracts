// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Script, console2 } from "forge-std/Script.sol";
import { Upgrades, Options } from "openzeppelin-foundry-upgrades/Upgrades.sol";

/// @notice This script is used to validate the upgrade of any upgradeable contract.
/// @dev This will fail if any storage collisions are detected.
/// @dev Need to run forge clean && forge compile before running this script.
contract ValidateHoneyUpgrade is Script {
    function run() public {
        vm.startBroadcast();
        // To validate the upgrade, we need to provide the upgraded contract name and the options
        // Either contract name should point to the deployed contract that is being upgraded using
        // @custom:oz-upgrades-from ContractV1
        // or `referenceContract` should be specified in the Options object.

        Options memory options; // create an empty options object.
        // check HoneyFactory safe upgrade
        // replace these version with the latest version to avoid too many upgrade check and hence getting `MemoryOOG`
        // error.
        options.referenceContract = "HoneyFactory_V1.sol:HoneyFactory_V1";
        Upgrades.validateUpgrade("HoneyFactory.sol", options);
        console2.log("HoneyFactory can be upgraded successfully.");

        // check collateral vault safe upgrade
        options.referenceContract = "CollateralVault_V1.sol:CollateralVault_V1";
        Upgrades.validateUpgrade("CollateralVault.sol", options);
        console2.log("CollateralVault can be upgraded successfully.");

        // check HoneyFactoryReader safe upgrade
        options.referenceContract = "HoneyFactoryReader_V0.sol:HoneyFactoryReader_V0";
        Upgrades.validateUpgrade("HoneyFactoryReader.sol", options);
        console2.log("HoneyFactoryReader can be upgraded successfully.");

        vm.stopBroadcast();
    }
}
