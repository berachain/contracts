// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseDeployScript } from "../../base/BaseDeploy.s.sol";
import { AddressBook } from "../../base/AddressBook.sol";
import { BUSDFactory } from "src/busd/BUSDFactory.sol";

contract DeployBUSDFactoryImplScript is BaseDeployScript, AddressBook {
    function run() public broadcast {
        _deploy("BUSDFactory", type(BUSDFactory).creationCode, _busdAddresses.busdFactoryImpl);
    }

    /// @dev This function is only for testnet or test purposes.
    function upgradeToTestnet() public broadcast {
        console2.log("New BUSDFactory implementation address:", _busdAddresses.busdFactoryImpl);
        _validateCode("BUSDFactory", _busdAddresses.busdFactoryImpl);

        bytes memory callSignature;
        BUSDFactory(_busdAddresses.busdFactory).upgradeToAndCall(_busdAddresses.busdFactoryImpl, callSignature);
        console2.log("BUSDFactory upgraded successfully");
    }
}
