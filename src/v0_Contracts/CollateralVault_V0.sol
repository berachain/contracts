// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ERC20 } from "solady/src/tokens/ERC20.sol";
import { ERC4626 } from "solady/src/tokens/ERC4626.sol";

import { Utils } from "../libraries/Utils.sol";
import { IHoneyErrors } from "src/honey/IHoneyErrors.sol";

/// @notice This is the ERC4626 vault for the collateral assets to mint Honey.
/// @author Berachain Team
contract CollateralVault_V0 is ERC4626, PausableUpgradeable, IHoneyErrors {
    using Utils for bytes4;

    ERC20 private _vaultAsset;
    string private _name;
    string private _symbol;
    /// @notice The address of the honey factory that created this vault.
    address public factory;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address asset_, address _factory) external initializer {
        __Pausable_init();

        __CollateralVault_init(asset_, _factory);
    }

    function __CollateralVault_init(address asset_, address _factory) internal onlyInitializing {
        // Check for zero addresses.
        // No need to check for zero asset address,
        // _asset.name(), _asset.symbol() will revert with `EvmError` if asset is zero address.
        if (_factory == address(0)) ZeroAddress.selector.revertWith();
        factory = _factory;
        ERC20 _asset = ERC20(asset_);
        _vaultAsset = _asset;
        _name = string.concat(_asset.name(), "Vault");
        _symbol = string.concat(_asset.symbol(), "Vault");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Throws if called by any account other than the factory.
    modifier onlyFactory() {
        _checkFactory();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Pauses the vault.
    /// @dev Only the factory can call this function.
    function pause() external onlyFactory {
        _pause();
    }

    /// @notice Unpauses the vault.
    /// @dev Only the factory can call this function.
    function unpause() external onlyFactory {
        _unpause();
    }

    /**
     * @dev A wrapper to ERC4626.deposit that only VaultAdmin can call.
     * @dev It is a protection against inflation attacks,
     * @dev in which only VaultAdmin can mint/burn shares.
     * @param assets The assets to deposit into the vault to receive shares.
     * @param receiver The address that will receive the shares.
     * @return shares The shares minted to deposit the assets.
     */
    function deposit(uint256 assets, address receiver) public override onlyFactory whenNotPaused returns (uint256) {
        return super.deposit(assets, receiver);
    }

    /**
     * @dev A wrapper to ERC4626.mint that only VaultAdmin can call.
     * @dev It is a protection against inflation attacks,
     * @dev in which only VaultAdmin can mint/burn shares.
     * @param shares The exact shares to mint by depositing the assets.
     * @param receiver The address that will receive the shares.
     * @return assets The assets required to mint the shares.
     */
    function mint(uint256 shares, address receiver) public override onlyFactory whenNotPaused returns (uint256) {
        return super.mint(shares, receiver);
    }

    /**
     * @dev A wrapper to ERC4626.withdraw that only VaultAdmin can call.
     * @dev It is a protection against inflation attacks,
     * @dev in which only VaultAdmin can mint/burn shares.
     * @param assets The exact assets to withdraw from the vault.
     * @param receiver The address that will receive the assets.
     * @param owner The address that will burn the shares.
     * @return shares The shares burned to withdraw the assets.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    )
        public
        override
        onlyFactory
        whenNotPaused
        returns (uint256)
    {
        return super.withdraw(assets, receiver, owner);
    }

    /**
     * @dev A wrapper to ERC4626.redeem that only VaultAdmin can call.
     * @dev It is a protection against inflation attacks,
     * @dev in which only VaultAdmin can mint/burn shares.
     * @param shares The shares to redeem for the assets.
     * @param receiver The address that will receive the assets.
     * @param owner The address that will burn the shares.
     * @return assets The assets redeemed from the vault.
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    )
        public
        override
        onlyFactory
        whenNotPaused
        returns (uint256)
    {
        return super.redeem(shares, receiver, owner);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          GETTERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function asset() public view virtual override returns (address) {
        return address(_vaultAsset);
    }

    function convertToAssets(uint256 shares) public view override returns (uint256) {
        return _convertToAssets(shares);
    }

    function convertToShares(uint256 assets) public view override returns (uint256) {
        return _convertToShares(assets);
    }

    /**
     * @dev An implementation of ERC4626.totalAssets to avoid inflation attacks,
     * @dev which returns the total assets that VaultAdmin transferred to the vault.
     */
    function totalAssets() public view override returns (uint256) {
        // This is another layer of protection against inflation attacks.
        // ERC4626 uses this function to calculate the exchange rate.
        // Because only VaultAdmin can mint/burn shares via deposit/mint,
        // the total assets transferred by VaultAdmin into this vault
        // must be always equal to the total supply of the shares.
        // Therefore, the assets/shares exchange rate is always 1.
        // Attackers or users can transfer assets directly into this vault
        // (thus the total assets is always greater than or equal the total supply),
        // but that will not change the total assets returned by this
        // function, thus the exchange rate is not changed.
        //
        // We also need to consider the difference in decimals
        // between the vault and the asset to ensure that
        // 10^assetDecimals asset_wei ~ 10^vaultDecimals vault_wei.
        // asset_wei_totalAssets ~ vault_wei_totalSupply / 10**(vaultDecimals - assetDecimals)
        return _convertToAssets(totalSupply());
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc ERC4626
    function _initialConvertToShares(uint256 assets) internal view override returns (uint256 shares) {
        return _convertToShares(assets);
    }

    /// @inheritdoc ERC4626
    function _initialConvertToAssets(uint256 shares) internal view override returns (uint256 assets) {
        return _convertToAssets(shares);
    }

    /**
     * @dev Convert the assets to shares with decimals in consideration,
     * but out of the ERC4626's logic to enforce the fixed exchange rate
     * between Honey, shares, and assets.
     * @param assets The assets to convert to shares.
     * @return shares The shares converted from the assets.
     */
    function _convertToShares(uint256 assets) private view returns (uint256 shares) {
        uint8 vaultDecimals = decimals();
        uint8 assetDecimals = _vaultAsset.decimals();
        uint256 exponent;
        if (vaultDecimals >= assetDecimals) {
            unchecked {
                exponent = vaultDecimals - assetDecimals;
            }
            return assets * (10 ** exponent);
        }
        unchecked {
            exponent = assetDecimals - vaultDecimals;
        }
        return assets / (10 ** exponent);
    }

    /**
     * @dev Convert the assets to shares with decimals in consideration,
     * but out of the ERC4626's logic to enforce the fixed exchange rate
     * between Honey, shares, and assets.
     * @param shares The shares to convert to assets.
     * @return assets The assets converted from the shares.
     */
    function _convertToAssets(uint256 shares) private view returns (uint256 assets) {
        uint8 vaultDecimals = decimals();
        uint8 assetDecimals = _vaultAsset.decimals();
        uint256 exponent;
        if (vaultDecimals >= assetDecimals) {
            unchecked {
                exponent = vaultDecimals - assetDecimals;
            }
            return shares / (10 ** exponent);
        }
        unchecked {
            exponent = assetDecimals - vaultDecimals;
        }
        return shares * (10 ** exponent);
    }

    /// @inheritdoc ERC4626
    function _useVirtualShares() internal pure override returns (bool) {
        return false;
    }

    /// @inheritdoc PausableUpgradeable
    function _requireNotPaused() internal view override {
        if (paused()) VaultPaused.selector.revertWith(asset());
    }

    function _checkFactory() internal view {
        if (msg.sender != factory) {
            NotFactory.selector.revertWith();
        }
    }
}
