// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ERC20 } from "solady/src/tokens/ERC20.sol";

abstract contract MockAsset is ERC20 {
    string internal _name;
    string internal _symbol;

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }
}

contract MockDAI is MockAsset {
    constructor() {
        _name = "MockDAI";
        _symbol = "DAI";
    }
}

contract MockUSDT is MockAsset {
    constructor() {
        _name = "MockUSDT";
        _symbol = "USDT";
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract MockDummy is MockAsset {
    constructor() {
        _name = "MockDummy";
        _symbol = "DUMMY";
    }

    function decimals() public pure override returns (uint8) {
        return 20;
    }
}
