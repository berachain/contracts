// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { LSTStakerVaultFactory } from "src/pol/lst/LSTStakerVaultFactory.sol";
import { LSTStakerVault } from "src/pol/lst/LSTStakerVault.sol";
import { LSTStakerVaultWithdrawalRequest } from "src/pol/lst/LSTStakerVaultWithdrawalRequest.sol";
import { Salt } from "src/base/Salt.sol";

/// @title LSTStakerVaultFactoryDeployer
/// @author Berachain Team
/// @notice This contract is used to deploy the LSTStakerVaultFactory contract, along with
/// the LSTStakerVault and LSTStakerVaultWithdrawalRequest reference implementations.
contract LSTStakerVaultFactoryDeployer is Create2Deployer {
    LSTStakerVaultFactory public lstVaultFactory;

    /// @notice Constructor for the LSTStakerVaultFactoryDeployer.
    /// @param governance The address of the governance contract.
    constructor(
        address governance,
        Salt memory lstStakerVaultFactorySalt,
        uint256 lstStakerVaultSalt,
        uint256 lstStakerVaultWithdrawalRequestSalt
    ) {
        address lstVaultImpl = deployWithCreate2(lstStakerVaultSalt, type(LSTStakerVault).creationCode);
        address lstVaultWithdrawalImpl =
            deployWithCreate2(lstStakerVaultWithdrawalRequestSalt, type(LSTStakerVaultWithdrawalRequest).creationCode);

        address lstVaultFactoryImpl =
            deployWithCreate2(lstStakerVaultFactorySalt.implementation, type(LSTStakerVaultFactory).creationCode);
        lstVaultFactory =
            LSTStakerVaultFactory(deployProxyWithCreate2(lstVaultFactoryImpl, lstStakerVaultFactorySalt.proxy));

        lstVaultFactory.initialize(governance, lstVaultImpl, lstVaultWithdrawalImpl);
    }
}
