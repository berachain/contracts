/// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {
    ERC721EnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC721Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

import { IStakerVaultWithdrawalRequest } from "src/pol/interfaces/lst/IStakerVaultWithdrawalRequest.sol";
import { FactoryOwnable } from "src/base/FactoryOwnable.sol";
import { Utils } from "src/libraries/Utils.sol";

/// @title LSTStakerVaultWithdrawalRequest
/// @author Berachain Team
/// @notice A contract for creating and managing withdrawal requests for LSTStakerVault.
/// @dev NFT mint, burn related functions are only callable by LSTStakerVault and NFT is non-transferable.
contract LSTStakerVaultWithdrawalRequest is
    FactoryOwnable,
    UUPSUpgradeable,
    ERC721EnumerableUpgradeable,
    IStakerVaultWithdrawalRequest
{
    using Utils for bytes4;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          CONSTANTS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The withdrawal cooldown period.
    uint256 public constant WITHDRAWAL_COOLDOWN = 7 days;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           STORAGE                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The address of the withdrawal vault.
    address public stakerVault;

    /// @notice The id of the next withdrawal request to mint.
    uint256 internal _nextRequestId;

    /// @notice Mapping ids to withdrawal requests.
    mapping(uint256 requestId => WithdrawalRequest) internal withdrawalRequests;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address stakerVault_) public initializer {
        if (stakerVault_ == address(0)) {
            ZeroAddress.selector.revertWith();
        }

        __FactoryOwnable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ERC721Enumerable_init();

        // Derive name and symbol from the staking token
        IERC20Metadata token = IERC20Metadata(IERC4626(stakerVault_).asset());
        string memory symbol = string.concat("s", token.symbol());
        symbol = string.concat(symbol, "wr");
        string memory name = string.concat("POL Staked ", token.symbol());
        name = string.concat(name, " Withdrawal Request");
        __ERC721_init(name, symbol);

        stakerVault = stakerVault_;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Throws if called by any account other than LSTStakerVault contract.
    modifier onlyStakerVault() {
        if (msg.sender != address(stakerVault)) NotStakerVault.selector.revertWith();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _authorizeUpgrade(address newImplementation) internal override onlyFactoryOwner { }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          FUNCTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Override to make non-transferable.
    function transferFrom(
        address, /* from */
        address, /* to */
        uint256 /* tokenId */
    )
        public
        pure
        override(ERC721Upgradeable, IERC721)
    {
        NonTransferable.selector.revertWith();
    }

    /// @inheritdoc IStakerVaultWithdrawalRequest
    function getRequest(uint256 requestId) external view returns (WithdrawalRequest memory) {
        WithdrawalRequest memory request = withdrawalRequests[requestId];
        return request;
    }

    /// @inheritdoc IStakerVaultWithdrawalRequest
    function mint(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    )
        external
        onlyStakerVault
        returns (uint256 requestId)
    {
        return _mintWithdrawalRequest(caller, receiver, owner, assets, shares);
    }

    /// @inheritdoc IStakerVaultWithdrawalRequest
    function burn(uint256 requestId) external onlyStakerVault {
        _burnWithdrawalRequest(requestId);
    }

    /// @inheritdoc IStakerVaultWithdrawalRequest
    function cancel(uint256 requestId) external onlyStakerVault {
        _cancelWithdrawalRequest(requestId);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           INTERNAL                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _mintWithdrawalRequest(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    )
        internal
        returns (uint256)
    {
        uint256 newRequestId = _nextRequestId++;

        WithdrawalRequest memory newRequest = WithdrawalRequest({
            assets: assets, shares: shares, requestTime: block.timestamp, receiver: receiver, owner: owner
        });

        _safeMint(caller, newRequestId);
        withdrawalRequests[newRequestId] = newRequest;

        emit WithdrawalRequestCreated(newRequestId);
        return newRequestId;
    }

    function _burnWithdrawalRequest(uint256 requestId) internal {
        WithdrawalRequest memory request = withdrawalRequests[requestId];
        // Reverts with ERC721NonexistentToken if the request does not exist
        _burn(requestId);
        // Reverts with WithdrawalNotReady if the request is not ready
        if (request.requestTime + WITHDRAWAL_COOLDOWN > block.timestamp) {
            WithdrawalNotReady.selector.revertWith();
        }
        delete withdrawalRequests[requestId];
        emit WithdrawalRequestCompleted(requestId);
    }

    function _cancelWithdrawalRequest(uint256 requestId) internal {
        _burn(requestId);
        delete withdrawalRequests[requestId];
        emit WithdrawalRequestCancelled(requestId);
    }
}
