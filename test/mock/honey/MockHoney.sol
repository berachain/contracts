// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import { ERC20 } from "solady/src/tokens/ERC20.sol";
import { Ownable } from "solady/src/auth/Ownable.sol";

/**
 * @notice This is an ERC20 token for testing.
 * @author Berachain Team
 */
contract FaultyMockHoney is ERC20, Ownable, UUPSUpgradeable {
    string private constant _name = "MockHoney";
    string private constant _symbol = "MOCK_HONEY";

    address public collidedFactoryValue; // Add a variable to cause storage collision
    address public factory;

    constructor() {
        _disableInitializers();
    }

    function initialize(address owner) public {
        super._initializeOwner(owner);
    }

    function name() public pure override returns (string memory) {
        return _name;
    }

    function symbol() public pure override returns (string memory) {
        return _symbol;
    }

    function _authorizeUpgrade(address) internal view override onlyOwner {
        return;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

/**
 * @notice This is an ERC20 token for testing.
 * @author Berachain Team
 * @author Solady (https://github.com/Vectorized/solady/)
 */
contract MockHoney is ERC20, Ownable, UUPSUpgradeable {
    string private constant _name = "MockHoney";
    string private constant _symbol = "MOCK_HONEY";

    constructor() {
        _disableInitializers();
    }

    function initialize(address owner) public {
        super._initializeOwner(owner);
    }

    function name() public pure override returns (string memory) {
        return _name;
    }

    function symbol() public pure override returns (string memory) {
        return _symbol;
    }

    function _authorizeUpgrade(address) internal view override onlyOwner {
        return;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    /**
     * @notice Returns factory address
     * @dev Since in the original Honey contract, the factory address is the fist public variable,
     *      it's has been stored on the first slot of the storage.
     * @return _factory The factory address
     */
    function factory() public view returns (address _factory) {
        assembly {
            _factory := sload(0)
        }
    }
}
