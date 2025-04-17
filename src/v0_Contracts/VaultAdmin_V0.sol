// SPDX-License-Identifier: BUSL-1.1
// To support named parameters in mapping types and custom operators for user-defined value types.
pragma solidity 0.8.26;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { LibClone } from "solady/src/utils/LibClone.sol";
import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";

import { IHoneyErrors } from "src/honey/IHoneyErrors.sol";
import { Utils } from "../libraries/Utils.sol";
import { CollateralVault_V0 } from "./CollateralVault_V0.sol";

/// @notice This is the admin contract that manages the vaults and fees.
/// @author Berachain Team
abstract contract VaultAdmin_V0 is AccessControlUpgradeable, PausableUpgradeable, UUPSUpgradeable, IHoneyErrors {
    using Utils for bytes4;

    /// @notice Emitted when the fee receiver address is set.
    event FeeReceiverSet(address indexed feeReceiver);

    /// @notice Emitted when the POL Fee Collector address is set.
    event POLFeeCollectorSet(address indexed polFeeCollector);

    /// @notice Emitted when a new vault is created.
    event VaultCreated(address indexed vault, address indexed asset);

    /// @notice Emitted when collateral asset status is set.
    event CollateralAssetStatusSet(address indexed asset, bool isBadCollateral);

    /// @notice Emitted when a collected fee is withdrawn.
    event CollectedFeeWithdrawn(address indexed asset, address indexed receiver, uint256 shares, uint256 assets);

    /// @notice Emitted when a price feed is changed.
    event PriceFeedChanged(address indexed asset, bytes32 id);

    /// @notice The MANAGER role.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice The PAUSER role.
    /// @dev This role is used to only pause the factory and vaults.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice The beacon address.
    address public beacon;

    /// @notice The address of the fee receiver.
    address public feeReceiver;

    /// @notice The address of the POL Fee Collector.
    address public polFeeCollector;

    /// @notice Array of registered assets.
    address[] public registeredAssets;

    /// @notice Mapping of assets to their corresponding vaults.
    mapping(address asset => CollateralVault_V0 vault) public vaults;

    /// @notice Mapping of bad collateral assets.
    mapping(address asset => bool badCollateral) public isBadCollateralAsset;

    /// @notice Mapping of receiver to asset to collected fee.
    /// @dev Stores the shares of fees corresponding to the receiver that are not yet redeemed.
    mapping(address receiver => mapping(address asset => uint256 collectedFee)) public collectedFees;

    /// @dev Stores the shares of fees for each asset that are not yet redeemed.
    mapping(address asset => uint256 collectedFee) internal collectedAssetFees;

    /// @dev This gap is used to prevent storage collisions.
    uint256[49] private __gap;
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         INITIALIZER                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Must be called by the initializer of the inheriting contract.
    /// @param _governance The address of the governance.
    /// @param _feeReceiver The address of the fee receiver.
    /// @param _polFeeCollector The address of the POL Fee Collector.
    function __VaultAdmin_init(
        address _governance,
        address _polFeeCollector,
        address _feeReceiver
    )
        internal
        onlyInitializing
    {
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        __VaultAdmin_init_unchained(_governance, _polFeeCollector, _feeReceiver);
        // Allow the MANAGER role to manage the PAUSER role.
        // MANAGER role can grant and revoke access for the PAUSER role.
        _setRoleAdmin(PAUSER_ROLE, MANAGER_ROLE);
    }

    function __VaultAdmin_init_unchained(
        address _governance,
        address _polFeeCollector,
        address _feeReceiver
    )
        internal
        onlyInitializing
    {
        if (_governance == address(0)) ZeroAddress.selector.revertWith();
        if (_polFeeCollector == address(0)) ZeroAddress.selector.revertWith();
        if (_feeReceiver == address(0)) ZeroAddress.selector.revertWith();

        beacon = address(new UpgradeableBeacon(_governance, address(new CollateralVault_V0())));
        _grantRole(DEFAULT_ADMIN_ROLE, _governance);

        feeReceiver = _feeReceiver;
        polFeeCollector = _polFeeCollector;
        emit FeeReceiverSet(_feeReceiver);
        emit POLFeeCollectorSet(_polFeeCollector);
    }

    /// @notice Check if the asset is registered.
    function _checkRegisteredAsset(address asset) internal view {
        if (address(vaults[asset]) == address(0)) {
            AssetNotRegistered.selector.revertWith(asset);
        }
    }

    /// @notice Check if the asset is not a bad collateral.
    function _checkGoodCollateralAsset(address asset) internal view {
        if (isBadCollateralAsset[asset]) {
            AssetIsBadCollateral.selector.revertWith(asset);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _authorizeUpgrade(address newImplementation) internal virtual override {
        // Silent warning
        newImplementation;
        _checkRole(DEFAULT_ADMIN_ROLE);
    }

    /// @notice Pause the contract.
    /// @dev Only the PAUSER role can call this function.
    function pause() external {
        _checkRole(PAUSER_ROLE);
        _pause();
    }

    /// @notice Unpause the contract.
    /// @dev only the MANAGER role can call this function.
    function unpause() external {
        _checkRole(MANAGER_ROLE);
        _unpause();
    }

    /// @notice Pause the vault for a given asset.
    /// @dev Only the PAUSER role can call this function.
    /// @dev Only registered assets can be paused.
    /// @param asset The address of the asset.
    function pauseVault(address asset) external {
        _checkRole(PAUSER_ROLE);
        _checkRegisteredAsset(asset);
        CollateralVault_V0(address(vaults[asset])).pause();
    }

    /// @notice Unpause the vault for a given asset.
    /// @dev Only the MANAGER role can call this function.
    /// @dev Only registered assets can be unpaused.
    /// @param asset The address of the asset.
    function unpauseVault(address asset) external {
        _checkRole(MANAGER_ROLE);
        _checkRegisteredAsset(asset);
        CollateralVault_V0(address(vaults[asset])).unpause();
    }

    function _createVault(address asset) internal returns (CollateralVault_V0) {
        _checkRole(DEFAULT_ADMIN_ROLE);
        // Revert if the vault for the given asset is already registered.
        if (address(vaults[asset]) != address(0)) {
            VaultAlreadyRegistered.selector.revertWith(asset);
        }
        // Register the asset.
        registeredAssets.push(asset);

        // Use solady library to deploy deterministic beacon proxy.
        // NOTE: bits not part of the encoding of the address type cannot be assumed to be zero
        bytes32 salt;
        assembly ("memory-safe") {
            mstore(0, shr(96, shl(96, asset)))
            salt := keccak256(0, 0x20)
        }
        CollateralVault_V0 vault = CollateralVault_V0(LibClone.deployDeterministicERC1967BeaconProxy(beacon, salt));
        vault.initialize(asset, address(this));

        vaults[asset] = vault;
        emit VaultCreated(address(vault), address(asset));
        return vault;
    }

    /// @notice Set the fee receiver address.
    /// @dev Only the default admin role can call this function.
    /// @dev Reverts if the fee receiver address is zero address.
    /// @param _feeReceiver The address of the fee receiver.
    function setFeeReceiver(address _feeReceiver) external {
        _checkRole(DEFAULT_ADMIN_ROLE);
        if (_feeReceiver == address(0)) ZeroAddress.selector.revertWith();
        feeReceiver = _feeReceiver;
        emit FeeReceiverSet(_feeReceiver);
    }

    /// @notice Set the POL Fee Collector address.
    /// @dev Only the default admin role can call this function.
    /// @dev Reverts if the POL Fee Collector address is zero address.
    /// @param _polFeeCollector The address of the POL Fee Collector.
    function setPOLFeeCollector(address _polFeeCollector) external {
        _checkRole(DEFAULT_ADMIN_ROLE);
        if (_polFeeCollector == address(0)) ZeroAddress.selector.revertWith();
        polFeeCollector = _polFeeCollector;
        emit POLFeeCollectorSet(_polFeeCollector);
    }

    /// @notice Set the bad collateral status of an asset.
    /// @dev Only the manager role can call this function.
    /// @dev Only registered assets can be set as bad collateral.
    /// @dev If set to true, minting will be disabled for the asset.
    /// @param asset The address of the asset.
    /// @param _isBadCollateral The status of the asset.
    function setCollateralAssetStatus(address asset, bool _isBadCollateral) external {
        _checkRole(MANAGER_ROLE);
        _checkRegisteredAsset(asset);

        isBadCollateralAsset[asset] = _isBadCollateral;
        emit CollateralAssetStatusSet(asset, _isBadCollateral);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        FEE RELATED                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Withdraw all the collected fees for a `receiver`.
    /// @dev It loops over all the registered assets and withdraws the collected fees.
    /// @param receiver The address of the receiver.
    function withdrawAllFees(address receiver) external {
        uint256 numAssets = numRegisteredAssets();
        for (uint256 i; i < numAssets;) {
            address asset = registeredAssets[i];
            _withdrawCollectedFee(asset, receiver);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Withdraw the collected fees for a `receiver` for a specific `asset`.
    function withdrawFee(address asset, address receiver) external returns (uint256 assets) {
        _checkRegisteredAsset(asset);
        assets = _withdrawCollectedFee(asset, receiver);
    }

    /// @notice Internal function to withdraw the collected fees.
    /// @dev Redeems the shares from the vault and transfers the assets to the receiver.
    /// @param asset The address of the asset.
    /// @param receiver The address of the receiver.
    /// @return assets The amount of assets redeemed.
    function _withdrawCollectedFee(address asset, address receiver) internal returns (uint256 assets) {
        uint256 shares = collectedFees[receiver][asset];

        if (vaults[asset].convertToAssets(shares) == 0) {
            return 0;
        }

        collectedFees[receiver][asset] = 0;
        // All the shares refer to the receiver and the assets are transferred to the receiver.
        // This subtraction is safe because of they are counted in the same function.
        collectedAssetFees[asset] -= shares;

        assets = vaults[asset].redeem(shares, receiver, address(this));
        emit CollectedFeeWithdrawn(asset, receiver, shares, assets);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          GETTERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Get the length of `registeredAssets` array.
    function numRegisteredAssets() public view returns (uint256) {
        return registeredAssets.length;
    }

    function _lookupRegistrationIndex(address asset) internal view returns (uint256 index) {
        for (uint256 i = 0; i < registeredAssets.length; i++) {
            if (registeredAssets[i] == asset) {
                return i;
            }
        }
    }
}
