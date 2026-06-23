// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { RewardVaultHelper } from "src/pol/rewards/RewardVaultHelper.sol";
import { BaseERC1967UpgradeScript } from "../../base/BaseUpgrade.s.sol";

contract UpgradeRewardVaultHelperScript is BaseERC1967UpgradeScript {
    function _proxyAddress() internal view override returns (address) {
        return _polAddresses.rewardVaultHelper;
    }

    function _deployNewImplementation() internal override returns (address) {
        return _deploy("RewardVaultHelper", type(RewardVaultHelper).creationCode, _polAddresses.rewardVaultHelperImpl);
    }
}
