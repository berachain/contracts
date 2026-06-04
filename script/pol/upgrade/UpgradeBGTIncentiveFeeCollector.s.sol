// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BGTIncentiveFeeCollector } from "src/pol/BGTIncentiveFeeCollector.sol";
import { BaseERC1967UpgradeScript } from "script/base/BaseUpgrade.s.sol";

contract UpgradeBGTIncentiveFeeCollectorScript is BaseERC1967UpgradeScript {
    function _proxyAddress() internal view override returns (address) {
        return _polAddresses.bgtIncentiveFeeCollector;
    }

    function _deployNewImplementation() internal override returns (address) {
        return _deploy(
            "BGTIncentiveFeeCollector",
            type(BGTIncentiveFeeCollector).creationCode,
            _polAddresses.bgtIncentiveFeeCollectorImpl
        );
    }
}
