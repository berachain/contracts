// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IPriceOracle } from "./IPriceOracle.sol";
import { Utils } from "../libraries/Utils.sol";

/// @title RedStone price feed adapter interface
interface IRedStonePriceFeedAdapter {
    /// @dev Get the last update details.
    /// @param dataFeedId The data feed ID.
    /// @return lastDataTimestamp The timestamp when the data was last updated.
    /// @return lastBlockTimestamp The timestamp when the block was last updated.
    /// @return lastValue The last value.
    function getLastUpdateDetails(bytes32 dataFeedId)
        external
        view
        returns (uint256 lastDataTimestamp, uint256 lastBlockTimestamp, uint256 lastValue);

    /// @dev Get the last update details without any sanity checks.
    /// @param dataFeedId The data feed ID.
    /// @return lastDataTimestamp The timestamp when the data was last updated.
    /// @return lastBlockTimestamp The timestamp when the block was last updated.
    /// @return lastValue The last value.
    function getLastUpdateDetailsUnsafe(bytes32 dataFeedId)
        external
        view
        returns (uint256 lastDataTimestamp, uint256 lastBlockTimestamp, uint256 lastValue);
}

/// @title RedStone price oracle
/// @dev Provides price data from RedStone feeds in WAD precision.
contract RedStonePriceOracle is IPriceOracle, AccessControlUpgradeable, UUPSUpgradeable {
    using Utils for bytes4;

    /// @notice The RedStone price feed adapter.
    IRedStonePriceFeedAdapter public redstonePriceFeedAdapter;

    /// @notice The RedStone data feed IDs mapping
    mapping(address asset => bytes32 dataFeedId) public dataFeedIds;

    /// @notice Emitted when a data feed ID is changed.
    event DataFeedIdChanged(address indexed asset, bytes32 indexed dataFeedId);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address governance_, address redstonePriceFeedAdapter_) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        if (governance_ == address(0)) ZeroAddress.selector.revertWith();
        if (redstonePriceFeedAdapter_ == address(0)) ZeroAddress.selector.revertWith();
        redstonePriceFeedAdapter = IRedStonePriceFeedAdapter(redstonePriceFeedAdapter_);
        _grantRole(DEFAULT_ADMIN_ROLE, governance_);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override {
        // Silent warning
        newImplementation;
        _checkRole(DEFAULT_ADMIN_ROLE);
    }

    /// @notice Set the data feed ID for a given asset.
    /// @param asset The asset.
    /// @param dataFeedId The RedStone data feed ID.
    function setDataFeedId(address asset, bytes32 dataFeedId) external {
        _checkRole(DEFAULT_ADMIN_ROLE);
        if (asset == address(0) || dataFeedId == bytes32(0)) ZeroAddress.selector.revertWith();
        dataFeedIds[asset] = dataFeedId;
        emit DataFeedIdChanged(asset, dataFeedId);
    }

    /// @dev Get the latest round data and convert it to the WAD precision.
    function _wrapData(uint256 lastValue, uint256 lastBlockTimestamp)
        internal
        pure
        returns (IPriceOracle.Data memory)
    {
        // redstone feed returns value in 8 decimals, so we need to convert it to 18 decimals.
        return IPriceOracle.Data({ price: Utils.changeDecimals(lastValue, 8, 18), publishTime: lastBlockTimestamp });
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   IPriceOracle FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IPriceOracle
    /// @dev getLastUpdateDetails has an inbuilt sanity check for 30 hours stale data along with positive value check.
    function getPrice(address asset) public view onlyAssetWithDataFeedIdSet(asset) returns (Data memory data) {
        (, uint256 lastBlockTimestamp, uint256 lastValue) =
            redstonePriceFeedAdapter.getLastUpdateDetails(dataFeedIds[asset]);
        return _wrapData(lastValue, lastBlockTimestamp);
    }

    /// @inheritdoc IPriceOracle
    function getPriceUnsafe(address asset) public view onlyAssetWithDataFeedIdSet(asset) returns (Data memory data) {
        (, uint256 lastBlockTimestamp, uint256 lastValue) =
            redstonePriceFeedAdapter.getLastUpdateDetailsUnsafe(dataFeedIds[asset]);
        return _wrapData(lastValue, lastBlockTimestamp);
    }

    /// @inheritdoc IPriceOracle
    /// @dev For any number of age less than heartbeat interval, this will mostly revert as redstone feeds are
    /// generally updated at heartbeat interval.
    function getPriceNoOlderThan(
        address asset,
        uint256 age
    )
        external
        view
        onlyAssetWithDataFeedIdSet(asset)
        returns (Data memory data)
    {
        data = getPriceUnsafe(asset);
        // Throws panic revert if age is greater than block.timestamp
        // Revert with UnavailableData if the price is older than the age.
        if (data.publishTime < block.timestamp - age) {
            UnavailableData.selector.revertWith(asset);
        }
        return data;
    }

    /// @inheritdoc IPriceOracle
    function priceAvailable(address asset) external view returns (bool) {
        if (dataFeedIds[asset] == bytes32(0)) {
            return false;
        }
        (, uint256 lastBlockTimestamp,) = redstonePriceFeedAdapter.getLastUpdateDetailsUnsafe(dataFeedIds[asset]);
        return lastBlockTimestamp != 0;
    }

    /// @dev Modifier to check if the data feed ID is set for a given asset.
    /// @param asset The asset.
    modifier onlyAssetWithDataFeedIdSet(address asset) {
        if (dataFeedIds[asset] == bytes32(0)) {
            UnavailableData.selector.revertWith(asset);
        }
        _;
    }
}
