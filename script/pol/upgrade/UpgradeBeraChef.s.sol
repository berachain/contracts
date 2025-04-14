// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { BeraChef } from "src/pol/rewards/BeraChef.sol";

import { BERACHEF_ADDRESS } from "../POLAddresses.sol";

contract UpgradeBeraChefScript is BaseScript, Create2Deployer {
    // Equal to MAX_COMMISSION_CHANGE_DELAY
    uint64 constant COMMISSION_CHANGE_DELAY = 2 * 8191;

    uint64 constant STARTING_VALUE_MAX_WEIGHT_PER_VAULT = 1e4;

    function run() public pure {
        console2.log("Please run specific function.");
    }

    function deployNewImplementation() public broadcast {
        address newBeraChefImpl = _deployNewImplementation();
        console2.log("New BeraChef implementation address:", newBeraChefImpl);
    }

    function printSetCommissionChangeDelayCallSignature() public pure {
        console2.logBytes(abi.encodeCall(BeraChef.setCommissionChangeDelay, (COMMISSION_CHANGE_DELAY)));
    }

    function printSetMaxWeightPerVaultCallSignature() public pure {
        console2.logBytes(abi.encodeCall(BeraChef.setMaxWeightPerVault, (STARTING_VALUE_MAX_WEIGHT_PER_VAULT)));
    }

    /// @dev This function is only for testnet or test purposes.
    function upgradeToAndCallTestnet(bytes memory callSignature) public broadcast {
        address newBeraChefImpl = _deployNewImplementation();
        console2.log("New BeraChef implementation address:", newBeraChefImpl);
        BeraChef(BERACHEF_ADDRESS).upgradeToAndCall(newBeraChefImpl, callSignature);
        console2.log("BeraChef upgraded successfully");
    }

    function _deployNewImplementation() internal returns (address) {
        return deployWithCreate2(0, type(BeraChef).creationCode);
    }
}
