// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { WBERA_STAKER_VAULT_ADDRESS } from "../POLAddresses.sol";
import { WBERAStakerWithdrawReqDeployer } from "src/pol/WBERAStakerWithdrawReqDeployer.sol";

import { WBERA_STAKER_VAULT_WITHDRAWAL_REQUEST_SALT } from "../POLSalts.sol";

contract DeployWBERAStakerWithdrawReqScript is BaseScript {
    function run() public pure {
        console2.log("Please run specific function.");
    }

    /// @notice Deploy the WBERAStakerWithdrawReqDeployer contract.
    /// @dev This function is used to deploy the WBERAStakerWithdrawReqDeployer contract.
    function deployWBERAStakerWithdrawReq(address governance) public broadcast {
        console2.log("deploying WBERAStakerWithdrawReqDeployer");
        console2.log("governance address:", governance);

        // deploy the WBERAStakerWithdrawReqDeployer
        WBERAStakerWithdrawReqDeployer wberaStakerWithdrawReqDeployer = new WBERAStakerWithdrawReqDeployer(
            governance, WBERA_STAKER_VAULT_ADDRESS, WBERA_STAKER_VAULT_WITHDRAWAL_REQUEST_SALT
        );
        console2.log("WBERAStakerWithdrawReqDeployer deployed at", address(wberaStakerWithdrawReqDeployer));
        console2.log(
            "WBERAStakerVaultWithdrawalRequest implementation address:",
            wberaStakerWithdrawReqDeployer.wberaStakerVaultWithdrawalRequestImpl()
        );
        console2.log(
            "WBERAStakerVaultWithdrawalRequest deployed at",
            address(wberaStakerWithdrawReqDeployer.wberaStakerVaultWithdrawalRequest())
        );
    }
}
