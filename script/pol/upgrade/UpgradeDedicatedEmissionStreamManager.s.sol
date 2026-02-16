// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseDeployScript } from "../../base/BaseDeploy.s.sol";
import { DedicatedEmissionStreamManager } from "src/pol/rewards/DedicatedEmissionStreamManager.sol";

import { AddressBook } from "script/base/AddressBook.sol";

contract UpgradeDedicatedEmissionStreamManagerScript is BaseDeployScript, AddressBook {
    function run() public pure {
        console2.log("Please run specific function.");
    }

    function deployNewDedicatedEmissionStreamManagerImplementation() public broadcast {
        address newDedicatedEmissionStreamManagerImpl = _deployDedicatedEmissionStreamManagerNewImpl();
        console2.log(
            "New DedicatedEmissionStreamManager implementation address:", newDedicatedEmissionStreamManagerImpl
        );
    }

    /// @dev This function is only for testnet or test purposes.
    function upgradeToAndCallTestnet(bytes memory callSignature) public broadcast {
        address newImpl = _deployDedicatedEmissionStreamManagerNewImpl();
        console2.log("New DedicatedEmissionStreamManager implementation address:", newImpl);
        DedicatedEmissionStreamManager(payable(_polAddresses.dedicatedEmissionStreamManager))
            .upgradeToAndCall(newImpl, callSignature);
        console2.log("DedicatedEmissionStreamManager upgraded successfully");
    }

    function _deployDedicatedEmissionStreamManagerNewImpl() internal returns (address) {
        return _deploy(
            "DedicatedEmissionStreamManager",
            type(DedicatedEmissionStreamManager).creationCode,
            _polAddresses.dedicatedEmissionStreamManagerImpl
        );
    }
}
