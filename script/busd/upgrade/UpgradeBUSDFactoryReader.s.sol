// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseDeployScript } from "../../base/BaseDeploy.s.sol";
import { AddressBook } from "../../base/AddressBook.sol";
import { BUSDFactoryReader } from "src/busd/BUSDFactoryReader.sol";

contract DeployBUSDFactoryReaderImplScript is BaseDeployScript, AddressBook {
    function run() public broadcast {
        _deploy("BUSDFactoryReader", type(BUSDFactoryReader).creationCode, _busdAddresses.busdFactoryReaderImpl);
    }

    /// @dev This function is only for testnet or test purposes.
    function upgradeToTestnet() public broadcast {
        console2.log("New BUSDFactoryReader implementation address:", _busdAddresses.busdFactoryReaderImpl);
        _validateCode("BUSDFactoryReader", _busdAddresses.busdFactoryReaderImpl);

        bytes memory callSignature;
        BUSDFactoryReader(_busdAddresses.busdFactoryReader)
            .upgradeToAndCall(_busdAddresses.busdFactoryReaderImpl, callSignature);
        console2.log("BUSDFactoryReader upgraded successfully");
    }
}
