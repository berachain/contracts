// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { WBERAStakerVault } from "src/pol/WBERAStakerVault.sol";

import { WBERA_STAKER_VAULT_ADDRESS, WBERA_STAKER_VAULT_WITHDRAWAL_REQUEST_ADDRESS } from "../POLAddresses.sol";

contract UpgradeWBERAStakerVaultScript is BaseScript, Create2Deployer {
    function run() public pure {
        console2.log("Please run specific function.");
    }

    function deployNewImplementation() public broadcast {
        address newWBERAStakerVaultImpl = _deployNewImplementation();
        console2.log("New WBERAStakerVault implementation address:", newWBERAStakerVaultImpl);
    }

    function printSetWithdrawalRequests721CallSignature() public pure {
        console2.logBytes(
            abi.encodeCall(WBERAStakerVault.setWithdrawalRequests721, WBERA_STAKER_VAULT_WITHDRAWAL_REQUEST_ADDRESS)
        );
    }

    /// @dev This function is only for testnet or test purposes.
    function upgradeToAndCallTestnet(bytes memory callSignature) public broadcast {
        address newImpl = _deployNewImplementation();
        console2.log("New WBERAStakerVault implementation address:", newImpl);
        WBERAStakerVault(payable(WBERA_STAKER_VAULT_ADDRESS)).upgradeToAndCall(newImpl, callSignature);
        console2.log("WBERAStakerVault upgraded successfully");
    }

    function _deployNewImplementation() internal returns (address) {
        return deployWithCreate2(0, type(WBERAStakerVault).creationCode);
    }
}
