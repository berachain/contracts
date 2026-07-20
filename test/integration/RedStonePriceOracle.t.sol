// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { Salt } from "src/base/Salt.sol";
import { IPriceOracle } from "src/extras/IPriceOracle.sol";
import { RedStonePriceOracle, IRedStonePriceFeedAdapter } from "src/extras/RedStonePriceOracle.sol";
import { RedStonePriceOracleDeployer } from "src/extras/RedStonePriceOracleDeployer.sol";

/// @title RedStonePriceOracleIntegrationTest
/// @notice Fork tests for RedStonePriceOracle on Berachain mainnet.
contract RedStonePriceOracleIntegrationTest is Create2Deployer, Test {
    /// @dev Mainnet RedStone price feed adapter (multi-feed) — sourced from
    /// `script/oracles/deployment/5_DeployRedStonePriceOracle.s.sol`.
    address constant REDSTONE_FEED_ADAPTER = 0x24c8964338Deb5204B096039147B8e8C3AEa42Cc;

    address constant USDT = 0x779Ded0c9e1022225f8E0630b35a9b54bE713736;
    address constant USDC = 0x549943e04f40284185054145c6E4e9568C1D3241;
    address constant USDe = 0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34;

    bytes32 constant USDT_FEED = bytes32("USDT");
    bytes32 constant USDC_FEED = bytes32("USDC");
    bytes32 constant USDe_FEED = bytes32("USDe");

    address governance = 0xD13948F99525FB271809F45c268D72a3C00a568D;
    uint256 forkBlock = 21_990_674;

    RedStonePriceOracle oracle;

    function setUp() public virtual {
        vm.createSelectFork("berachain");
        vm.rollFork(forkBlock);

        // Deploy via the deployer contract (matches production deployment path).
        RedStonePriceOracleDeployer deployer =
            new RedStonePriceOracleDeployer(governance, REDSTONE_FEED_ADAPTER, Salt({ implementation: 0, proxy: 0 }));
        oracle = deployer.oracle();

        // Register feeds for the three stablecoins as governance (DEFAULT_ADMIN_ROLE).
        vm.startPrank(governance);
        oracle.setDataFeedId(USDT, USDT_FEED);
        oracle.setDataFeedId(USDC, USDC_FEED);
        oracle.setDataFeedId(USDe, USDe_FEED);
        vm.stopPrank();
    }

    function test_Fork() public view {
        assertEq(block.chainid, 80_094);
        assertEq(block.number, forkBlock);
        assertEq(block.timestamp, 1_780_996_064);
    }

    function test_Deployment() public view {
        assertEq(address(oracle.redstonePriceFeedAdapter()), REDSTONE_FEED_ADAPTER);
        assertTrue(oracle.hasRole(oracle.DEFAULT_ADMIN_ROLE(), governance));
        assertEq(oracle.dataFeedIds(USDT), USDT_FEED);
        assertEq(oracle.dataFeedIds(USDC), USDC_FEED);
        assertEq(oracle.dataFeedIds(USDe), USDe_FEED);
    }

    function test_GetPrice_USDT() public view {
        _assertStablecoinPrice(USDT, USDT_FEED);
    }

    function test_GetPrice_USDC() public view {
        _assertStablecoinPrice(USDC, USDC_FEED);
    }

    function test_GetPrice_USDe() public view {
        _assertStablecoinPrice(USDe, USDe_FEED);
    }

    function test_GetPriceUnsafe_AllFeeds() public view {
        _assertUnsafeMatchesAdapter(USDT, USDT_FEED);
        _assertUnsafeMatchesAdapter(USDC, USDC_FEED);
        _assertUnsafeMatchesAdapter(USDe, USDe_FEED);
    }

    function test_PriceAvailable() public view {
        assertTrue(oracle.priceAvailable(USDT));
        assertTrue(oracle.priceAvailable(USDC));
        assertTrue(oracle.priceAvailable(USDe));
        // Unregistered asset has no feed
        assertFalse(oracle.priceAvailable(address(0xdead)));
    }

    /// @dev `getPriceUnsafe` and `getPrice` wrap the same underlying value — they must agree.
    function test_GetPriceUnsafe_EqualsGetPrice() public view {
        _assertUnsafeEqualsSafe(USDT);
        _assertUnsafeEqualsSafe(USDC);
        _assertUnsafeEqualsSafe(USDe);
    }

    /// @dev RedStone stablecoin feeds typically update on a multi-hour heartbeat, so requesting
    /// a price no older than 1 hour should revert for all three stablecoins at this fork block.
    function test_GetPriceNoOlderThan_RevertsAt1Hour() public {
        _assertNoOlderThanReverts(USDT, 1 hours);
        _assertNoOlderThanReverts(USDC, 1 hours);
        _assertNoOlderThanReverts(USDe, 1 hours);
    }

    /// @dev Same as above but with a 6 hour staleness tolerance — still expected to revert at this
    /// fork block because the feeds were last pushed more than 6 hours ago.
    function test_GetPriceNoOlderThan_RevertsAt6Hours() public {
        _assertNoOlderThanReverts(USDT, 6 hours);
        _assertNoOlderThanReverts(USDC, 6 hours);
        _assertNoOlderThanReverts(USDe, 6 hours);
    }

    /// @dev With a large tolerance (2 days), the call should succeed and return the same
    /// data as `getPriceUnsafe`.
    function test_GetPriceNoOlderThan_SucceedsWithLargeAge() public view {
        for (uint256 i = 0; i < 3; ++i) {
            address asset = [USDT, USDC, USDe][i];
            IPriceOracle.Data memory withAge = oracle.getPriceNoOlderThan(asset, 2 days);
            IPriceOracle.Data memory unsafe = oracle.getPriceUnsafe(asset);
            assertEq(withAge.price, unsafe.price);
            assertEq(withAge.publishTime, unsafe.publishTime);
        }
    }

    /// @dev Verifies that the oracle returns the price in WAD (18 decimals) and that the value
    /// is approximately $1 (within +/- 2%) — appropriate for a USD-pegged stablecoin feed.
    function _assertStablecoinPrice(address asset, bytes32 feed) internal view {
        IPriceOracle.Data memory data = oracle.getPrice(asset);

        // Raw adapter value is 8 decimals; oracle returns 18 decimals (factor of 1e10).
        (, uint256 lastBlockTimestamp, uint256 rawValue) =
            IRedStonePriceFeedAdapter(REDSTONE_FEED_ADAPTER).getLastUpdateDetails(feed);
        assertEq(data.price, rawValue * 1e10, "price not scaled to 18 decimals");
        assertEq(data.publishTime, lastBlockTimestamp, "publishTime mismatch");

        // Sanity: the returned 18-decimal price must be in the same order of magnitude as 1e18,
        // and clearly larger than what a 8-decimal value would be.
        assertGt(data.price, 0.98e18, "stablecoin price too low");
        assertLt(data.price, 1.02e18, "stablecoin price too high");
        assertGt(data.price, 1e9, "price not scaled up from 8 decimals");
    }

    /// @dev Verifies `getPriceUnsafe` against the adapter's unsafe getter with 1e10 scaling.
    function _assertUnsafeMatchesAdapter(address asset, bytes32 feed) internal view {
        IPriceOracle.Data memory data = oracle.getPriceUnsafe(asset);
        (, uint256 lastBlockTimestamp, uint256 rawValue) =
            IRedStonePriceFeedAdapter(REDSTONE_FEED_ADAPTER).getLastUpdateDetailsUnsafe(feed);
        assertEq(data.price, rawValue * 1e10);
        assertEq(data.publishTime, lastBlockTimestamp);
    }

    function _assertUnsafeEqualsSafe(address asset) internal view {
        IPriceOracle.Data memory safe = oracle.getPrice(asset);
        IPriceOracle.Data memory unsafe = oracle.getPriceUnsafe(asset);
        assertEq(safe.price, unsafe.price, "price mismatch between safe and unsafe");
        assertEq(safe.publishTime, unsafe.publishTime, "publishTime mismatch between safe and unsafe");
    }

    function _assertNoOlderThanReverts(address asset, uint256 age) internal {
        vm.expectRevert(abi.encodeWithSelector(IPriceOracle.UnavailableData.selector, asset));
        oracle.getPriceNoOlderThan(asset, age);
    }
}
