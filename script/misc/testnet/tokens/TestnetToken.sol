// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "solady/src/auth/Ownable.sol";

contract TestnetToken is ERC20Permit, Ownable {
    uint8 internal immutable _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20Permit(name) ERC20(name, symbol) {
        _initializeOwner(msg.sender);
        _decimals = decimals_;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
