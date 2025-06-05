// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { HoneyFactory } from "src/honey/HoneyFactory.sol";
import { HONEY_FACTORY_ADDRESS, HONEY_FACTORY_IMPL } from "../HoneyAddresses.sol";

contract DeployHoneyFactoryImplScript is BaseScript, Create2Deployer {
    function run() public broadcast {
        address newHoneyFactoryImpl = deployWithCreate2(0, type(HoneyFactory).creationCode);
        require(newHoneyFactoryImpl == HONEY_FACTORY_IMPL, "implementation not deployed at desired address");
        console2.log("HoneyFactory implementation deployed successfully");
        console2.log("HoneyFactory implementation address:", newHoneyFactoryImpl);
    }

    /// @dev This function is only for testnet or test purposes.
    function upgradeToTestnet() public broadcast {
        console2.log("New HoneyFactory implementation address:", HONEY_FACTORY_IMPL);
        _validateCode("HoneyFactory", HONEY_FACTORY_IMPL);

        bytes memory callSignature;
        HoneyFactory(HONEY_FACTORY_ADDRESS).upgradeToAndCall(HONEY_FACTORY_IMPL, callSignature);
        console2.log("HoneyFactory upgraded successfully");
    }
}
