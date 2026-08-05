// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

/// @notice Interface of BUSDFactoryPythWrapper.
/// @author Berachain Team
interface IBUSDFactoryPythWrapper {
    /// @notice Emitted when the Pyth oracle is updated.
    /// @param fee The fee paid for the Pyth oracle update.
    event PythOracleUpdated(uint256 fee);

    /// @notice BUSDFactory mint with price update.
    /// @dev Function is payable so that user can directly pay the Pyth update fee.
    /// @param updateData The signed collaterals prices to update Pyth oracle.
    /// @param amount The amount of ERC20 to mint with.
    /// @param receiver The address that will receive BUSD.
    /// @param expectBasketMode Expectation of the basket mode status.
    /// @return The amount of BUSD minted.
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

    /// @notice BUSDFactory redeem with price update.
    /// @dev Function is payable so that user can directly pay the Pyth update fee.
    /// @param updateData The signed collaterals prices to update Pyth oracle.
    /// @param busdAmount The amount of BUSD to redeem.
    /// @param receiver The address that will receive assets.
    /// @param expectBasketMode Expectation of the basket mode status.
    /// @return The amount of assets redeemed.
    function redeem(
        bytes[] calldata updateData,
        address asset,
        uint256 busdAmount,
        address receiver,
        bool expectBasketMode
    )
        external
        payable
        returns (uint256[] memory);

    /// @notice BUSDFactory liquidate with price update.
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

    /// @notice BUSDFactory ricapitalize with price update.
    /// @dev Function is payable so that user can directly pay the Pyth update fee.
    /// @param updateData The signed collaterals prices to update Pyth oracle.
    /// @param asset The ERC20 asset to recapitalize.
    /// @param amount The amount provided.
    function recapitalize(bytes[] calldata updateData, address asset, uint256 amount) external payable;
}
