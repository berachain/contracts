// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title Create2Deployer
/// @author Berachain Team
/// @notice Can be used to deploy contracts with CREATE2 Factory.
abstract contract Create2Deployer {
    using Create2 for bytes32;

    /// @dev Used by default when deploying with create2, https://github.com/Arachnid/deterministic-deployment-proxy.
    address public constant _CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    error DeploymentFailed();

    /// @dev Deploys a contract using the _CREATE2_FACTORY.
    /// @dev The call data is encoded as `abi.encodePacked(salt, initCode)`.
    /// @dev The return data is `abi.encodePacked(addr)`.
    /// @param salt The salt to use for the deployment.
    /// @param initCode The init code of the contract to deploy.
    /// @return addr The address of the deployed contract.
    function deployWithCreate2(uint256 salt, bytes memory initCode) internal returns (address addr) {
        assembly ("memory-safe") {
            // cache the length of the init code
            let length := mload(initCode)
            // overwrite the length memory slot with the salt
            mstore(initCode, salt)
            // deploy the contract using the _CREATE2_FACTORY
            if iszero(call(gas(), _CREATE2_FACTORY, 0, initCode, add(length, 0x20), 0, 0x14)) {
                mstore(0, 0x30116425) // selector for DeploymentFailed()
                revert(0x1c, 0x04)
            }
            addr := shr(96, mload(0))
            // restore the length memory slot
            mstore(initCode, length)
        }
    }

    /// @notice Deploys a contract using the _CREATE2_FACTORY with constructor arguments.
    /// @param salt The salt to use for the deployment.
    /// @param initCode The init code of the contract to deploy.
    /// @param args The constructor arguments to pass to the contract.
    /// @return addr The address of the deployed contract.
    function deployWithCreate2WithArgs(
        uint256 salt,
        bytes memory initCode,
        bytes memory args
    )
        internal
        returns (address addr)
    {
        // Combine initCode with constructorArgs
        bytes memory combinedCode = abi.encodePacked(initCode, args);

        assembly ("memory-safe") {
            // cache the length of the combined code
            let length := mload(combinedCode)
            // overwrite the length memory slot with the salt
            mstore(combinedCode, salt)
            // deploy the contract using the _CREATE2_FACTORY
            if iszero(call(gas(), _CREATE2_FACTORY, 0, combinedCode, add(length, 0x20), 0, 0x14)) {
                mstore(0, 0x30116425) // selector for DeploymentFailed()
                revert(0x1c, 0x04)
            }
            addr := shr(96, mload(0))
            // restore the length memory slot
            mstore(combinedCode, length)
        }
    }

    /// @notice Returns the deterministic address of a contract for the given salt and init code.
    /// @dev Assumes that the contract will be deployed using `deployWithCreate2`.
    /// @param salt The salt to use for the deployment.
    /// @param initCode The init code of the contract to deploy.
    /// @return addr The address of the deployed contract.
    function getCreate2Address(uint256 salt, bytes memory initCode) internal pure returns (address) {
        return getCreate2Address(salt, keccak256(initCode));
    }

    /// @notice Returns the deterministic address of a contract for the given salt, init code and constructor
    /// arguments.
    /// @dev Assumes that the contract will be deployed using `deployWithCreate2WithArgs`.
    /// @param salt The salt to use for the deployment.
    /// @param initCode The init code of the contract to deploy.
    /// @param args The constructor arguments to pass to the contract.
    /// @return addr The address of the deployed contract.
    function getCreate2AddressWithArgs(
        uint256 salt,
        bytes memory initCode,
        bytes memory args
    )
        internal
        pure
        returns (address)
    {
        return getCreate2Address(salt, keccak256(abi.encodePacked(initCode, args)));
    }

    /// @notice Returns the deterministic address of a contract for the given salt and init code.
    /// @dev Assumes that the contract will be deployed using `deployWithCreate2`.
    /// @param salt The salt to use for the deployment.
    /// @param initCodeHash The init codehash of the contract to deploy.
    /// @return addr The address of the deployed contract.
    function getCreate2Address(uint256 salt, bytes32 initCodeHash) internal pure returns (address) {
        return bytes32(salt).computeAddress(initCodeHash, _CREATE2_FACTORY);
    }

    /// @notice Deploys a ERC1967 Proxy for the already deployed implementation contract.
    /// @param implementation The implementation contract address.
    /// @param salt The salt that will be used for the deployment of the proxy.
    /// @return instance The determinitic address of the deployed proxy contract.
    function deployProxyWithCreate2(address implementation, uint256 salt) internal returns (address) {
        return deployWithCreate2(salt, initCodeERC1967(implementation));
    }

    /// @notice Returns the deterministic address of a ERC1967 proxy for the given implementation and salt.
    /// @dev Assumes that the proxy is deployed using `deployProxyWithCreate2`.
    /// @param implementation The implementation contract address.
    /// @param salt The salt that will be used for the deployment of the proxy.
    /// @return instance The address of the deployed proxy contract.
    function getCreate2ProxyAddress(address implementation, uint256 salt) internal pure returns (address) {
        return getCreate2Address(salt, initCodeERC1967(implementation));
    }

    /// @notice Returns the init code for a ERC1967 proxy with the given implementation.
    function initCodeERC1967(address implementation) internal pure returns (bytes memory) {
        return abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, bytes("")));
    }
}
