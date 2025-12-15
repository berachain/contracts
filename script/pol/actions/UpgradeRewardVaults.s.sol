// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { Storage } from "../../base/Storage.sol";
import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";
import { RewardVaultFactory } from "src/pol/rewards/RewardVaultFactory.sol";
import { RewardVault } from "src/pol/rewards/RewardVault.sol";
import { AddressBook } from "../../base/AddressBook.sol";

contract UpgradeRewardVaults is BaseScript, Storage, AddressBook {
    function run() public virtual broadcast {
        rewardVaultFactory = RewardVaultFactory(_polAddresses.rewardVaultFactory);
        upgradeRewardVaults(rewardVaultFactory);
    }

    function upgradeRewardVaults(RewardVaultFactory _rewardVaultFactory) internal {
        UpgradeableBeacon beacon = UpgradeableBeacon(_rewardVaultFactory.beacon());
        console2.log("Beacon address: ", address(beacon));
        console2.log("Original implementation: ", beacon.implementation());
        beacon.upgradeTo(address(new RewardVault()));
        console2.log("Upgraded to: ", beacon.implementation());
    }
}
