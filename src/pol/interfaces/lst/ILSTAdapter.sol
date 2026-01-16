// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IPOLErrors } from "../IPOLErrors.sol";

interface ILSTAdapter {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a WBERA amount is converted to the associated LST.
    /// @param amountBera The amount of BERA being swapped.
    /// @param amountLST The amount of LST received.
    event Stake(uint256 amountBera, uint256 amountLST);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         FUNCTIONS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Gets the current exchange rate between the LST and the native token.
    /// @return The rate LST/BERA (18 decimals).
    function getRate() external view returns (uint256);

    /// @notice Stakes the given WBERA amount for LST.
    /// @return The amount of LST received.
    function stake(uint256 amount) external returns (uint256);
}
