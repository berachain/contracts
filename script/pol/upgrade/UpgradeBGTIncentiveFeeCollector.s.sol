// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { BGT_INCENTIVE_FEE_COLLECTOR_ADDRESS } from "../POLAddresses.sol";
import { BGTIncentiveFeeCollector } from "src/pol/BGTIncentiveFeeCollector.sol";

contract UpgradeBGTIncentiveFeeCollectorScript is BaseScript, Create2Deployer {
    function run() public pure {
        console2.log("Please run specific function.");
    }

    function deployNewImplementation() public broadcast {
        address newBGTIncentiveFeeCollectorImpl = _deployNewImplementation();
        console2.log("New BGTIncentiveFeeCollector implementation address:", newBGTIncentiveFeeCollectorImpl);
    }

    /// @dev This function is only for testnet or test purposes.
    function upgradeToTestnet() public broadcast {
        address newBGTIncentiveFeeCollectorImpl = _deployNewImplementation();
        console2.log("New BGTIncentiveFeeCollector implementation address:", newBGTIncentiveFeeCollectorImpl);
        BGTIncentiveFeeCollector(BGT_INCENTIVE_FEE_COLLECTOR_ADDRESS).upgradeToAndCall(
            newBGTIncentiveFeeCollectorImpl, bytes("")
        );
        console2.log("BGTIncentiveFeeCollector upgraded successfully");
    }

    function _deployNewImplementation() internal returns (address) {
        return deployWithCreate2(0, type(BGTIncentiveFeeCollector).creationCode);
    }
}
