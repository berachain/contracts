// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ILSTAdapter } from "src/pol/interfaces/lst/ILSTAdapter.sol";
import { WBERA } from "src/WBERA.sol";

interface IInfraredBeraRateProvider {
    function getRate() external view returns (uint256);
}

interface IInfraredBera {
    function rateProvider() external view returns (address rateProviderAddr);
    function mint(address receiver) external payable returns (uint256 shares);
    function previewMint(uint256 amount) external view returns (uint256 shares);
}

contract InfraredBeraAdapter is ILSTAdapter {
    WBERA public constant wbera = WBERA(payable(0x6969696969696969696969696969696969696969));
    address payable public constant INFRARED_BERA_ADDR = payable(0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5);

    constructor() { }

    /// @inheritdoc ILSTAdapter
    function getRate() external view returns (uint256) {
        return IInfraredBeraRateProvider(IInfraredBera(INFRARED_BERA_ADDR).rateProvider()).getRate();
    }

    /// @inheritdoc ILSTAdapter
    function stake(uint256 amount) external returns (uint256) {
        wbera.transferFrom(msg.sender, address(this), amount);
        wbera.withdraw(amount);

        uint256 shares = IInfraredBera(INFRARED_BERA_ADDR).previewMint(amount);
        if (shares > 0) {
            shares = IInfraredBera(INFRARED_BERA_ADDR).mint{ value: amount }(msg.sender);
            emit Stake(amount, shares);
        }

        return shares;
    }

    receive() external payable { }
}
