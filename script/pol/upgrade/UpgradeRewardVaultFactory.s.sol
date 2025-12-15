// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseDeployScript } from "../../base/BaseDeploy.s.sol";
import { RewardVaultFactory } from "src/pol/rewards/RewardVaultFactory.sol";

import { AddressBook } from "../../base/AddressBook.sol";

contract UpgradeRewardVaultFactoryScript is BaseDeployScript, AddressBook {
    function run() public pure {
        console2.log("Please run specific function.");
    }

    function deployNewImplementation() public broadcast {
        address newRewardVaultFactoryImpl = _deployNewImplementation();
        console2.log("New RewardVaultFactory implementation address:", newRewardVaultFactoryImpl);
    }

    function printSetBGTIncentiveDistributorCallSignature() public view {
        console2.logBytes(
            abi.encodeCall(RewardVaultFactory.setBGTIncentiveDistributor, (_polAddresses.bgtIncentiveDistributor))
        );
    }

    /// @dev This function is only for testnet or test purposes.
    function upgradeToAndCallTestnet(bytes memory callSignature) public broadcast {
        address newRewardVaultFactoryImpl = _deployNewImplementation();
        console2.log("New RewardVaultFactory implementation address:", newRewardVaultFactoryImpl);
        RewardVaultFactory(_polAddresses.rewardVaultFactory).upgradeToAndCall(newRewardVaultFactoryImpl, callSignature);
        console2.log("RewardVaultFactory upgraded successfully");
    }

    function _deployNewImplementation() internal returns (address) {
        return
            _deploy("RewardVaultFactory", type(RewardVaultFactory).creationCode, _polAddresses.rewardVaultFactoryImpl);
    }
}
