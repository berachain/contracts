// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { FeeCollector } from "src/pol/FeeCollector.sol";
import { BaseERC1967UpgradeScript } from "script/base/BaseUpgrade.s.sol";

contract UpgradeFeeCollectorScript is BaseERC1967UpgradeScript {
    function _proxyAddress() internal view override returns (address) {
        return _polAddresses.feeCollector;
    }

    function _deployNewImplementation() internal override returns (address) {
        return _deploy("FeeCollector", type(FeeCollector).creationCode, _polAddresses.feeCollectorImpl);
    }
}
