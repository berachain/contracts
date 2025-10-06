// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Script, console2 } from "forge-std/Script.sol";
import { Upgrades, Options } from "openzeppelin-foundry-upgrades/Upgrades.sol";

/// @notice This script is used to validate the upgrade of any upgradeable contract.
/// @dev This will fail if any storage collisions are detected.
/// @dev Need to run forge clean && forge compile before running this script.
contract ValidateWBERAStakerUpgrade is Script {
    function run() public {
        vm.startBroadcast();
        // To validate the upgrade, we need to provide the upgraded contract name and the options
        // Either contract name should point to the deployed contract that is being upgraded using
        // @custom:oz-upgrades-from ContractV1
        // or `referenceContract` should be specified in the Options object.

        Options memory options; // create an empty options object.
        options.referenceContract = "WBERAStakerVault_V0.sol:WBERAStakerVault_V0";

        Upgrades.validateUpgrade("WBERAStakerVault.sol", options);
        console2.log("WBERAStakerVault can be upgraded successfully.");
        vm.stopBroadcast();
    }
}
