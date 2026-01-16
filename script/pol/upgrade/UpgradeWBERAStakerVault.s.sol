// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseDeployScript } from "../../base/BaseDeploy.s.sol";
import { WBERAStakerVault } from "src/pol/WBERAStakerVault.sol";
import { ChainHelper } from "script/base/Chain.sol";
import { WBERAStakerVaultWithdrawalRequest } from "src/pol/WBERAStakerVaultWithdrawalRequest.sol";

import { AddressBook } from "script/base/AddressBook.sol";

contract UpgradeWBERAStakerVaultScript is BaseDeployScript, AddressBook {
    function run() public pure {
        console2.log("Please run specific function.");
    }

    function deployNewVaultImplementation() public broadcast {
        address newWBERAStakerVaultImpl = _deployVaultNewImpl();
        console2.log("New WBERAStakerVault implementation address:", newWBERAStakerVaultImpl);
    }

    function deployNewWithdrawal721Implementation() public broadcast {
        address newWBERAStakerVaultWithdrawalRequestImpl = _deployWithdrawal721NewImpl();
        console2.log(
            "New WBERAStakerVaultWithdrawalRequest implementation address:", newWBERAStakerVaultWithdrawalRequestImpl
        );
    }

    function printSetWithdrawalRequests721CallSignature() public view {
        console2.logBytes(
            abi.encodeCall(WBERAStakerVault.setWithdrawalRequests721, _polAddresses.wberaStakerVaultWithdrawalRequest)
        );
    }

    /// @dev This function is only for testnet or test purposes.
    function upgradeToAndCallTestnet(bytes memory callSignature) public broadcast {
        address newImpl = _deployVaultNewImpl();
        console2.log("New WBERAStakerVault implementation address:", newImpl);
        WBERAStakerVault(payable(_polAddresses.wberaStakerVault)).upgradeToAndCall(newImpl, callSignature);
        console2.log("WBERAStakerVault upgraded successfully");
    }

    function _deployVaultNewImpl() internal returns (address) {
        return _deploy("WBERAStakerVault", type(WBERAStakerVault).creationCode, _polAddresses.wberaStakerVaultImpl);
    }

    function _deployWithdrawal721NewImpl() internal returns (address) {
        return _deploy(
            "WBERAStakerVaultWithdrawalRequest",
            type(WBERAStakerVaultWithdrawalRequest).creationCode,
            _polAddresses.wberaStakerVaultWithdrawalRequestImpl
        );
    }
}
