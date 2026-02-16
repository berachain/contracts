// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";

import { AddressBook } from "script/base/AddressBook.sol";
import { BaseScript } from "script/base/Base.s.sol";
import { Storage } from "script/base/Storage.sol";

import { DedicatedEmissionStreamManagerDeployer } from "src/pol/DedicatedEmissionStreamManagerDeployer.sol";
import { DedicatedEmissionStreamManager } from "src/pol/rewards/DedicatedEmissionStreamManager.sol";

contract DeployDedicatedEmissionStreamManagerScript is BaseScript, Storage, AddressBook {
    function run() public pure {
        console2.log("Please run specific function.");
    }

    function deployDedicatedEmissionStreamManager(address governance) public broadcast {
        console2.log("\n\nDeploying DedicatedEmissionStreamManager...");

        DedicatedEmissionStreamManagerDeployer deployerContract = new DedicatedEmissionStreamManagerDeployer(
            governance,
            _polAddresses.distributor,
            _polAddresses.beraChef,
            _saltsForProxy(type(DedicatedEmissionStreamManager).creationCode)
        );

        dedicatedEmissionStreamManager = deployerContract.dedicatedEmissionStreamManager();
        _checkDeploymentAddress(
            "DedicatedEmissionStreamManager",
            address(dedicatedEmissionStreamManager),
            _polAddresses.dedicatedEmissionStreamManager
        );
    }
}
