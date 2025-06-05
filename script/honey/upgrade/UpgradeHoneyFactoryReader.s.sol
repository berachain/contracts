// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { HoneyFactoryReader } from "src/honey/HoneyFactoryReader.sol";
import { HONEY_FACTORY_READER_IMPL } from "../HoneyAddresses.sol";

contract DeployHoneyFactoryReaderImplScript is BaseScript, Create2Deployer {
    function run() public broadcast {
        address newHoneyFactoryImpl = deployWithCreate2(0, type(HoneyFactoryReader).creationCode);
        require(newHoneyFactoryImpl == HONEY_FACTORY_READER_IMPL, "implementation not deployed at desired address");
        console2.log("HoneyFactoryReader implementation deployed successfully");
        console2.log("HoneyFactoryReader implementation address:", newHoneyFactoryImpl);
    }
}
