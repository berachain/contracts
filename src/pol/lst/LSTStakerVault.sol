// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { WETH } from "solady/src/tokens/WETH.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { IERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

import { IStakerVault } from "src/pol/interfaces/lst/IStakerVault.sol";
import { IStakerVaultWithdrawalRequest } from "src/pol/interfaces/lst/IStakerVaultWithdrawalRequest.sol";
import { FactoryOwnable } from "src/base/FactoryOwnable.sol";
import { Utils } from "src/libraries/Utils.sol";

/// @title LST Staker Vault
/// @author Berachain Team
/// @notice The LSTStakerVault is an ERC4626-compliant vault that allows users to stake an LST and earn yield from
/// redirected PoL incentives. This contract is an additive LST equivalent of the WBERAStakerVault contract.
/// @dev Contract overrides internal `_withdraw` to disallow direct withdrawal. See `queue` methods in place.
/// @dev Contract uses `queueWithdraw` and `queueRedeem` to enqueue withdrawal requests which works with ERC721
/// withdrawal requests.
/// @dev Uses ERC721Enumerable to manage ERC721 withdrawal requests.
contract LSTStakerVault is
    FactoryOwnable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    ERC4626Upgradeable,
    IStakerVault
{
    using Utils for bytes4;
    using SafeTransferLib for address;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Amount of assets reserved for pending withdrawals
    uint256 public reservedAssets;

    /// @notice Contract managing withdrawal requests
    IStakerVaultWithdrawalRequest public withdrawalRequests721;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address stakeToken, address withdrawal721) external initializer {
        if (stakeToken == address(0) || withdrawal721 == address(0)) {
            ZeroAddress.selector.revertWith();
        }

        __FactoryOwnable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        IERC20Metadata tokenData = IERC20Metadata(stakeToken);
        string memory symbol = string.concat("s", tokenData.symbol());
        string memory name = string.concat("POL Staked ", tokenData.symbol());

        __ERC4626_init(tokenData);
        __ERC20_init(name, symbol);

        withdrawalRequests721 = IStakerVaultWithdrawalRequest(withdrawal721);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _authorizeUpgrade(address newImplementation) internal override onlyFactoryOwner { }

    /// @inheritdoc IStakerVault
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyFactoryOwner {
        if (tokenAddress == asset()) {
            CannotRecoverStakingToken.selector.revertWith();
        }
        tokenAddress.safeTransfer(msg.sender, tokenAmount);
        emit ERC20Recovered(tokenAddress, tokenAmount);
    }

    /// @inheritdoc IStakerVault
    function pause() external onlyFactoryVaultPauser {
        _pause();
    }

    /// @inheritdoc IStakerVault
    function unpause() external onlyFactoryVaultManager {
        _unpause();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     ERC4626 OVERRIDES                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice override to exclude reserved assets for withdrawal
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) - reservedAssets;
    }

    /// @notice override to use whenNotPaused modifier
    function deposit(uint256 assets, address receiver) public override whenNotPaused returns (uint256) {
        return super.deposit(assets, receiver);
    }

    /// @notice override to use whenNotPaused modifier
    function mint(uint256 shares, address receiver) public override whenNotPaused returns (uint256) {
        return super.mint(shares, receiver);
    }

    /// @inheritdoc IStakerVault
    function queueRedeem(
        uint256 shares,
        address receiver,
        address owner
    )
        external
        nonReentrant
        whenNotPaused
        returns (uint256, uint256)
    {
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }

        uint256 assets = previewRedeem(shares);
        uint256 withdrawalId = _queueWithdraw(_msgSender(), receiver, owner, assets, shares);
        return (assets, withdrawalId);
    }

    /// @inheritdoc IStakerVault
    function queueWithdraw(
        uint256 assets,
        address receiver,
        address owner
    )
        external
        nonReentrant
        whenNotPaused
        returns (uint256, uint256)
    {
        uint256 maxAssets = maxWithdraw(owner);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        }

        uint256 shares = previewWithdraw(assets);
        uint256 withdrawalId = _queueWithdraw(_msgSender(), receiver, owner, assets, shares);
        return (shares, withdrawalId);
    }

    /// @inheritdoc IStakerVault
    function cancelQueuedWithdrawal(uint256 requestId) external nonReentrant whenNotPaused {
        // only NFT owner can cancel the withdrawal request.
        // ownerOf reverts with ERC721NonexistentToken if the requestId does not exist.
        if (msg.sender != IERC721(address(withdrawalRequests721)).ownerOf(requestId)) {
            OnlyNFTOwnerAllowed.selector.revertWith();
        }
        // get the request from the withdrawalRequests721 contract.
        IStakerVaultWithdrawalRequest.WithdrawalRequest memory request = withdrawalRequests721.getRequest(requestId);
        // burn the NFT and delete the request from the mapping
        withdrawalRequests721.cancel(requestId);
        // mint the new shares to the NFT owner based on locked assets during the queuing of the request.
        uint256 assets = request.assets; // cache the assets
        uint256 maxAssets = maxDeposit(msg.sender);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(msg.sender, assets, maxAssets);
        }
        uint256 newSharesToMint = previewDeposit(assets);

        reservedAssets -= assets;
        // mint the shares to the caller
        _mint(msg.sender, newSharesToMint);
        emit WithdrawalCancelled(msg.sender, request.owner, assets, request.shares, newSharesToMint);
    }

    /// @inheritdoc IStakerVault
    function completeWithdrawal(uint256 requestId) external nonReentrant whenNotPaused {
        // Non existent (already completed / never created) and not ready requests are handled by the ERC721 contract
        _completeWithdrawal(requestId);
    }

    /// @inheritdoc IStakerVault
    function receiveRewards(uint256 amount) external {
        asset().safeTransferFrom(msg.sender, address(this), amount);
        emit RewardsReceived(msg.sender, amount, totalAssets());
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      HELPER FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStakerVault
    function WITHDRAWAL_COOLDOWN() public view returns (uint256) {
        return withdrawalRequests721.WITHDRAWAL_COOLDOWN();
    }

    /// @inheritdoc IStakerVault
    function getERC721WithdrawalRequest(uint256 requestId)
        external
        view
        returns (IStakerVaultWithdrawalRequest.WithdrawalRequest memory)
    {
        return withdrawalRequests721.getRequest(requestId);
    }

    /// @inheritdoc IStakerVault
    function getUserERC721WithdrawalRequestCount(address user) external view returns (uint256) {
        return IERC721(address(withdrawalRequests721)).balanceOf(user);
    }

    /// @inheritdoc IStakerVault
    function getERC721WithdrawalRequestIds(address user) external view returns (uint256[] memory) {
        uint256 balance = IERC721(address(withdrawalRequests721)).balanceOf(user);
        uint256[] memory ids = new uint256[](balance);
        for (uint256 i = 0; i < balance;) {
            ids[i] = IERC721Enumerable(address(withdrawalRequests721)).tokenOfOwnerByIndex(user, i);
            unchecked {
                ++i;
            }
        }
        return ids;
    }

    /// @inheritdoc IStakerVault
    function getERC721WithdrawalRequestIds(
        address user,
        uint256 offset,
        uint256 limit
    )
        external
        view
        returns (uint256[] memory ids)
    {
        uint256 balance = IERC721(address(withdrawalRequests721)).balanceOf(user);
        if (offset >= balance || limit == 0) {
            return new uint256[](0);
        }
        uint256 length = Math.min(balance - offset, limit);

        ids = new uint256[](length);
        for (uint256 i = 0; i < length;) {
            ids[i] = IERC721Enumerable(address(withdrawalRequests721)).tokenOfOwnerByIndex(user, offset + i);
            unchecked {
                ++i;
            }
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          INTERNAL                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Override to revert direct withdrawals.
    function _withdraw(
        address, /* caller */
        address, /* receiver */
        address, /* owner */
        uint256, /* assets */
        uint256 /* shares */
    )
        internal
        pure
        override
    {
        MethodNotAllowed.selector.revertWith();
    }

    /// @dev Enqueues a withdrawal request by burning shares and minting a withdrawal request NFT.
    function _queueWithdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    )
        internal
        returns (uint256)
    {
        // check if the caller has approved the owner to spend the shares
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        _burn(owner, shares);
        reservedAssets += assets;

        // Mint the withdrawal request NFT
        uint256 requestId = withdrawalRequests721.mint(caller, receiver, owner, assets, shares);
        emit WithdrawalRequested(caller, receiver, owner, assets, shares);
        return requestId;
    }

    /// @dev Completes a withdrawal request by burning the withdrawal request NFT and transferring the assets.
    /// @dev `withdrawalRequests721.burn` handles the cooldown period check and NFT burn.
    function _completeWithdrawal(uint256 requestId) internal {
        // get the request from the withdrawalRequests721 contract
        IStakerVaultWithdrawalRequest.WithdrawalRequest memory request = withdrawalRequests721.getRequest(requestId);
        // checks for request existence and cooldown period and burns the NFT along with deleting the request from the
        // mapping.
        withdrawalRequests721.burn(requestId);

        reservedAssets -= request.assets;
        asset().safeTransfer(request.receiver, request.assets);
        emit WithdrawalCompleted(msg.sender, request.receiver, request.owner, request.assets, request.shares);
    }
}
