/// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ERC721EnumerableUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC721Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

import { Utils } from "../libraries/Utils.sol";
import { IWBERAStakerVaultWithdrawalRequest } from "./interfaces/IWBERAStakerVaultWithdrawalRequest.sol";

/// @title WBERAStakerVaultWithdrawalRequest
/// @author Berachain Team
/// @notice A contract for creating and managing withdrawal requests for WBERAStakerVault.
/// @dev NFT mint, burn related functions are only callable by WBERAStakerVault and NFT is non-transferable.
contract WBERAStakerVaultWithdrawalRequest is
    UUPSUpgradeable,
    OwnableUpgradeable,
    ERC721EnumerableUpgradeable,
    IWBERAStakerVaultWithdrawalRequest
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
    address public wberaStakerVault;

    /// @notice The id of the next withdrawal request to mint.
    uint256 internal _nextRequestId;

    /// @notice Mapping ids to withdrawal requests.
    mapping(uint256 requestId => WithdrawalRequest) internal withdrawalRequests;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address governance, address wberaStakerVault_) public initializer {
        if (governance == address(0) || wberaStakerVault_ == address(0)) {
            ZeroAddress.selector.revertWith();
        }
        __UUPSUpgradeable_init();
        __Ownable_init(governance);
        __ERC721Enumerable_init();
        __ERC721_init("POL Staked WBERA Withdrawal Request", "sWBERAwr");

        wberaStakerVault = wberaStakerVault_;
        emit WBERAStakerVaultUpdated(address(0), wberaStakerVault_);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Throws if called by any account other than WBERAStakerVault contract.
    modifier onlyWBERAStakerVault() {
        if (msg.sender != address(wberaStakerVault)) NotWBERAStakerVault.selector.revertWith();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    /// @inheritdoc IWBERAStakerVaultWithdrawalRequest
    function setWBERAStakerVault(address wberaStakerVault_) external onlyOwner {
        if (wberaStakerVault_ == address(0)) {
            ZeroAddress.selector.revertWith();
        }

        emit WBERAStakerVaultUpdated(wberaStakerVault, wberaStakerVault_);
        wberaStakerVault = wberaStakerVault_;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          FUNCTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Make this non-transferable.
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    )
        public
        pure
        override(ERC721Upgradeable, IERC721)
    {
        from;
        to;
        tokenId;
        NonTransferable.selector.revertWith();
    }

    /// @inheritdoc IWBERAStakerVaultWithdrawalRequest
    function getRequest(uint256 requestId) external view returns (WithdrawalRequest memory) {
        WithdrawalRequest memory request = withdrawalRequests[requestId];
        return request;
    }

    /// @inheritdoc IWBERAStakerVaultWithdrawalRequest
    function mint(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    )
        external
        onlyWBERAStakerVault
        returns (uint256 requestId)
    {
        return _mintWithdrawalRequest(caller, receiver, owner, assets, shares);
    }

    /// @inheritdoc IWBERAStakerVaultWithdrawalRequest
    function burn(uint256 requestId) external onlyWBERAStakerVault {
        _burnWithdrawalRequest(requestId);
    }

    /// @inheritdoc IWBERAStakerVaultWithdrawalRequest
    function cancel(uint256 requestId) external onlyWBERAStakerVault {
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
            assets: assets,
            shares: shares,
            requestTime: block.timestamp,
            receiver: receiver,
            owner: owner
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
