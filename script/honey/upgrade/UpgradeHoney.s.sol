// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseDeployScript } from "../../base/BaseDeploy.s.sol";
import { Honey } from "src/honey/Honey.sol";
import { AddressBook } from "../../base/AddressBook.sol";

contract UpgradeHoneyImplScript is BaseDeployScript, AddressBook {
    constructor() AddressBook(_chainType) { }

    function run() public broadcast {
        address newHoneyImpl = _deploy("Honey Implementation", type(Honey).creationCode, _honeyAddresses.honeyImpl);
        console2.log("Honey implementation deployed successfully");
        console2.log("Honey implementation address:", newHoneyImpl);
    }

    /// @dev This function is only for testnet or test purposes.
    function upgradeToTestnet() public broadcast {
        console2.log("New Honey implementation address:", _honeyAddresses.honeyImpl);
        _validateCode("Honey", _honeyAddresses.honeyImpl);

        bytes memory callSignature;
        Honey(_honeyAddresses.honey).upgradeToAndCall(_honeyAddresses.honeyImpl, callSignature);
        console2.log("Honey upgraded successfully");
    }
}
