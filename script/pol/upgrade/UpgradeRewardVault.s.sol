// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { RewardVault } from "src/pol/rewards/RewardVault.sol";
import { RewardVaultFactory } from "src/pol/rewards/RewardVaultFactory.sol";
import { BaseBeaconUpgradeScript } from "../../base/BaseUpgrade.s.sol";

contract UpgradeRewardVaultScript is BaseBeaconUpgradeScript {
    function _beaconAddress() internal view override returns (address) {
        return RewardVaultFactory(_polAddresses.rewardVaultFactory).beacon();
    }

    function _deployNewImplementation() internal override returns (address) {
        return _deploy("RewardVault", type(RewardVault).creationCode, _polAddresses.rewardVaultImpl);
    }
}
