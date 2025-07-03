// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Script, console2 } from "forge-std/Script.sol";
import { Upgrades, Options } from "openzeppelin-foundry-upgrades/Upgrades.sol";

/// @notice This script is used to validate the upgrade of any upgradeable contract.
/// @dev This will fail if any storage collisions are detected.
/// @dev Need to run forge clean && forge compile before running this script.
contract ValidatePOLUpgrade is Script {
    function run() public {
        vm.startBroadcast();
        // To validate the upgrade, we need to provide the upgraded contract name and the options
        // Either contract name should point to the deployed contract that is being upgraded using
        // @custom:oz-upgrades-from ContractV1
        // or `referenceContract` should be specified in the Options object.

        Options memory options; // create an empty options object.
        // Allow state variable renaming.
        options.unsafeAllowRenames = true;
        // replace these version with the latest version to avoid too many upgrade check
        // and hence getting `MemoryOOG` error.
        options.referenceContract = "RewardVault_V6.sol:RewardVault_V6";

        Upgrades.validateUpgrade("RewardVault.sol", options);
        console2.log("RewardVault can be upgraded successfully.");

        // Check RewardVaultFactory safe upgrade
        options.referenceContract = "RewardVaultFactory_V0.sol:RewardVaultFactory_V0";
        Upgrades.validateUpgrade("RewardVaultFactory.sol", options);
        console2.log("RewardVaultFactory can be upgraded successfully.");
        vm.stopBroadcast();
    }
}
