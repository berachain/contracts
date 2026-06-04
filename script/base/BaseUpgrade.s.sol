// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";

import { BaseDeployScript } from "./BaseDeploy.s.sol";
import { AddressBook } from "./AddressBook.sol";

abstract contract BaseUpgradeScript is BaseDeployScript, AddressBook {
    function run() public pure {
        console2.log("Please run specific function.");
    }

    function deployNewImplementation() public broadcast {
        address impl = _deployNewImplementation();
        console2.log("New implementation address:", impl);
    }

    function _deployNewImplementation() internal virtual returns (address);
}

abstract contract BaseERC1967UpgradeScript is BaseUpgradeScript {
    /// @dev Only for testnet or test purposes.
    function upgradeToAndCallTestnet(bytes memory callSignature) public broadcast {
        address newImpl = _deployNewImplementation();
        console2.log("New implementation address:", newImpl);
        UUPSUpgradeable(_proxyAddress()).upgradeToAndCall(newImpl, callSignature);
        console2.log("Contract upgraded successfully");
    }

    function _proxyAddress() internal view virtual returns (address);
}

abstract contract BaseBeaconUpgradeScript is BaseUpgradeScript {
    /// @dev Only for testnet or test purposes.
    function upgradeToTestnet() public broadcast {
        address newImpl = _deployNewImplementation();
        console2.log("New implementation address:", newImpl);
        UpgradeableBeacon(_beaconAddress()).upgradeTo(newImpl);
        console2.log("Contract upgraded successfully");
    }

    function _beaconAddress() internal view virtual returns (address);
}
