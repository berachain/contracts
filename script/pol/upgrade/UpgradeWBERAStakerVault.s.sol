// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseDeployScript } from "../../base/BaseDeploy.s.sol";
import { WBERAStakerVault } from "src/pol/WBERAStakerVault.sol";

import { AddressBook } from "../../base/AddressBook.sol";

contract UpgradeWBERAStakerVaultScript is BaseDeployScript, AddressBook {
    constructor() AddressBook(_chainType) { }

    function run() public pure {
        console2.log("Please run specific function.");
    }

    function deployNewImplementation() public broadcast {
        address newWBERAStakerVaultImpl = _deployNewImplementation();
        console2.log("New WBERAStakerVault implementation address:", newWBERAStakerVaultImpl);
    }

    function printSetWithdrawalRequests721CallSignature() public view {
        console2.logBytes(
            abi.encodeCall(WBERAStakerVault.setWithdrawalRequests721, _polAddresses.wberaStakerVaultWithdrawalRequest)
        );
    }

    /// @dev This function is only for testnet or test purposes.
    function upgradeToAndCallTestnet(bytes memory callSignature) public broadcast {
        address newImpl = _deployNewImplementation();
        console2.log("New WBERAStakerVault implementation address:", newImpl);
        WBERAStakerVault(payable(_polAddresses.wberaStakerVault)).upgradeToAndCall(newImpl, callSignature);
        console2.log("WBERAStakerVault upgraded successfully");
    }

    function _deployNewImplementation() internal returns (address) {
        return _deploy("WBERAStakerVault", type(WBERAStakerVault).creationCode, _polAddresses.wberaStakerVaultImpl);
    }
}
