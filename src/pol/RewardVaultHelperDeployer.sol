// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { Salt } from "src/base/Salt.sol";
import { RewardVaultHelper } from "src/pol/rewards/RewardVaultHelper.sol";

/// @title RewardVaultHelperDeployer
/// @author Berachain Team
/// @notice This contract is used to deploy the RewardVaultHelper contract.
contract RewardVaultHelperDeployer is Create2Deployer {
    /// @notice The RewardVaultHelper implementation address.
    address public immutable rewardVaultHelperImpl;

    /// @notice The RewardVaultHelper contract.
    RewardVaultHelper public immutable rewardVaultHelper;

    constructor(address owner, Salt memory rewardVaultHelperSalt) {
        // deploy the RewardVaultHelper implementation
        rewardVaultHelperImpl =
            deployWithCreate2(rewardVaultHelperSalt.implementation, type(RewardVaultHelper).creationCode);
        // deploy the RewardVaultHelper proxy
        rewardVaultHelper =
            RewardVaultHelper(deployProxyWithCreate2(rewardVaultHelperImpl, rewardVaultHelperSalt.proxy));
        // initialize the contract
        rewardVaultHelper.initialize(owner);
    }
}
