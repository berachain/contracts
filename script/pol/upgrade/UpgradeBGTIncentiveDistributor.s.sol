// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BGTIncentiveDistributor } from "src/pol/rewards/BGTIncentiveDistributor.sol";
import { BaseERC1967UpgradeScript } from "../../base/BaseUpgrade.s.sol";

contract UpgradeBGTIncentiveDistributorScript is BaseERC1967UpgradeScript {
    function _proxyAddress() internal view override returns (address) {
        return _polAddresses.bgtIncentiveDistributor;
    }

    function _deployNewImplementation() internal override returns (address) {
        return _deploy(
            "BGTIncentiveDistributor",
            type(BGTIncentiveDistributor).creationCode,
            _polAddresses.bgtIncentiveDistributorImpl
        );
    }
}
