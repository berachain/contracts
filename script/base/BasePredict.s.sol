// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "./Base.s.sol";

abstract contract BasePredictScript is BaseScript {
    /// @notice Predicts the address of a proxied contract deployed using the CREATE2.
    /// @dev This method provides code ergonomy by hiding the salt generation based on a known convention.
    function _predictProxyAddress(string memory contractName, bytes memory initCode) internal view {
        address proxyAddr = _predictProxyAddress(initCode);
        console2.log(string.concat(contractName, ": "), proxyAddr);
    }

    /// @notice Predicts the address of a contract deployed using the CREATE2.
    /// @dev This method provides code ergonomy by hiding the salt generation based on a known convention.
    function _predictAddress(string memory contractName, bytes memory initCode) internal view {
        address contractAddress = _predictAddress(initCode);
        console2.log(string.concat(contractName, ": "), contractAddress);
    }

    /// @notice Predicts the address of a contract deployed using the CREATE2.
    /// @dev use abi.encode for args
    /// @dev This method provides code ergonomy by hiding the salt generation based on a known convention.
    function _predictAddressWithArgs(
        string memory contractName,
        bytes memory initCode,
        bytes memory args
    )
        internal
        view
    {
        address contractAddress = _predictAddressWithArgs(initCode, args);
        console2.log(string.concat(contractName, ": "), contractAddress);
        console2.log("WARNING: hard-coded addresses used as arguments may need to be updated");
    }
}
