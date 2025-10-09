// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { RewardVaultHelper } from "src/pol/rewards/RewardVaultHelper.sol";

/// @title RewardVaultHelperDeployer
/// @author Berachain Team
/// @notice This contract is used to deploy the RewardVaultHelper contract.
contract RewardVaultHelperDeployer is Create2Deployer {
    /// @notice The RewardVaultHelper implementation address.
    address public immutable rewardVaultHelperImpl;

    /// @notice The RewardVaultHelper contract.
    RewardVaultHelper public immutable rewardVaultHelper;

    constructor(address owner, uint256 rewardVaultHelperSalt) {
        // deploy the RewardVaultHelper implementation
        rewardVaultHelperImpl = deployWithCreate2(0, type(RewardVaultHelper).creationCode);
        // deploy the RewardVaultHelper proxy
        rewardVaultHelper = RewardVaultHelper(deployProxyWithCreate2(rewardVaultHelperImpl, rewardVaultHelperSalt));
        // initialize the contract
        rewardVaultHelper.initialize(owner);
    }
}
