// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { BUSDFactory } from "src/busd/BUSDFactory.sol";
import { BUSDFactoryReader } from "src/busd/BUSDFactoryReader.sol";
import { AddressBook } from "../../base/AddressBook.sol";

/// @notice Add collateral to vault and mint BUSD
contract MintBUSDScript is BaseScript, AddressBook {
    // Placeholders. Change before run script.
    string internal constant COLLATERAL_NAME = "COLLATERAL_NAME";
    address internal constant COLLATERAL_ADDRESS = address(0);
    uint256 internal constant AMOUNT = 1e10;

    /// @dev msg.send need to have enough collateral balance
    function run() public virtual broadcast {
        _validateCode("BUSD", _busdAddresses.busd);
        _validateCode("BUSDFactory", _busdAddresses.busdFactory);
        require(COLLATERAL_ADDRESS != address(0), "COLLATERAL_ADDRESS not set");
        _validateCode(COLLATERAL_NAME, COLLATERAL_ADDRESS);

        IERC20 collateralToken = IERC20(COLLATERAL_ADDRESS);
        uint256 amount = AMOUNT * (10 ** collateralToken.decimals());
        require(collateralToken.balanceOf(msg.sender) >= amount, "Insufficient collateral balance");

        // TODO: review after v2 merge
        mintBUSD(_busdAddresses.busdFactory, _busdAddresses.busdFactoryReader, COLLATERAL_ADDRESS, amount, msg.sender);
        require(IERC20(_busdAddresses.busd).balanceOf(msg.sender) >= amount, "Failed to mint BUSD");
        console2.log("BUSD balance of %s: %d", msg.sender, IERC20(_busdAddresses.busd).balanceOf(msg.sender));
    }

    /// @dev Mint BUSD using collateral
    function mintBUSD(
        address busdFactory,
        address busdFactoryReader,
        address collateral,
        uint256 amount,
        address to
    )
        internal
        returns (uint256 mintedAmount)
    {
        BUSDFactory _busdFactory = BUSDFactory(busdFactory);
        // Check if basket mode is enable.
        bool isBasketModeEnabled = _busdFactory.isBasketModeEnabled(true);
        if (isBasketModeEnabled) {
            console2.log("Basket mode is enabled.");
            uint256[] memory amounts = BUSDFactoryReader(busdFactoryReader).previewMintCollaterals(collateral, amount);

            for (uint256 i = 0; i < amounts.length; i++) {
                // If the asset is the one used to mint BUSD, adjust its amount.
                if (_busdFactory.registeredAssets(i) == collateral) {
                    amount = amounts[i];
                }
                if (amounts[i] == 0) {
                    continue;
                }
                IERC20(_busdFactory.registeredAssets(i)).approve(busdFactory, amounts[i]);
                console2.log("Approved %d of token %d for busdFactory", i, amount);
            }
        } else {
            IERC20(collateral).approve(busdFactory, amount);
            console2.log("Approved %d tokens for busdFactory", amount);
        }

        mintedAmount = BUSDFactory(busdFactory).mint(collateral, amount, to, isBasketModeEnabled);
        console2.log("Minted %d BUSD to %s", mintedAmount, to);
    }
}
