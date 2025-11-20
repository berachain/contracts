// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { HoneyFactory } from "src/honey/HoneyFactory.sol";
import { HoneyFactoryReader } from "src/honey/HoneyFactoryReader.sol";
import { AddressBook } from "../../base/AddressBook.sol";

/// @notice Add collateral to vault and mint Honey
contract MintHoneyScript is BaseScript, AddressBook {
    // Placeholders. Change before run script.
    string internal constant COLLATERAL_NAME = "COLLATERAL_NAME";
    address internal constant COLLATERAL_ADDRESS = address(0);
    uint256 internal constant AMOUNT = 1e10;

    constructor() AddressBook(_chainType) { }

    /// @dev msg.send need to have enought collateral balance
    function run() public virtual broadcast {
        _validateCode("Honey", _honeyAddresses.honey);
        _validateCode("HoneyFactory", _honeyAddresses.honeyFactory);
        require(COLLATERAL_ADDRESS != address(0), "COLLATERAL_ADDRESS not set");
        _validateCode(COLLATERAL_NAME, COLLATERAL_ADDRESS);

        IERC20 collateralToken = IERC20(COLLATERAL_ADDRESS);
        uint256 amount = AMOUNT * (10 ** collateralToken.decimals());
        require(collateralToken.balanceOf(msg.sender) >= amount, "Insufficient collateral balance");

        // TODO: review after v2 merge
        mintHoney(
            _honeyAddresses.honeyFactory, _honeyAddresses.honeyFactoryReader, COLLATERAL_ADDRESS, amount, msg.sender
        );
        require(IERC20(_honeyAddresses.honey).balanceOf(msg.sender) >= amount, "Failed to mint Honey");
        console2.log("Honey balance of %s: %d", msg.sender, IERC20(_honeyAddresses.honey).balanceOf(msg.sender));
    }

    /// @dev Mint Honey using collateral
    function mintHoney(
        address honeyFactory,
        address honeyFactoryReader,
        address collateral,
        uint256 amount,
        address to
    )
        internal
        returns (uint256 mintedAmount)
    {
        HoneyFactory _honeyFactory = HoneyFactory(honeyFactory);
        // Check if basket mode is enable.
        bool isBasketModeEnabled = _honeyFactory.isBasketModeEnabled(true);
        if (isBasketModeEnabled) {
            console2.log("Basket mode is enabled.");
            uint256[] memory amounts =
                HoneyFactoryReader(honeyFactoryReader).previewMintCollaterals(collateral, amount);

            for (uint256 i = 0; i < amounts.length; i++) {
                // If the asset is the one used to mint honey, adjust its amount.
                if (_honeyFactory.registeredAssets(i) == collateral) {
                    amount = amounts[i];
                }
                if (amounts[i] == 0) {
                    continue;
                }
                IERC20(_honeyFactory.registeredAssets(i)).approve(honeyFactory, amounts[i]);
                console2.log("Approved %d of token %d for honeyFactory", i, amount);
            }
        } else {
            IERC20(collateral).approve(honeyFactory, amount);
            console2.log("Approved %d tokens for honeyFactory", amount);
        }

        mintedAmount = HoneyFactory(honeyFactory).mint(collateral, amount, to, isBasketModeEnabled);
        console2.log("Minted %d Honey to %s", mintedAmount, to);
    }
}
