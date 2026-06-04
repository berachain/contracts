// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BeraChef } from "src/pol/rewards/BeraChef.sol";
import { BaseERC1967UpgradeScript } from "../../base/BaseUpgrade.s.sol";

contract UpgradeBeraChefScript is BaseERC1967UpgradeScript {
    // Equal to MAX_COMMISSION_CHANGE_DELAY
    uint64 constant COMMISSION_CHANGE_DELAY = 2 * 8191;
    uint64 constant STARTING_VALUE_MAX_WEIGHT_PER_VAULT = 1e4;

    function printSetCommissionChangeDelayCallSignature() public pure {
        console2.logBytes(abi.encodeCall(BeraChef.setCommissionChangeDelay, (COMMISSION_CHANGE_DELAY)));
    }

    function printSetMaxWeightPerVaultCallSignature() public pure {
        console2.logBytes(abi.encodeCall(BeraChef.setMaxWeightPerVault, (STARTING_VALUE_MAX_WEIGHT_PER_VAULT)));
    }

    function _proxyAddress() internal view override returns (address) {
        return _polAddresses.beraChef;
    }

    function _deployNewImplementation() internal override returns (address) {
        return _deploy("BeraChef", type(BeraChef).creationCode, _polAddresses.beraChefImpl);
    }
}
