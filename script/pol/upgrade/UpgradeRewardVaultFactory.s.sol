// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { RewardVaultFactory } from "src/pol/rewards/RewardVaultFactory.sol";

import { REWARD_VAULT_FACTORY_ADDRESS, BGT_INCENTIVE_DISTRIBUTOR_ADDRESS } from "../POLAddresses.sol";

contract UpgradeRewardVaultFactoryScript is BaseScript, Create2Deployer {
    function run() public pure {
        console2.log("Please run specific function.");
    }

    function deployNewImplementation() public broadcast {
        address newRewardVaultFactoryImpl = _deployNewImplementation();
        console2.log("New RewardVaultFactory implementation address:", newRewardVaultFactoryImpl);
    }

    function printSetBGTIncentiveDistributorCallSignature() public pure {
        console2.logBytes(
            abi.encodeCall(RewardVaultFactory.setBGTIncentiveDistributor, (BGT_INCENTIVE_DISTRIBUTOR_ADDRESS))
        );
    }

    /// @dev This function is only for testnet or test purposes.
    function upgradeToAndCallTestnet(bytes memory callSignature) public broadcast {
        address newRewardVaultFactoryImpl = _deployNewImplementation();
        console2.log("New RewardVaultFactory implementation address:", newRewardVaultFactoryImpl);
        RewardVaultFactory(REWARD_VAULT_FACTORY_ADDRESS).upgradeToAndCall(newRewardVaultFactoryImpl, callSignature);
        console2.log("RewardVaultFactory upgraded successfully");
    }

    function _deployNewImplementation() internal returns (address) {
        return deployWithCreate2(0, type(RewardVaultFactory).creationCode);
    }
}
