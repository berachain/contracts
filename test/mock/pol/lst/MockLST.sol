// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockLst
/// @notice A mock contract for the underlying LST platform for a LSTStakerVault.
contract MockLST is ERC4626 {
    using SafeERC20 for IERC20;

    address payable public constant WBERA_ADDR = payable(0x6969696969696969696969696969696969696969);

    constructor() ERC4626(IERC20(WBERA_ADDR)) ERC20("Mock LST", "mLST") { }

    function injectNative() external payable {
        uint256 amount = msg.value;
        (bool success,) = WBERA_ADDR.call{ value: amount }("");
        if (!success) {
            revert("MockLST: Failed to inject native currency");
        }
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
