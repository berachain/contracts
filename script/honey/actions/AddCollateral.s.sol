// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { HoneyFactory } from "src/honey/HoneyFactory.sol";
import { ERC4626 } from "solady/src/tokens/ERC4626.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { USDT_ADDRESS, DAI_ADDRESS, USDC_ADDRESS } from "../../misc/Addresses.sol";
import { AddressBook } from "../../base/AddressBook.sol";
import { IPriceOracle } from "src/extras/IPriceOracle.sol";

/// @notice Creates a collateral vault for the given token.
contract AddCollateralVaultScript is BaseScript, AddressBook {
    // Placeholders. Change before run script.
    string constant COLLATERAL_NAME = "COLLATERAL_NAME"; // "USDC" "pyUSD" - MAKE SURE TO SET ONE OF THOSE.
    address constant COLLATERAL_ADDRESS = address(0); // USDT_ADDRESS DAI_ADDRESS USDC_ADDRESS
    // REMOVE AFTER TRANSFER OWNERSHIP TO THE GOVERNANCE
    uint256 constant USDC_PEG_OFFSET = 0.001e18;
    // REMOVE AFTER TRANSFER OWNERSHIP TO THE GOVERNANCE
    uint256 constant pyUSD_RELATIVE_CAP = 0.5e18;

    function run() public virtual broadcast {
        require(COLLATERAL_ADDRESS != address(0), "COLLATERAL_ADDRESS not set");

        _validateCode("HoneyFactory", _honeyAddresses.honeyFactory);
        _validateCode(COLLATERAL_NAME, COLLATERAL_ADDRESS);
        addCollateralVault(COLLATERAL_ADDRESS);
    }

    /// @dev requires MANAGER_ROLE to be granted to msg.sender
    function addCollateralVault(address collateral) internal {
        bool isUSDC = keccak256(abi.encodePacked(COLLATERAL_NAME)) == keccak256(abi.encodePacked("USDC"));
        bool isPyUSD = keccak256(abi.encodePacked(COLLATERAL_NAME)) == keccak256(abi.encodePacked("pyUSD"));
        require(isUSDC || isPyUSD, "collateral not supported");

        _validateCode("Collateral", collateral);
        HoneyFactory honeyFactory = HoneyFactory(_honeyAddresses.honeyFactory);

        console2.log("Adding collateral %s", IERC20(collateral).symbol());

        // NOTE: the price oracle must have freshly pushed data, otherwise
        // the honey factory will consider the asset as depegged.
        IPriceOracle priceOracle = IPriceOracle(honeyFactory.priceOracle());
        IPriceOracle.Data memory data = priceOracle.getPriceUnsafe(collateral);
        require(data.publishTime >= block.timestamp - honeyFactory.priceFeedMaxDelay(), "Price data too old");

        ERC4626 vault = honeyFactory.createVault(collateral);
        console2.log("Collateral Vault deployed at:", address(vault));
        // Set mint rate to 1:1
        // Only for initial launch
        honeyFactory.setMintRate(collateral, 1e18);

        if (isUSDC) {
            // Set peg offset for USDC
            honeyFactory.setDepegOffsets(collateral, USDC_PEG_OFFSET, USDC_PEG_OFFSET);
        }
        if (isPyUSD) {
            // Set relative cap for pyUSD
            honeyFactory.setRelativeCap(collateral, pyUSD_RELATIVE_CAP);
        }
    }
}
