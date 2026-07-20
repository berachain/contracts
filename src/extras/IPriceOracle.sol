// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

/// @title Provide asset prices in USD with WAD precision
/// @dev Generic interface that wraps the Pyth oracle and redstone price oracle
interface IPriceOracle {
    /// @dev TBD whether to also return a confidence interval.
    struct Data {
        // Price with WAD precision
        uint256 price;
        // Unix timestamp describing when the price was published
        uint256 publishTime;
    }

    // Signature: 0xd92e233d
    error ZeroAddress();
    error UnavailableData(address asset);

    /// @notice Returns the price in USD.
    /// @dev Reverts if the price has not been recently updated (implementation defined).
    /// @param asset The asset of which to fetch the price.
    /// @return data
    function getPrice(address asset) external view returns (Data memory data);

    /// @notice Returns the price without any sanity checks.
    /// @dev This function returns the most recent price update in this contract without any recency checks.
    /// This function is unsafe as the returned price update may be arbitrarily far in the past.
    ///
    /// Users of this function should check the `publishTime` to ensure that the returned price is
    /// sufficiently recent for their application. If you are considering using this function, it may be
    /// safer / easier to use either `getPrice` or `getPriceNoOlderThan`.
    /// @return data
    function getPriceUnsafe(address asset) external view returns (Data memory data);

    /// @notice Returns the price that is no older than `age` seconds of the current time.
    /// @dev This function is a sanity-checked version of `getPriceUnsafe` which is useful in
    /// applications that require a sufficiently-recent price. Reverts if the price wasn't updated sufficiently
    /// recently.
    /// @return data
    function getPriceNoOlderThan(address asset, uint256 age) external view returns (Data memory data);

    /// @notice Returns whether a price is available or not.
    function priceAvailable(address asset) external view returns (bool);
}
