// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import { RedStonePriceOracle, IRedStonePriceFeedAdapter } from "src/extras/RedStonePriceOracle.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { IPriceOracle } from "src/extras/IPriceOracle.sol";

contract MockRedStonePriceFeedAdapter is IRedStonePriceFeedAdapter {
    struct Update {
        uint256 lastDataTimestamp;
        uint256 lastBlockTimestamp;
        uint256 lastValue;
    }

    mapping(bytes32 dataFeedId => Update update) public updates;

    function setUpdate(
        bytes32 dataFeedId,
        uint256 lastDataTimestamp,
        uint256 lastBlockTimestamp,
        uint256 lastValue
    )
        external
    {
        updates[dataFeedId] = Update(lastDataTimestamp, lastBlockTimestamp, lastValue);
    }

    function getLastUpdateDetails(bytes32 dataFeedId)
        external
        view
        returns (uint256 lastDataTimestamp, uint256 lastBlockTimestamp, uint256 lastValue)
    {
        Update memory u = updates[dataFeedId];
        return (u.lastDataTimestamp, u.lastBlockTimestamp, u.lastValue);
    }

    function getLastUpdateDetailsUnsafe(bytes32 dataFeedId)
        external
        view
        returns (uint256 lastDataTimestamp, uint256 lastBlockTimestamp, uint256 lastValue)
    {
        Update memory u = updates[dataFeedId];
        return (u.lastDataTimestamp, u.lastBlockTimestamp, u.lastValue);
    }
}

contract RedStonePriceOracleTest is Test, Create2Deployer {
    RedStonePriceOracle _redStonePriceOracle;
    MockRedStonePriceFeedAdapter _mockedAdapter;
    address _governance = makeAddr("governance");

    function setUp() public {
        RedStonePriceOracle _redStonePriceOracleImpl = new RedStonePriceOracle();
        _redStonePriceOracle = RedStonePriceOracle(deployProxyWithCreate2(address(_redStonePriceOracleImpl), 0));
        _mockedAdapter = new MockRedStonePriceFeedAdapter();
    }

    modifier initialize() {
        _redStonePriceOracle.initialize(_governance, address(_mockedAdapter));
        assert(_redStonePriceOracle.hasRole(_redStonePriceOracle.DEFAULT_ADMIN_ROLE(), _governance));
        _;
    }

    function test_initialize_zeroAddress() public {
        // Governance address cannot be zero
        vm.expectRevert(IPriceOracle.ZeroAddress.selector);
        _redStonePriceOracle.initialize(address(0), address(_mockedAdapter));

        // RedStone price feed adapter address cannot be zero
        vm.expectRevert(IPriceOracle.ZeroAddress.selector);
        _redStonePriceOracle.initialize(_governance, address(0));
    }

    function testFuzz_initialize(address governance_, address adapter_) public {
        assumeNotZeroAddress(governance_);
        assumeNotZeroAddress(adapter_);

        _redStonePriceOracle.initialize(governance_, adapter_);

        assertEq(address(_redStonePriceOracle.redstonePriceFeedAdapter()), adapter_);
        assertTrue(_redStonePriceOracle.hasRole(_redStonePriceOracle.DEFAULT_ADMIN_ROLE(), governance_));
    }

    function test_setDataFeedId() public initialize {
        address asset = makeAddr("USDC");
        bytes32 dataFeedId = "USDC";

        _setDataFeedId(asset, dataFeedId);

        assertEq(_redStonePriceOracle.dataFeedIds(asset), dataFeedId);
    }

    function test_setDataFeedId_ZeroAddress() public initialize {
        // Asset cannot be zero
        vm.prank(_governance);
        vm.expectRevert(IPriceOracle.ZeroAddress.selector);
        _redStonePriceOracle.setDataFeedId(address(0), "USDC");

        // Data feed ID cannot be zero
        vm.prank(_governance);
        vm.expectRevert(IPriceOracle.ZeroAddress.selector);
        _redStonePriceOracle.setDataFeedId(makeAddr("USDC"), bytes32(0));
    }

    function test_setDataFeedId_NotAdmin() public initialize {
        // Only DEFAULT_ADMIN_ROLE can set data feed IDs
        vm.expectRevert();
        _redStonePriceOracle.setDataFeedId(makeAddr("USDC"), "USDC");
    }

    function test_getPrice() public initialize {
        address asset = address(0x1);
        bytes32 dataFeedId = "USDC";

        // RedStone reports prices in 8 decimals. Source value 1e8 represents $1 and
        // should be returned as 1e18 in WAD precision.
        _mockedAdapter.setUpdate(dataFeedId, block.timestamp, block.timestamp, 1e8);
        _setDataFeedId(asset, dataFeedId);

        IPriceOracle.Data memory priceData = _redStonePriceOracle.getPrice(asset);
        assertEq(priceData.price, 1e18);
        assertEq(priceData.publishTime, block.timestamp);
    }

    function test_getPrice_UnavailableAsset() public initialize {
        // No data feed ID set for the asset, should revert with UnavailableData.
        vm.expectRevert(abi.encodeWithSelector(IPriceOracle.UnavailableData.selector, address(0x1)));
        _redStonePriceOracle.getPrice(address(0x1));
    }

    function test_getPriceUnsafe() public initialize {
        address asset = address(0x1);
        bytes32 dataFeedId = "USDC";

        _mockedAdapter.setUpdate(dataFeedId, block.timestamp, block.timestamp, 2e8);
        _setDataFeedId(asset, dataFeedId);

        IPriceOracle.Data memory priceData = _redStonePriceOracle.getPriceUnsafe(asset);
        assertEq(priceData.price, 2e18);
        assertEq(priceData.publishTime, block.timestamp);
    }

    function test_getPriceNoOlderThan() public initialize {
        address asset = address(0x1);
        bytes32 dataFeedId = "USDC";

        // Warp ahead so we can travel back for the publish time
        vm.warp(1_000_000);
        uint256 publishTime = block.timestamp - 100;

        _mockedAdapter.setUpdate(dataFeedId, publishTime, publishTime, 1e8);
        _setDataFeedId(asset, dataFeedId);

        // Within age tolerance
        IPriceOracle.Data memory priceData = _redStonePriceOracle.getPriceNoOlderThan(asset, 200);
        assertEq(priceData.price, 1e18);
        assertEq(priceData.publishTime, publishTime);

        // Stale data, beyond age tolerance
        vm.expectRevert(abi.encodeWithSelector(IPriceOracle.UnavailableData.selector, asset));
        _redStonePriceOracle.getPriceNoOlderThan(asset, 50);
    }

    function test_priceAvailable() public initialize {
        address asset = address(0x1);
        bytes32 dataFeedId = "USDC";

        // No data feed ID set
        assertFalse(_redStonePriceOracle.priceAvailable(asset));

        // Data feed ID set, but adapter returns zero timestamp
        _setDataFeedId(asset, dataFeedId);
        assertFalse(_redStonePriceOracle.priceAvailable(asset));

        // Adapter has data
        _mockedAdapter.setUpdate(dataFeedId, block.timestamp, block.timestamp, 1e8);
        assertTrue(_redStonePriceOracle.priceAvailable(asset));
    }

    function _setDataFeedId(address asset, bytes32 dataFeedId) internal {
        vm.prank(_governance);
        _redStonePriceOracle.setDataFeedId(asset, dataFeedId);
    }
}
