// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseDeployScript } from "../../base/BaseDeploy.s.sol";
import { BGTIncentiveFeeCollector } from "src/pol/BGTIncentiveFeeCollector.sol";
import { AddressBook } from "../../base/AddressBook.sol";

contract UpgradeBGTIncentiveFeeCollectorScript is BaseDeployScript, AddressBook {
    constructor() AddressBook(_chainType) { }

    function run() public pure {
        console2.log("Please run specific function.");
    }

    function deployNewImplementation() public broadcast {
        address newBGTIncentiveFeeCollectorImpl = _deployNewImplementation();
        console2.log("New BGTIncentiveFeeCollector implementation address:", newBGTIncentiveFeeCollectorImpl);
    }

    /// @dev This function is only for testnet or test purposes.
    function upgradeToTestnet() public broadcast {
        address newBGTIncentiveFeeCollectorImpl = _deployNewImplementation();
        console2.log("New BGTIncentiveFeeCollector implementation address:", newBGTIncentiveFeeCollectorImpl);
        BGTIncentiveFeeCollector(_polAddresses.bgtIncentiveFeeCollector)
            .upgradeToAndCall(newBGTIncentiveFeeCollectorImpl, bytes(""));
        console2.log("BGTIncentiveFeeCollector upgraded successfully");
    }

    function _deployNewImplementation() internal returns (address) {
        return _deploy(
            "BGTIncentiveFeeCollector",
            type(BGTIncentiveFeeCollector).creationCode,
            _polAddresses.bgtIncentiveFeeCollectorImpl
        );
    }
}
