// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Script, console2 } from "forge-std/Script.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";

abstract contract BasePredictScript is Script, Create2Deployer {
    /// @notice Predicts the address of a proxied contract deployed using the CREATE2.
    function _predictProxyAddress(
        string memory contractName,
        bytes memory initCode,
        uint256 implSalt,
        uint256 proxySalt
    )
        internal
        pure
    {
        address contractAddress = getCreate2ProxyAddress(getCreate2Address(implSalt, initCode), proxySalt);
        console2.log(string.concat(contractName, ": "), contractAddress);
    }

    /// @notice Predicts the address of a contract deployed using the CREATE2.
    function _predictAddress(string memory contractName, bytes memory initCode, uint256 salt) internal pure {
        address contractAddress = getCreate2Address(salt, initCode);
        console2.log(string.concat(contractName, ": "), contractAddress);
    }

    /// @notice Predicts the address of a contract deployed using the CREATE2.
    function _predictAddressWithArgs(
        string memory contractName,
        bytes memory initCode,
        uint256 salt,
        bytes memory args
    )
        internal
        pure
    {
        address contractAddress = getCreate2AddressWithArgs(salt, initCode, args);
        console2.log(string.concat(contractName, ": "), contractAddress);
    }
}
