// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseDeployScript } from "../../base/BaseDeploy.s.sol";
import { BUSD } from "src/busd/BUSD.sol";
import { AddressBook } from "../../base/AddressBook.sol";

contract UpgradeBUSDImplScript is BaseDeployScript, AddressBook {
    function run() public broadcast {
        address newBUSDImpl = _deploy("BUSD Implementation", type(BUSD).creationCode, _busdAddresses.busdImpl);
        console2.log("BUSD implementation deployed successfully");
        console2.log("BUSD implementation address:", newBUSDImpl);
    }

    /// @dev This function is only for testnet or test purposes.
    function upgradeToTestnet() public broadcast {
        console2.log("New BUSD implementation address:", _busdAddresses.busdImpl);
        _validateCode("BUSD", _busdAddresses.busdImpl);

        bytes memory callSignature;
        BUSD(_busdAddresses.busd).upgradeToAndCall(_busdAddresses.busdImpl, callSignature);
        console2.log("BUSD upgraded successfully");
    }
}
