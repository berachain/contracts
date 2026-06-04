// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { DedicatedEmissionStreamManager } from "src/pol/rewards/DedicatedEmissionStreamManager.sol";
import { BaseERC1967UpgradeScript } from "script/base/BaseUpgrade.s.sol";

contract UpgradeDedicatedEmissionStreamManagerScript is BaseERC1967UpgradeScript {
    function _proxyAddress() internal view override returns (address) {
        return _polAddresses.dedicatedEmissionStreamManager;
    }

    function _deployNewImplementation() internal override returns (address) {
        return _deploy(
            "DedicatedEmissionStreamManager",
            type(DedicatedEmissionStreamManager).creationCode,
            _polAddresses.dedicatedEmissionStreamManagerImpl
        );
    }
}
