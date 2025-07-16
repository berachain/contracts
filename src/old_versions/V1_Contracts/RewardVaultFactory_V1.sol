// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { LibClone } from "solady/src/utils/LibClone.sol";
import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";
import { Utils } from "src/libraries/Utils.sol";
import { IRewardVaultFactory_V1 } from "./interfaces/IRewardVaultFactory_V1.sol";
import { RewardVault_V6 } from "../V6_Contracts/RewardVault_V6.sol";

/// @title RewardVaultFactory
/// @author Berachain Team
/// @notice Factory contract for creating RewardVaults and keeping track of them.
contract RewardVaultFactory_V1 is IRewardVaultFactory_V1, AccessControlUpgradeable, UUPSUpgradeable {
    using Utils for bytes4;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The VAULT MANAGER role.
    bytes32 public constant VAULT_MANAGER_ROLE = keccak256("VAULT_MANAGER_ROLE");

    /// @notice The VAULT PAUSER role.
    bytes32 public constant VAULT_PAUSER_ROLE = keccak256("VAULT_PAUSER_ROLE");

    /// @notice The beacon address.
    address public beacon;

    /// @notice The BGT token address.
    address public bgt;

    /// @notice The distributor address.
    address public distributor;

    /// @notice The BeaconDeposit contract address.
    address public beaconDepositContract;

    /// @notice Mapping of staking token to vault address.
    mapping(address stakingToken => address vault) public getVault;

    /// @notice Array of all vaults that have been created.
    address[] public allVaults;

    /// @notice The address of the BGTIncentiveDistributor contract to receive
    /// the BGT booster share of the incentive tokens.
    address public bgtIncentiveDistributor;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _bgt,
        address _distributor,
        address _beaconDepositContract,
        address _governance,
        address _vaultImpl
    )
        external
        initializer
    {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _governance);
        // Allow the vault manager to manage the vault pauser role.
        // vault manager can grant and revoke the access for the vault pauser role.
        _setRoleAdmin(VAULT_PAUSER_ROLE, VAULT_MANAGER_ROLE);
        // slither-disable-next-line missing-zero-check
        bgt = _bgt;
        // slither-disable-next-line missing-zero-check
        distributor = _distributor;
        // slither-disable-next-line missing-zero-check
        beaconDepositContract = _beaconDepositContract;

        beacon = address(new UpgradeableBeacon(_governance, _vaultImpl));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          ADMIN                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    /// @inheritdoc IRewardVaultFactory_V1
    function setBGTIncentiveDistributor(address _bgtIncentiveDistributor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_bgtIncentiveDistributor == address(0)) ZeroAddress.selector.revertWith();
        emit BGTIncentiveDistributorSet(_bgtIncentiveDistributor, bgtIncentiveDistributor);
        bgtIncentiveDistributor = _bgtIncentiveDistributor;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        VAULT CREATION                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRewardVaultFactory_V1
    function createRewardVault(address stakingToken) external returns (address) {
        address cachedAddress = getVault[stakingToken];
        if (cachedAddress != address(0)) return cachedAddress;

        // Check the code size of the staking token.
        if (stakingToken.code.length == 0) NotAContract.selector.revertWith();

        // Use solady library to deploy deterministic clone of vaultImpl.
        bytes32 salt;
        assembly ("memory-safe") {
            mstore(0, stakingToken)
            salt := keccak256(0, 0x20)
        }
        address vault = LibClone.deployDeterministicERC1967BeaconProxy(beacon, salt);

        // Store the vault in the mapping and array.
        getVault[stakingToken] = vault;
        allVaults.push(vault);
        emit VaultCreated(stakingToken, vault);

        // Initialize the vault.
        RewardVault_V6(vault).initialize(beaconDepositContract, bgt, distributor, stakingToken);

        return vault;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          READS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRewardVaultFactory_V1
    function predictRewardVaultAddress(address stakingToken) external view returns (address) {
        bytes32 salt;
        assembly ("memory-safe") {
            mstore(0, stakingToken)
            salt := keccak256(0, 0x20)
        }
        return LibClone.predictDeterministicAddressERC1967BeaconProxy(beacon, salt, address(this));
    }

    /// @inheritdoc IRewardVaultFactory_V1
    function allVaultsLength() external view returns (uint256) {
        return allVaults.length;
    }
}
