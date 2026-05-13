// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

/// @title IWBERA
/// @notice Interface for the Wrapped BERA (WBERA) contract based on Solady's WETH implementation.
interface IWBERA is IERC20Metadata {
    /// @notice Deposits BERA and mints WBERA to the caller.
    function deposit() external payable;

    /// @notice Burns WBERA and withdraws BERA to the caller.
    /// @param amount Amount of WBERA to burn/BERA to withdraw.
    function withdraw(uint256 amount) external;
}
