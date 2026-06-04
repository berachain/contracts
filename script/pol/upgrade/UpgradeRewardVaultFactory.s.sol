// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { RewardVaultFactory } from "src/pol/rewards/RewardVaultFactory.sol";
import { BaseERC1967UpgradeScript } from "../../base/BaseUpgrade.s.sol";

contract UpgradeRewardVaultFactoryScript is BaseERC1967UpgradeScript {
    function _proxyAddress() internal view override returns (address) {
        return _polAddresses.rewardVaultFactory;
    }

    function _deployNewImplementation() internal override returns (address) {
        return
            _deploy("RewardVaultFactory", type(RewardVaultFactory).creationCode, _polAddresses.rewardVaultFactoryImpl);
    }
}
