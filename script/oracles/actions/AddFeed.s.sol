// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { PythPriceOracle } from "src/extras/PythPriceOracle.sol";
import { AddressBook } from "../../base/AddressBook.sol";
import { PYUSDC_ADDRESS, USDC_ADDRESS } from "../../misc/Addresses.sol";

/// @notice Creates a collateral vault for the given token.
contract AddFeedScript is BaseScript, AddressBook {
    bytes32 constant USDC_PYTH_FEED = bytes32(0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a);
    bytes32 constant PYUSD_PYTH_FEED = bytes32(0xc1da1b73d7f01e7ddd54b3766cf7fcd644395ad14f70aa706ec5384c59e76692);

    function run() public virtual broadcast {
        require(USDC_PYTH_FEED != bytes32(0), "USDC_PYTH_FEED not set");
        require(PYUSD_PYTH_FEED != bytes32(0), "PYUSD_PYTH_FEED not set");
        _validateCode("PythPriceOracle", _oraclesAddresses.pythPriceOracle);
        PythPriceOracle pythPriceOracle = PythPriceOracle(_oraclesAddresses.pythPriceOracle);

        bool grantedRole = false;
        if (!pythPriceOracle.hasRole(pythPriceOracle.MANAGER_ROLE(), msg.sender)) {
            grantedRole = true;
            pythPriceOracle.grantRole(pythPriceOracle.MANAGER_ROLE(), msg.sender);
        }

        setPriceFeed("USDC", USDC_ADDRESS, USDC_PYTH_FEED);
        setPriceFeed("PYUSD", PYUSDC_ADDRESS, PYUSD_PYTH_FEED);

        if (grantedRole) {
            pythPriceOracle.revokeRole(pythPriceOracle.MANAGER_ROLE(), msg.sender);
        }
    }

    /// @dev requires MANAGER_ROLE to be granted to msg.sender
    function setPriceFeed(string memory assetName, address asset, bytes32 feed) internal {
        PythPriceOracle pythPriceOracle = PythPriceOracle(_oraclesAddresses.pythPriceOracle);
        console2.log(string.concat("Setting feed for ", assetName, " (%s):"), asset);
        pythPriceOracle.setPriceFeed(asset, feed);
        require(pythPriceOracle.feeds(asset) == feed, "Failed to set feed");
        require(pythPriceOracle.priceAvailable(asset) == true, "Price not available");
        console2.log("Feed set to:");
        console2.logBytes32(feed);
        console2.log("-------");
    }
}
