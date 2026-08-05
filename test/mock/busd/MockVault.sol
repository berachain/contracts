// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @notice This is a mock ERC4626 vault for testing.
 * @author Berachain Team
 * @author Solady (https://github.com/Vectorized/solady/tree/main/src/tokens/ERC4626.sol)
 * @author OpenZeppelin
 * (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol)
 */
contract FaultyVault {
    string private _name;
    address private _vaultAsset; // storage collision of _vaultAsset with name.
    string private _symbol;
    string private _newName;

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function setNewName(string memory newName) public {
        _newName = newName;
    }

    function getNewName() public view returns (string memory) {
        return _newName;
    }

    function asset() public view returns (address) {
        return _vaultAsset;
    }
}

contract MockVault {
    struct PausableStorage {
        bool _paused;
    }

    address private _vaultAsset;
    string private _name;
    string private _symbol;
    string private _newName;

    bytes32 private constant PAUSABLE_STORAGE_SLOT =
        0xcd5ed15c6e187e77e9aee88184c21f4f2182ab5827cb3b7e07fbedcd63f03300;

    function VERSION() public pure returns (uint256) {
        return 2;
    }

    function isNewImplementation() public pure returns (bool) {
        return true;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function setNewName(string memory newName) public {
        _newName = newName;
    }

    function getNewName() public view returns (string memory) {
        return _newName;
    }

    function asset() public view returns (address) {
        return _vaultAsset;
    }

    /**
     * @notice Get the paused status of the vault.
     * @dev It allows to read from the expected PausableUpgradeable storage slot when it upgrades a CollateralVault.
     */
    function paused() public view returns (bool) {
        PausableStorage storage ps;
        assembly {
            ps.slot := PAUSABLE_STORAGE_SLOT
        }
        return ps._paused;
    }
}
