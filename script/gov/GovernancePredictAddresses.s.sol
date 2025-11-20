// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BasePredictScript } from "../base/BasePredict.s.sol";
import { BerachainGovernance } from "src/gov/BerachainGovernance.sol";
import { TimeLock } from "src/gov/TimeLock.sol";

contract GovernancePredictAddressesScript is BasePredictScript {
    function run() public view {
        _predictProxyAddress("Governance", type(BerachainGovernance).creationCode);
        _predictProxyAddress("Timelock", type(TimeLock).creationCode);
    }
}
