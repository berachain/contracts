// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { LSTStakerVaultFactory } from "src/pol/lst/LSTStakerVaultFactory.sol";
import { LSTStakerVaultWithdrawalRequest } from "src/pol/lst/LSTStakerVaultWithdrawalRequest.sol";
import { BaseBeaconUpgradeScript } from "script/base/BaseUpgrade.s.sol";

contract UpgradeLSTStakerVaultWithdrawalRequestScript is BaseBeaconUpgradeScript {
    function _beaconAddress() internal view override returns (address) {
        return LSTStakerVaultFactory(_polAddresses.lstStakerVaultFactory).withdrawalBeacon();
    }

    function _deployNewImplementation() internal override returns (address) {
        return _deploy(
            "LSTStakerVaultWithdrawalRequest",
            type(LSTStakerVaultWithdrawalRequest).creationCode,
            _polAddresses.lstStakerVaultWithdrawalRequestImpl
        );
    }
}
