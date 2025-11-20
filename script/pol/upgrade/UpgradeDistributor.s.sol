// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseDeployScript } from "../../base/BaseDeploy.s.sol";
import { Distributor } from "src/pol/rewards/Distributor.sol";

import { AddressBook } from "../../base/AddressBook.sol";

contract UpgradeDistributorScript is BaseDeployScript, AddressBook {
    constructor() AddressBook(_chainType) { }

    function run() public pure {
        console2.log("Please run specific function.");
    }

    function deployNewImplementation() public broadcast {
        address newDistributorImpl = _deployNewImplementation();
        console2.log("New Distributor implementation address:", newDistributorImpl);
    }

    /// @dev This function is only for testnet or test purposes.
    function upgradeToAndCallTestnet(bytes memory callSignature) public broadcast {
        address newDistributorImpl = _deployNewImplementation();
        console2.log("New Distributor implementation address:", newDistributorImpl);
        Distributor(_polAddresses.distributor).upgradeToAndCall(newDistributorImpl, callSignature);
        console2.log("Distributor upgraded successfully");
    }

    function _deployNewImplementation() internal returns (address) {
        return _deploy("Distributor", type(Distributor).creationCode, _polAddresses.distributorImpl);
    }
}
