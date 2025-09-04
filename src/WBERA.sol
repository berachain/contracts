// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { WETH } from "solady/src/tokens/WETH.sol";

/// @title WBERA (Wrapped BERA)
/// @author Berachain Team
/// @notice An ERC20 token that wraps the native BERA token, allowing it to be used in smart contracts that
/// expect ERC20 tokens. Users can deposit BERA to receive WBERA and withdraw BERA by burning WBERA.
/// @dev Extends Solady's WETH implementation for gas efficiency. The contract maintains a 1:1 peg with BERA.
contract WBERA is WETH {
    /// @dev Returns the name of the token.
    function name() public pure override returns (string memory) {
        return "Wrapped Bera";
    }

    /// @dev Returns the symbol of the token.
    function symbol() public pure override returns (string memory) {
        return "WBERA";
    }
}
