// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BasePredictScript } from "./BasePredict.s.sol";

abstract contract BaseDeployScript is BasePredictScript {
    /// @notice Deploys a contract using the CREATE2.
    /// @dev This method provides code ergonomy by hiding the salt generation based on a known convention.
    function _deploy(
        string memory contractName,
        bytes memory initCode,
        address predictedAddress
    )
        internal
        returns (address deployedAddress)
    {
        deployedAddress = _deploy(initCode);

        _checkDeploymentAddress(contractName, deployedAddress, predictedAddress);
    }

    /// @notice Deploys a contract using the CREATE2.
    /// @dev use abi.encode for args
    function _deployWithArgs(
        string memory contractName,
        bytes memory initCode,
        bytes memory args,
        address predictedAddress
    )
        internal
        returns (address deployedAddress)
    {
        deployedAddress = _deployWithArgs(initCode, args);

        _checkDeploymentAddress(contractName, deployedAddress, predictedAddress);
    }
}
