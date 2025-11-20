// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/console2.sol";
import { BaseScript } from "../base/Base.s.sol";
import { BeaconDeposit } from "src/pol/BeaconDeposit.sol";

/// @dev Only for local deployment
/// @dev This contract is deployed during genesis, it doesn't need to be deployed
contract DeployBeaconDepositScript is BaseScript {
    function run() public pure {
        console2.log("This is a genesis contract, it doesn't need to be deployed");
    }

    function deployBeaconDeposit() public broadcast {
        BeaconDeposit beaconDeposit = new BeaconDeposit();
        console2.log("BeaconDeposit deployed at:", address(beaconDeposit));
    }
}
