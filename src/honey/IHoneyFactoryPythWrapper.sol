// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

/// @notice Interface of HoneyFactoryPythWrapper.
/// @author Berachain Team
interface IHoneyFactoryPythWrapper {
    /// @notice Emitted when the Pyth oracle is updated.
    /// @param fee The fee paid for the Pyth oracle update.
    event PythOracleUpdated(uint256 fee);

    /// @notice HoneyFactory mint with price update.
    /// @dev Function is payable so that user can directly pay the Pyth update fee.
    /// @param updateData The signed collaterals prices to update Pyth oracle.
    /// @param amount The amount of ERC20 to mint with.
    /// @param receiver The address that will receive Honey.
    /// @param expectBasketMode Expectation of the basket mode status.
    /// @return The amount of Honey minted.
    /// @dev The expectBasketMode flag avoid behavioral issues that may happen when the basket mode status changes
    /// after the client signed its transaction.
    function mint(
        bytes[] calldata updateData,
        address asset,
        uint256 amount,
        address receiver,
        bool expectBasketMode
    )
        external
        payable
        returns (uint256);

    /// @notice HoneyFactory redeem with price update.
    /// @dev Function is payable so that user can directly pay the Pyth update fee.
    /// @param updateData The signed collaterals prices to update Pyth oracle.
    /// @param honeyAmount The amount of Honey to redeem.
    /// @param receiver The address that will receive assets.
    /// @param expectBasketMode Expectation of the basket mode status.
    /// @return The amount of assets redeemed.
    function redeem(
        bytes[] calldata updateData,
        address asset,
        uint256 honeyAmount,
        address receiver,
        bool expectBasketMode
    )
        external
        payable
        returns (uint256[] memory);

    /// @notice HoneyFactory liquidate with price update.
    /// @dev Function is payable so that user can directly pay the Pyth update fee.
    /// @param updateData The signed collaterals prices to update Pyth oracle.
    /// @param badCollateral The ERC20 asset to liquidate.
    /// @param goodCollateral The ERC20 asset to provide in place.
    /// @param goodAmount The amount provided.
    /// @return badAmount The amount obtained.
    function liquidate(
        bytes[] calldata updateData,
        address badCollateral,
        address goodCollateral,
        uint256 goodAmount
    )
        external
        payable
        returns (uint256 badAmount);

    /// @notice HoneyFactory ricapitalize with price update.
    /// @dev Function is payable so that user can directly pay the Pyth update fee.
    /// @param updateData The signed collaterals prices to update Pyth oracle.
    /// @param asset The ERC20 asset to recapitalize.
    /// @param amount The amount provided.
    function recapitalize(bytes[] calldata updateData, address asset, uint256 amount) external payable;

    /// @notice HoneyFactory isBasketModeEnabled with externally provided price.
    /// @param isMint True if checking basket mode for minting.
    /// @param prices The prices assumed to be valid.
    function isBasketModeEnabled(bool isMint, uint256[] memory prices) external returns (bool basketMode);

    /// @notice HoneyFactory isPegged with externally provided price.
    /// @param asset The asset to check.
    /// @param price The price assumed to be valid.
    /// @return true if the asset is pegged.
    function isPegged(address asset, uint256 price) external returns (bool);
}
