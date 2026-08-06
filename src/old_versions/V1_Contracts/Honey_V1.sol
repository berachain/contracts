// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { ERC20 } from "solady/src/tokens/ERC20.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { Utils } from "src/libraries/Utils.sol";
import { IHoneyErrors } from "src/honey/IHoneyErrors.sol";

/// @notice This is the ERC20 token representation of Berachain's native stablecoin, Honey.
/// @author Berachain Team
contract Honey_V1 is ERC20, PausableUpgradeable, AccessControlUpgradeable, UUPSUpgradeable, IHoneyErrors {
    using Utils for bytes4;

    string private constant NAME = "Honey";
    string private constant SYMBOL = "HONEY";

    /// @notice The factory contract that mints and burns Honey.
    address public factory;

    /// @notice Whether or not a wallet has been blacklisted (e.g. due to stolen funds).
    mapping(address wallet => bool blacklisted) public isBlacklistedWallet;

    /// @notice Emitted when the fee receiver address is set.
    event BlacklistedStatusChanged(address wallet, bool status);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _governance, address _factory) external initializer {
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        // Check for zero addresses.
        if (_factory == address(0)) ZeroAddress.selector.revertWith();
        if (_governance == address(0)) ZeroAddress.selector.revertWith();
        factory = _factory;
        _grantRole(DEFAULT_ADMIN_ROLE, _governance);
    }

    /// @custom:oz-upgrades-validate-as-initializer
    function initializeV1Update() external reinitializer(2) {
        __Pausable_init();
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    modifier onlyFactory() {
        if (msg.sender != factory) NotFactory.selector.revertWith();
        _;
    }

    /// @notice Mint Honey to the receiver.
    /// @dev Only the factory can call this function.
    /// @param to The receiver address.
    /// @param amount The amount of Honey to mint.
    function mint(address to, uint256 amount) external onlyFactory {
        _mint(to, amount);
    }

    /// @notice Burn Honey from an account.
    /// @dev Only the factory can call this function.
    /// @param from The account to burn Honey from.
    /// @param amount The amount of Honey to burn.
    function burn(address from, uint256 amount) external onlyFactory {
        _burn(from, amount);
    }

    function name() public pure override returns (string memory) {
        return NAME;
    }

    function symbol() public pure override returns (string memory) {
        return SYMBOL;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal view override {
        amount;
        _requireNotPaused();

        if (isBlacklistedWallet[from] || isBlacklistedWallet[to]) {
            revert BlacklistedWallet();
        }
    }

    /// @notice Allows to pause transfer of Honey for a specific wallet
    function setBlacklisted(address wallet, bool status) external {
        _checkRole(DEFAULT_ADMIN_ROLE);
        isBlacklistedWallet[wallet] = status;

        emit BlacklistedStatusChanged(wallet, status);
    }

    /// @notice Allows to pause transfer of Honey
    function setPaused(bool pause) external {
        _checkRole(DEFAULT_ADMIN_ROLE);

        bool isPaused = paused();
        if (pause && !isPaused) {
            _pause();
        }
        if (!pause && isPaused) {
            _unpause();
        }
    }
}
