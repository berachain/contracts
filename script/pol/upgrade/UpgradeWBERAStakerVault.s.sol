// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { WBERAStakerVault } from "src/pol/WBERAStakerVault.sol";
import { WBERAStakerVaultWithdrawalRequest } from "src/pol/WBERAStakerVaultWithdrawalRequest.sol";
import { BaseERC1967UpgradeScript } from "../../base/BaseUpgrade.s.sol";

contract UpgradeWBERAStakerVaultScript is BaseERC1967UpgradeScript {
    function deployNewWithdrawal721Implementation() public broadcast {
        address impl = _deployWithdrawal721NewImpl();
        console2.log("New WBERAStakerVaultWithdrawalRequest implementation address:", impl);
    }

    function printSetWithdrawalRequests721CallSignature() public view {
        console2.logBytes(
            abi.encodeCall(WBERAStakerVault.setWithdrawalRequests721, _polAddresses.wberaStakerVaultWithdrawalRequest)
        );
    }

    function _proxyAddress() internal view override returns (address) {
        return _polAddresses.wberaStakerVault;
    }

    function _deployNewImplementation() internal override returns (address) {
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
