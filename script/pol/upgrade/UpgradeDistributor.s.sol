// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { Distributor } from "src/pol/rewards/Distributor.sol";

import { DISTRIBUTOR_ADDRESS } from "../POLAddresses.sol";

contract UpgradeDistributorScript is BaseScript, Create2Deployer {
    function run() public pure {
        console2.log("Please run specific function.");
    }

    function deployNewImplementation() public broadcast {
        address newDistributorImpl = _deployNewImplementation();
        console2.log("New Distributor implementation address:", newDistributorImpl);
    }

    /// @dev This function is only for testnet or test purposes.
    function upgradeToAndCallTestnet(bytes memory callSignature) public broadcast {
        address newDistributorImpl = _deployNewImplementation();
        console2.log("New Distributor implementation address:", newDistributorImpl);
        Distributor(DISTRIBUTOR_ADDRESS).upgradeToAndCall(newDistributorImpl, callSignature);
        console2.log("Distributor upgraded successfully");
    }

    function _deployNewImplementation() internal returns (address) {
        return deployWithCreate2(0, type(Distributor).creationCode);
    }
}
