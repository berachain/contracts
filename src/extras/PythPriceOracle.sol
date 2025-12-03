// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IPyth } from "@pythnetwork/IPyth.sol";
import { PythStructs } from "@pythnetwork/PythStructs.sol";
import { PythUtils } from "@pythnetwork/PythUtils.sol";
import { IPriceOracle } from "./IPriceOracle.sol";
import { Utils } from "../libraries/Utils.sol";

contract PythPriceOracle is IPriceOracle, AccessControlUpgradeable, UUPSUpgradeable {
    using Utils for bytes4;

    /// @notice The MANAGER role.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice The Pyth price oracle
    IPyth public pyth;

    /// @notice Mapping of asset to (Pyth) price feed ID.
    mapping(address asset => bytes32 id) public feeds;

    /// @notice Emitted when the oracle source is changed.
    event OracleChanged(address oracle);
    /// @notice Emitted when a price feed is changed.
    event PriceFeedChanged(address indexed asset, bytes32 id);

    error ZeroFeed();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address governance_) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __PriceOracle_init_unchained(governance_);
    }

    function __PriceOracle_init_unchained(address governance_) internal onlyInitializing {
        if (governance_ == address(0)) ZeroAddress.selector.revertWith();

        _grantRole(DEFAULT_ADMIN_ROLE, governance_);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override {
        // Silent warning
        newImplementation;
        _checkRole(DEFAULT_ADMIN_ROLE);
    }

    /// @notice Set the underlying price oracle.
    /// @param pythOracle_ The Pyth oracle.
    function setPythSource(address pythOracle_) external {
        _checkRole(DEFAULT_ADMIN_ROLE);
        if (pythOracle_ == address(0)) ZeroAddress.selector.revertWith();

        pyth = IPyth(pythOracle_);

        emit OracleChanged(pythOracle_);
    }

    /// @notice Set the price feed for a given asset.
    /// @param asset The asset.
    /// @param feed The (Pyth) feed ID for the asset/USD price feed.
    function setPriceFeed(address asset, bytes32 feed) external {
        _checkRole(MANAGER_ROLE);
        if (asset == address(0)) ZeroAddress.selector.revertWith();
        if (feed == bytes32(0)) ZeroFeed.selector.revertWith();

        feeds[asset] = feed;

        // Check that it works:
        getPrice(asset);

        emit PriceFeedChanged(asset, feed);
    }

    function _wrapData(PythStructs.Price memory response) internal pure returns (IPriceOracle.Data memory) {
        return IPriceOracle.Data({
            price: PythUtils.convertToUint(response.price, response.expo, 18), publishTime: response.publishTime
        });
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   IPriceOracle FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IPriceOracle
    function getPrice(address asset) public view returns (Data memory data) {
        if (!_pythAndFeedAreSet(asset)) {
            UnavailableData.selector.revertWith(asset);
        }

        PythStructs.Price memory price = pyth.getPrice(feeds[asset]);
        return _wrapData(price);
    }

    /// @inheritdoc IPriceOracle
    function getPriceUnsafe(address asset) public view returns (Data memory data) {
        if (!_pythAndFeedAreSet(asset)) {
            UnavailableData.selector.revertWith(asset);
        }

        PythStructs.Price memory price = pyth.getPriceUnsafe(feeds[asset]);
        return _wrapData(price);
    }

    /// @inheritdoc IPriceOracle
    function getPriceNoOlderThan(address asset, uint256 age) external view returns (Data memory data) {
        if (!_pythAndFeedAreSet(asset)) {
            UnavailableData.selector.revertWith(asset);
        }

        PythStructs.Price memory price = pyth.getPriceNoOlderThan(feeds[asset], age);
        return _wrapData(price);
    }

    /// @inheritdoc IPriceOracle
    function priceAvailable(address asset) external view returns (bool) {
        if (!_pythAndFeedAreSet(asset)) {
            return false;
        }

        Data memory data = getPriceUnsafe(asset);
        return data.publishTime != 0;
    }

    function _pythAndFeedAreSet(address asset) internal view returns (bool) {
        if (address(pyth) == address(0)) {
            return false;
        }
        if (feeds[asset] == bytes32(0)) {
            return false;
        }
        return true;
    }
}
