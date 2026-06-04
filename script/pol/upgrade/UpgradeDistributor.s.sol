// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Distributor } from "src/pol/rewards/Distributor.sol";
import { BaseERC1967UpgradeScript } from "../../base/BaseUpgrade.s.sol";

contract UpgradeDistributorScript is BaseERC1967UpgradeScript {
    function _proxyAddress() internal view override returns (address) {
        return _polAddresses.distributor;
    }

    function _deployNewImplementation() internal override returns (address) {
        return _deploy("Distributor", type(Distributor).creationCode, _polAddresses.distributorImpl);
    }
}
