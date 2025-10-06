// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Create2Deployer } from "../base/Create2Deployer.sol";
import { WBERAStakerVaultWithdrawalRequest } from "./WBERAStakerVaultWithdrawalRequest.sol";

/// @title WBERAStakerWithdrawReqDeployer
/// @author Berachain Team
/// @notice This contract is used to deploy the WBERAStakerVaultWithdrawalRequest contract.
contract WBERAStakerWithdrawReqDeployer is Create2Deployer {
    /// @notice WBERAStakerVaultWithdrawalRequest implementation address.
    address public immutable wberaStakerVaultWithdrawalRequestImpl;

    /// @notice The WBERAStakerVaultWithdrawalRequest contract.
    WBERAStakerVaultWithdrawalRequest public immutable wberaStakerVaultWithdrawalRequest;

    constructor(address governance, address wberaStakerVault, uint256 wberaStakerVaultWithdrawalRequestSalt) {
        // deploy the WBERAStakerVaultWithdrawalRequest implementation
        wberaStakerVaultWithdrawalRequestImpl =
            deployWithCreate2(0, type(WBERAStakerVaultWithdrawalRequest).creationCode);
        // deploy the WBERAStakerVaultWithdrawalRequest proxy
        wberaStakerVaultWithdrawalRequest = WBERAStakerVaultWithdrawalRequest(
            deployProxyWithCreate2(wberaStakerVaultWithdrawalRequestImpl, wberaStakerVaultWithdrawalRequestSalt)
        );
        // initialize the contract
        wberaStakerVaultWithdrawalRequest.initialize(governance, wberaStakerVault);
    }
}
