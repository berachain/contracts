// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { Honey } from "src/honey/Honey.sol";
import { HONEY_ADDRESS, HONEY_IMPL } from "../HoneyAddresses.sol";

contract UpgradeHoneyImplScript is BaseScript, Create2Deployer {
    function run() public broadcast {
        address newHoneyImpl = deployWithCreate2(0, type(Honey).creationCode);
        require(newHoneyImpl == HONEY_IMPL, "implementation not deployed at desired address");
        console2.log("Honey implementation deployed successfully");
        console2.log("Honey implementation address:", newHoneyImpl);
    }

    /// @dev This function is only for testnet or test purposes.
    function upgradeToTestnet() public broadcast {
        console2.log("New Honey implementation address:", HONEY_IMPL);
        _validateCode("Honey", HONEY_IMPL);

        bytes memory callSignature;
        Honey(HONEY_ADDRESS).upgradeToAndCall(HONEY_IMPL, callSignature);
        console2.log("Honey upgraded successfully");
    }
}
