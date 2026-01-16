// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ILSTAdapter } from "src/pol/interfaces/lst/ILSTAdapter.sol";
import { WBERA } from "src/WBERA.sol";
import { MockLST } from "./MockLST.sol";

contract MockLSTAdapter is ILSTAdapter {
    address payable public constant WBERA_ADDR = payable(0x6969696969696969696969696969696969696969);
    MockLST lst;

    constructor(address lst_) {
        lst = MockLST(lst_);
    }

    /// @inheritdoc ILSTAdapter
    function getRate() external view returns (uint256) {
        return 1e36 / lst.previewDeposit(1e18);
    }

    /// @inheritdoc ILSTAdapter
    function stake(uint256 amount) external returns (uint256) {
        WBERA(WBERA_ADDR).transferFrom(msg.sender, address(this), amount);
        WBERA(WBERA_ADDR).approve(address(lst), amount);
        uint256 lstAmount = lst.deposit(amount, msg.sender);
        emit Stake(amount, lstAmount);
        return lstAmount;
    }
}
