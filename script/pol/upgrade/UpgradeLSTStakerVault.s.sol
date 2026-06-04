// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { LSTStakerVault } from "src/pol/lst/LSTStakerVault.sol";
import { LSTStakerVaultFactory } from "src/pol/lst/LSTStakerVaultFactory.sol";
import { BaseBeaconUpgradeScript } from "script/base/BaseUpgrade.s.sol";

contract UpgradeLSTStakerVaultScript is BaseBeaconUpgradeScript {
    function _beaconAddress() internal view override returns (address) {
        return LSTStakerVaultFactory(_polAddresses.lstStakerVaultFactory).vaultBeacon();
    }

    function _deployNewImplementation() internal override returns (address) {
        return _deploy("LSTStakerVault", type(LSTStakerVault).creationCode, _polAddresses.lstStakerVaultImpl);
    }
}
