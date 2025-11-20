// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseDeployScript } from "../../base/BaseDeploy.s.sol";
import { AddressBook } from "../../base/AddressBook.sol";
import { HoneyFactory } from "src/honey/HoneyFactory.sol";

contract DeployHoneyFactoryImplScript is BaseDeployScript, AddressBook {
    constructor() AddressBook(_chainType) { }

    function run() public broadcast {
        _deploy("HoneyFactory", type(HoneyFactory).creationCode, _honeyAddresses.honeyFactoryImpl);
    }

    /// @dev This function is only for testnet or test purposes.
    function upgradeToTestnet() public broadcast {
        console2.log("New HoneyFactory implementation address:", _honeyAddresses.honeyFactoryImpl);
        _validateCode("HoneyFactory", _honeyAddresses.honeyFactoryImpl);

        bytes memory callSignature;
        HoneyFactory(_honeyAddresses.honeyFactory).upgradeToAndCall(_honeyAddresses.honeyFactoryImpl, callSignature);
        console2.log("HoneyFactory upgraded successfully");
    }
}
