// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Create2Deployer } from "./Create2Deployer.sol";
import { Salt } from "./Salt.sol";

/// @notice A contract to enforce an opinionated way to make deterministic deployments.
/// @dev This contract is not aimed to be deployed but, instead, must be used as script.
/// @dev For deterministic deployment the team members must share the secret seeds and pepper.
abstract contract DeployHelper is Create2Deployer {
    /// @dev Used to store the cryptographic pepper used in deterministic deployments.
    string private _pepper;

    function _setPepper(string memory pepper) internal {
        _pepper = pepper;
    }

    //--[ UTILS ]--------------------------------------------------------------

    /// @notice Enrich a nonce with cryptographic salt and pepper.
    /// @dev The nonce should be different on every public chain ID.
    /// @dev The value can still be used in frontrunning attacks; please act accordingly.
    function _saltAndPepper(uint256 nonce) internal view returns (uint256 value) {
        value = uint256(keccak256(abi.encode(_pepper, nonce)));
    }

    /// @notice Computes a nonce for the deployment of a given smart-contract.
    /// @param initCode The smart-contract creation code.
    /// @dev The value is safe against replication attacks on different chains.
    /// @dev The value can still be used in frontrunning attacks; please act accordingly.
    function _nonce(bytes memory initCode) internal view returns (uint256 nonce) {
        nonce = uint256(keccak256(abi.encode(block.chainid, initCode)));
    }

    /// @notice Computes a nonce for the deployment of a given smart-contract.
    /// @param initCode The smart-contract creation code.
    /// @param args The smart-contract creation parameters.
    /// @dev use abi.encode for args
    /// @dev The value is safe against replication attacks on different chains.
    /// @dev The value can still be used in frontrunning attacks; please act accordingly.
    function _nonce(bytes memory initCode, bytes memory args) internal view returns (uint256 nonce) {
        nonce = _nonce(abi.encodePacked(initCode, args));
    }

    /// @dev Syntactic sugar
    function _salt(bytes memory initCode) internal view returns (uint256 salt) {
        salt = _saltAndPepper(_nonce(initCode));
    }

    /// @dev Syntactic sugar
    function _salt(bytes memory initCode, bytes memory args) internal view returns (uint256 salt) {
        salt = _saltAndPepper(_nonce(initCode, args));
    }

    /// @notice Computes the salts needed for deploying a proxied contract using the CREATE2.
    function _saltsForProxy(bytes memory initCode) internal view returns (Salt memory salt) {
        uint256 implSalt = _salt(initCode);
        address implAddr = getCreate2Address(implSalt, initCode);
        uint256 proxySalt = _salt(initCodeERC1967(implAddr));

        salt = Salt({ proxy: proxySalt, implementation: implSalt });
    }

    //--[ PREDICT ]------------------------------------------------------------

    /// @notice Predicts the address of a proxied contract deployed using the CREATE2.
    /// @dev This method provides code ergonomy by hiding the salt generation based on a known convention.
    function _predictProxyAddress(bytes memory initCode) internal view returns (address) {
        Salt memory salt = _saltsForProxy(initCode);
        return getCreate2ProxyAddress(getCreate2Address(salt.implementation, initCode), salt.proxy);
    }

    /// @notice Predicts the address of a contract deployed using the CREATE2.
    /// @dev This method provides code ergonomy by hiding the salt generation based on a known convention.
    function _predictAddress(bytes memory initCode) internal view returns (address) {
        uint256 salt = _salt(initCode);
        return getCreate2Address(salt, initCode);
    }

    /// @notice Predicts the address of a contract deployed using the CREATE2.
    /// @dev This method provides code ergonomy by hiding the salt generation based on a known convention.
    /// @dev use abi.encode for args
    function _predictAddressWithArgs(bytes memory initCode, bytes memory args) internal view returns (address) {
        uint256 salt = _salt(initCode, args);
        return getCreate2AddressWithArgs(salt, initCode, args);
    }

    //--[ DEPLOY ]-------------------------------------------------------------

    /// @notice Deploys a contract using the CREATE2.
    /// @dev This method provides code ergonomy by hiding the salt generation based on a known convention.
    function _deploy(bytes memory initCode) internal returns (address deployedAddress) {
        uint256 salt = _salt(initCode);
        deployedAddress = deployWithCreate2(salt, initCode);
    }

    /// @notice Deploys a contract using the CREATE2.
    /// @dev This method provides code ergonomy by hiding the salt generation based on a known convention.
    /// @dev use abi.encode for args
    function _deployWithArgs(bytes memory initCode, bytes memory args) internal returns (address deployedAddress) {
        uint256 salt = _salt(initCode, args);
        deployedAddress = deployWithCreate2WithArgs(salt, initCode, args);
    }
}
