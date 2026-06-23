// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IncentivesCollector } from "src/pol/IncentivesCollector.sol";
import { BaseERC1967UpgradeScript } from "script/base/BaseUpgrade.s.sol";

contract UpgradeIncentivesCollectorScript is BaseERC1967UpgradeScript {
    function _proxyAddress() internal view override returns (address) {
        return _polAddresses.incentivesCollector;
    }

    function _deployNewImplementation() internal override returns (address) {
        return _deploy(
            "IncentivesCollector", type(IncentivesCollector).creationCode, _polAddresses.incentivesCollectorImpl
        );
    }
}
