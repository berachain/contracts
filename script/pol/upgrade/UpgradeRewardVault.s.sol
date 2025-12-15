// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";

import { BaseDeployScript } from "../../base/BaseDeploy.s.sol";
import { RewardVault } from "src/pol/rewards/RewardVault.sol";
import { RewardVaultFactory } from "src/pol/rewards/RewardVaultFactory.sol";
import { AddressBook } from "../../base/AddressBook.sol";

contract UpgradeRewardVaultScript is BaseDeployScript, AddressBook {
    function run() public pure {
        console2.log("Please run specific function.");
    }

    function deployNewImplementation() public broadcast {
        address newRewardVaultImpl = _deployNewImplementation();
        console2.log("New rewardVault implementation address:", newRewardVaultImpl);
    }

    /// @dev This function is only for testnet or test purposes.
    function upgradeToTestnet() public broadcast {
        address newRewardVaultImpl = _deployNewImplementation();
        console2.log("New rewardVault implementation address:", newRewardVaultImpl);

        address beacon = RewardVaultFactory(_polAddresses.rewardVaultFactory).beacon();
        UpgradeableBeacon(beacon).upgradeTo(newRewardVaultImpl);
        console2.log("RewardVault upgraded successfully");
    }

    function _deployNewImplementation() internal returns (address) {
        return _deploy("RewardVault", type(RewardVault).creationCode, _polAddresses.rewardVaultImpl);
    }
}
