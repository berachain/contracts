// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseDeployScript } from "../../base/BaseDeploy.s.sol";
import { AddressBook } from "../../base/AddressBook.sol";
import { HoneyFactoryReader } from "src/honey/HoneyFactoryReader.sol";

contract DeployHoneyFactoryReaderImplScript is BaseDeployScript, AddressBook {
    function run() public broadcast {
        _deploy("HoneyFactoryReader", type(HoneyFactoryReader).creationCode, _honeyAddresses.honeyFactoryReaderImpl);
    }

    /// @dev This function is only for testnet or test purposes.
    function upgradeToTestnet() public broadcast {
        console2.log("New HoneyFactoryReader implementation address:", _honeyAddresses.honeyFactoryReaderImpl);
        _validateCode("HoneyFactoryReader", _honeyAddresses.honeyFactoryReaderImpl);

        bytes memory callSignature;
        HoneyFactoryReader(_honeyAddresses.honeyFactoryReader)
            .upgradeToAndCall(_honeyAddresses.honeyFactoryReaderImpl, callSignature);
        console2.log("HoneyFactoryReader upgraded successfully");
    }
}
