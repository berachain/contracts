// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BlockRewardController } from "src/pol/rewards/BlockRewardController.sol";
import { BaseERC1967UpgradeScript } from "../../base/BaseUpgrade.s.sol";

contract UpgradeBlockRewardControllerScript is BaseERC1967UpgradeScript {
    function _proxyAddress() internal view override returns (address) {
        return _polAddresses.blockRewardController;
    }

    function _deployNewImplementation() internal override returns (address) {
        return _deploy(
            "BlockRewardController", type(BlockRewardController).creationCode, _polAddresses.blockRewardControllerImpl
        );
    }
}
