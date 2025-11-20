// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { AddressBook } from "../../base/AddressBook.sol";
import { RewardVaultHelperDeployer } from "src/pol/RewardVaultHelperDeployer.sol";
import { RewardVaultHelper } from "src/pol/rewards/RewardVaultHelper.sol";

contract DeployRewardVaultHelperScript is BaseScript, AddressBook {
    constructor() AddressBook(_chainType) { }

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
            new RewardVaultHelperDeployer(governance, _saltsForProxy(type(RewardVaultHelper).creationCode));
        console2.log("RewardVaultHelperDeployer deployed at", address(rewardVaultHelperDeployer));

        _checkDeploymentAddress(
            "RewardVaultHelper Impl",
            address(rewardVaultHelperDeployer.rewardVaultHelperImpl()),
            _polAddresses.rewardVaultHelperImpl
        );
        _checkDeploymentAddress(
            "RewardVaultHelper",
            address(rewardVaultHelperDeployer.rewardVaultHelper()),
            _polAddresses.rewardVaultHelper
        );
    }
}
