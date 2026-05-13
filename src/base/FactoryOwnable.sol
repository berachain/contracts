// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { IRewardVaultFactory } from "../pol/interfaces/IRewardVaultFactory.sol";

import { Utils } from "../libraries/Utils.sol";

/// @title FactoryOwnable
/// @author Berachain Team
/// @notice Contract module which provides a modifier for restricting access to the factory owner.
abstract contract FactoryOwnable is Initializable {
    using Utils for bytes4;

    /// @notice Throws if sender is not the owner of factory contract.
    /// @param account The address of the sender.
    error OwnableUnauthorizedAccount(address account);

    /// @custom:storage-location erc7201:berachain.storage.factoryOwnable
    struct FactoryOwnableStorage {
        address _factory;
    }

    // keccak256(abi.encode(uint256(keccak256("berachain.storage.factoryOwnable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FactoryOwnableStorageLocation =
        0x4e32a932fdd4658a66f9586d8955a0d0a795a01bd8251335b4fae29d972acc00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         INITIALIZER                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Must be called by the initializer of the inheriting contract.
    /// @param factoryAddr The address of the ownable factory contract.
    function __FactoryOwnable_init(address factoryAddr) internal onlyInitializing {
        _setFactory(factoryAddr);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Throws if called by any account other than the factory owner.
    modifier onlyFactoryOwner() {
        _checkFactoryOwner();
        _;
    }

    /// @dev Throws if called by any account other than the factory vault manager.
    modifier onlyFactoryVaultManager() {
        _checkFactoryVaultManager();
        _;
    }

    /// @dev Throws if called by any account other than the factory vault pauser.
    modifier onlyFactoryVaultPauser() {
        _checkFactoryVaultPauser();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         GETTERS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns the address of the factory contract.
    function factory() public view virtual returns (address) {
        FactoryOwnableStorage storage $ = _getFactoryOwnableStorage();
        return $._factory;
    }

    /// @notice Returns if the user is a owner of the factory contract.
    function isFactoryOwner(address user) public view virtual returns (bool) {
        FactoryOwnableStorage storage $ = _getFactoryOwnableStorage();
        return AccessControlUpgradeable($._factory).hasRole(_getAdminRole(), user);
    }

    /// @notice Returns if the account is a vault manager of the factory contract.
    function isFactoryVaultManager(address user) public view virtual returns (bool) {
        FactoryOwnableStorage storage $ = _getFactoryOwnableStorage();
        return AccessControlUpgradeable($._factory).hasRole(_getVaultManagerRole(), user);
    }

    /// @notice Returns if the account is a vault pauser of the factory contract.
    function isFactoryVaultPauser(address user) public view virtual returns (bool) {
        FactoryOwnableStorage storage $ = _getFactoryOwnableStorage();
        return AccessControlUpgradeable($._factory).hasRole(_getVaultPauserRole(), user);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         INTERNALS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the DEFAULT_ADMIN_ROLE of the factory contract.
    function _getAdminRole() internal view returns (bytes32) {
        FactoryOwnableStorage storage $ = _getFactoryOwnableStorage();
        return AccessControlUpgradeable($._factory).DEFAULT_ADMIN_ROLE();
    }

    /// @dev Returns the VAULT_MANAGER_ROLE of the factory contract.
    function _getVaultManagerRole() internal view returns (bytes32) {
        FactoryOwnableStorage storage $ = _getFactoryOwnableStorage();
        return IRewardVaultFactory($._factory).VAULT_MANAGER_ROLE();
    }

    /// @dev Returns the VAULT_PAUSER_ROLE of the factory contract.
    function _getVaultPauserRole() internal view returns (bytes32) {
        FactoryOwnableStorage storage $ = _getFactoryOwnableStorage();
        return IRewardVaultFactory($._factory).VAULT_PAUSER_ROLE();
    }

    /// @dev Returns the storage struct of the factory ownable contract.
    function _getFactoryOwnableStorage() internal pure returns (FactoryOwnableStorage storage $) {
        assembly {
            $.slot := FactoryOwnableStorageLocation
        }
    }

    /// @dev Returns the address of the incentive tokens collector contract.
    function getIncentiveTokensCollector() internal view returns (address) {
        FactoryOwnableStorage storage $ = _getFactoryOwnableStorage();
        return IRewardVaultFactory($._factory).incentiveTokensCollector();
    }

    /// @dev Sets the address of the factory contract.
    function _setFactory(address factoryAddr) internal {
        FactoryOwnableStorage storage $ = _getFactoryOwnableStorage();
        $._factory = factoryAddr;
    }

    /// @dev Checks if the sender is a admin of the factory contract.
    function _checkFactoryOwner() internal view {
        if (!isFactoryOwner(msg.sender)) OwnableUnauthorizedAccount.selector.revertWith(msg.sender);
    }

    /// @dev Check if the sender is a vault manager of the factory contract.
    function _checkFactoryVaultManager() internal view {
        if (!isFactoryVaultManager(msg.sender)) OwnableUnauthorizedAccount.selector.revertWith(msg.sender);
    }

    /// @dev Check if the sender is a vault pauser of the factory contract.
    function _checkFactoryVaultPauser() internal view {
        if (!isFactoryVaultPauser(msg.sender)) OwnableUnauthorizedAccount.selector.revertWith(msg.sender);
    }
}
