// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Salt } from "src/base/Salt.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { RewardAllocatorFactory } from "src/pol/rewards/RewardAllocatorFactory.sol";

/// @title RewardAllocatorFactoryDeployer
/// @author Berachain Team
/// @notice This contract is used to deploy the RewardAllocatorFactory contract.
contract RewardAllocatorFactoryDeployer is Create2Deployer {
    /// @notice The RewardAllocatorFactory implementation address.
    address public immutable rewardAllocatorFactoryImpl;

    /// @notice The RewardAllocatorFactory contract.
    RewardAllocatorFactory public immutable rewardAllocatorFactory;

    constructor(address owner, address beraChef, Salt memory rewardAllocatorFactorySalt) {
        // deploy the RewardAllocatorFactory implementation
        rewardAllocatorFactoryImpl =
            deployWithCreate2(rewardAllocatorFactorySalt.implementation, type(RewardAllocatorFactory).creationCode);
        // deploy the RewardAllocatorFactory proxy
        rewardAllocatorFactory = RewardAllocatorFactory(
            deployProxyWithCreate2(rewardAllocatorFactoryImpl, rewardAllocatorFactorySalt.proxy)
        );
        // initialize the contract
        rewardAllocatorFactory.initialize(owner, beraChef);
    }
}
