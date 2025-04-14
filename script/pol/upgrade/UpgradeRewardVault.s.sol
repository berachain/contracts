// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";

import { BaseScript } from "../../base/Base.s.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { RewardVault } from "src/pol/rewards/RewardVault.sol";
import { RewardVaultFactory } from "src/pol/rewards/RewardVaultFactory.sol";
import { REWARD_VAULT_FACTORY_ADDRESS } from "../POLAddresses.sol";

contract UpgradeRewardVaultScript is BaseScript, Create2Deployer {
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

        address beacon = RewardVaultFactory(REWARD_VAULT_FACTORY_ADDRESS).beacon();
        UpgradeableBeacon(beacon).upgradeTo(newRewardVaultImpl);
        console2.log("RewardVault upgraded successfully");
    }

    function _deployNewImplementation() internal returns (address) {
        return deployWithCreate2(0, type(RewardVault).creationCode);
    }
}
