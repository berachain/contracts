// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { REWARD_VAULT_HELPER_ADDRESS, REWARD_VAULT_HELPER_IMPL_ADDRESS } from "../POLAddresses.sol";
import { RewardVaultHelperDeployer } from "src/pol/RewardVaultHelperDeployer.sol";

import { REWARD_VAULT_HELPER_SALT } from "../POLSalts.sol";

contract DeployRewardVaultHelperScript is BaseScript {
    function run() public pure {
        console2.log("Please run specific function.");
    }

    /// @notice Deploy the RewardVaultHelperDeployer contract.
    /// @dev This function is used to deploy the RewardVaultHelperDeployer contract.
    function deployRewardVaultHelper(address governance) public broadcast {
        console2.log("deploying RewardVaultHelperDeployer");
        console2.log("governance address:", governance);

        // deploy the RewardVaultHelperDeployer
        RewardVaultHelperDeployer rewardVaultHelperDeployer =
            new RewardVaultHelperDeployer(governance, REWARD_VAULT_HELPER_SALT);
        console2.log("RewardVaultHelperDeployer deployed at", address(rewardVaultHelperDeployer));

        _checkDeploymentAddress(
            "RewardVaultHelper Impl",
            address(rewardVaultHelperDeployer.rewardVaultHelperImpl()),
            REWARD_VAULT_HELPER_IMPL_ADDRESS
        );
        _checkDeploymentAddress(
            "RewardVaultHelper", address(rewardVaultHelperDeployer.rewardVaultHelper()), REWARD_VAULT_HELPER_ADDRESS
        );
    }
}
