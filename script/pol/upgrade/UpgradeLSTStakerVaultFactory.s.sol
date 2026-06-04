// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { LSTStakerVaultFactory } from "src/pol/lst/LSTStakerVaultFactory.sol";
import { BaseERC1967UpgradeScript } from "script/base/BaseUpgrade.s.sol";

contract UpgradeLSTStakerVaultFactoryScript is BaseERC1967UpgradeScript {
    function _proxyAddress() internal view override returns (address) {
        return _polAddresses.lstStakerVaultFactory;
    }

    function _deployNewImplementation() internal override returns (address) {
        return _deploy(
            "LSTStakerVaultFactory", type(LSTStakerVaultFactory).creationCode, _polAddresses.lstStakerVaultFactoryImpl
        );
    }
}
