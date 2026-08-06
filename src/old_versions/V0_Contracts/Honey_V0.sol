// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { ERC20 } from "solady/src/tokens/ERC20.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { Utils } from "src/libraries/Utils.sol";
import { IHoneyErrors } from "src/honey/IHoneyErrors.sol";

/// @notice This is the ERC20 token representation of Berachain's native stablecoin, Honey.
/// @author Berachain Team
contract Honey_V0 is ERC20, AccessControlUpgradeable, UUPSUpgradeable, IHoneyErrors {
    using Utils for bytes4;

    string private constant NAME = "Honey";
    string private constant SYMBOL = "HONEY";

    /// @notice The factory contract that mints and burns Honey.
    address public factory;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _governance, address _factory) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        // Check for zero addresses.
        if (_factory == address(0)) ZeroAddress.selector.revertWith();
        if (_governance == address(0)) ZeroAddress.selector.revertWith();
        factory = _factory;
        _grantRole(DEFAULT_ADMIN_ROLE, _governance);
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
}
