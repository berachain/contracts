// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { LibClone } from "solady/src/utils/LibClone.sol";
import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";
import { Utils } from "../../libraries/Utils.sol";
import { ILSTStakerVaultFactory } from "../interfaces/lst/ILSTStakerVaultFactory.sol";
import { LSTStakerVault } from "./LSTStakerVault.sol";
import { LSTStakerVaultWithdrawalRequest } from "./LSTStakerVaultWithdrawalRequest.sol";

/// @title LSTStakerVaultFactory
/// @author Berachain Team
/// @notice Factory contract for creating LSTStakerVaults and their withdrawal contracts and keeping track of them.
contract LSTStakerVaultFactory is ILSTStakerVaultFactory, AccessControlUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    using Utils for bytes4;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The initial deposit amount to be made to each vault upon creation to prevent inflation attacks.
    uint256 public constant INITIAL_DEPOSIT = 10e18;

    /// @notice The VAULT MANAGER role.
    bytes32 public constant VAULT_MANAGER_ROLE = keccak256("VAULT_MANAGER_ROLE");

    /// @notice The VAULT PAUSER role.
    bytes32 public constant VAULT_PAUSER_ROLE = keccak256("VAULT_PAUSER_ROLE");

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The beacon address for the LSTStakerVault.
    address public vaultBeacon;

    /// @notice The beacon address for the LSTStakerVaultWithdrawalRequest.
    address public withdrawalBeacon;

    /// @notice Mapping of staking token to deployed contract addresses.
    mapping(address stakingToken => LSTAddresses addresses) public lstStakerContracts;

    /// @notice Array of all contracts that have been created.
    LSTAddresses[] public allLSTStakerContracts;

    constructor() {
        _disableInitializers();
    }

    function initialize(address governance, address vaultImpl, address withdrawalImpl) external initializer {
        if (governance == address(0) || vaultImpl == address(0) || withdrawalImpl == address(0)) {
            ZeroAddress.selector.revertWith();
        }

        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, governance);
        // Allow the vault manager to manage the vault pauser role.
        // vault manager can grant and revoke the access for the vault pauser role.
        _setRoleAdmin(VAULT_PAUSER_ROLE, VAULT_MANAGER_ROLE);

        vaultBeacon = address(new UpgradeableBeacon(governance, vaultImpl));
        withdrawalBeacon = address(new UpgradeableBeacon(governance, withdrawalImpl));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          ADMIN                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    /// @inheritdoc ILSTStakerVaultFactory
    function createLSTStakerVaultSystem(address stakingToken)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (LSTAddresses memory)
    {
        LSTAddresses memory cachedAddresses = lstStakerContracts[stakingToken];
        if (cachedAddresses.vault != address(0)) return cachedAddresses;

        // Check the code size of the staking token.
        if (stakingToken.code.length == 0) NotAContract.selector.revertWith();

        // Use solady library to deploy deterministic clone of vaultImpl and withdrawalImpl.
        bytes32 salt;
        assembly ("memory-safe") {
            mstore(0, stakingToken)
            salt := keccak256(0, 0x20)
        }

        address vault = LibClone.deployDeterministicERC1967BeaconProxy(vaultBeacon, salt);
        address withdrawal721 = LibClone.deployDeterministicERC1967BeaconProxy(withdrawalBeacon, salt);

        // Store the vault in the mapping and array.
        LSTAddresses memory addresses = LSTAddresses({ vault: vault, withdrawal721: withdrawal721 });
        lstStakerContracts[stakingToken] = addresses;
        allLSTStakerContracts.push(addresses);
        emit LSTStakerVaultCreated(stakingToken, vault);
        emit LSTStakerVaultWithdrawalRequestCreated(stakingToken, withdrawal721);

        // Initialize the contracts.
        LSTStakerVault(vault).initialize(stakingToken, withdrawal721);
        LSTStakerVaultWithdrawalRequest(withdrawal721).initialize(vault);

        // Get initial deposit amount from creator and perform initial deposit.
        IERC20(stakingToken).safeTransferFrom(msg.sender, address(this), INITIAL_DEPOSIT);
        IERC20(stakingToken).safeIncreaseAllowance(vault, INITIAL_DEPOSIT);
        LSTStakerVault(vault).deposit(INITIAL_DEPOSIT, msg.sender);

        return addresses;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          READS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc ILSTStakerVaultFactory
    function getLSTStakerContracts(address stakingToken) external view returns (LSTAddresses memory) {
        return lstStakerContracts[stakingToken];
    }

    /// @inheritdoc ILSTStakerVaultFactory
    function predictStakerVaultAddress(address stakingToken) external view returns (address) {
        bytes32 salt;
        assembly ("memory-safe") {
            mstore(0, stakingToken)
            salt := keccak256(0, 0x20)
        }
        return LibClone.predictDeterministicAddressERC1967BeaconProxy(vaultBeacon, salt, address(this));
    }

    /// @inheritdoc ILSTStakerVaultFactory
    function predictWithdrawalRequestAddress(address stakingToken) external view returns (address) {
        bytes32 salt;
        assembly ("memory-safe") {
            mstore(0, stakingToken)
            salt := keccak256(0, 0x20)
        }
        return LibClone.predictDeterministicAddressERC1967BeaconProxy(withdrawalBeacon, salt, address(this));
    }

    /// @inheritdoc ILSTStakerVaultFactory
    function allLSTStakerContractsLength() external view returns (uint256) {
        return allLSTStakerContracts.length;
    }
}
