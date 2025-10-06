// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { WETH } from "solady/src/tokens/WETH.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { IERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

import { Utils } from "../libraries/Utils.sol";
import { IWBERAStakerVault } from "./interfaces/IWBERAStakerVault.sol";
import { IWBERAStakerVaultWithdrawalRequest } from "./interfaces/IWBERAStakerVaultWithdrawalRequest.sol";

/// @title WBERA Staker Vault
/// @author Berachain Team
/// @notice The WBERAStakerVault is an ERC4626-compliant vault that allows users to stake $BERA and earn yield from
/// redirected PoL incentives. This contract is the core component of the PoL BERA Yield Module.
/// Key features:
/// - ERC4626 Compliance: Standard vault interface for easy integration
/// - Native BERA Support: Accepts both native BERA and WBERA deposits
/// - 7-Day Unbonding: Withdrawal requests require 7-day cooldown period
/// - Auto-Compounding: Rewards automatically compound to staker positions
/// - Inflation Attack Protection: Initial deposit mechanism prevents attacks
/// - Emergency Controls: Pausable with role-based access control
/// @dev Contract overrides internal `_withdraw` to enforce cooldown mechanism, all withdraw/redeem call be stored as
/// withdrawal request and can be completed after cooldown period.
/// @dev Contract uses `queueWithdraw` and `queueRedeem` to enqueue withdrawal requests which works with ERC721
/// withdrawal requests.
/// @dev `completeWithdrawal(bool)` is used to support the legacy withdrawal requests while `completeWithdrawal(bool,
/// uint256)` is used to support the ERC721 withdrawal requests.
/// @dev Uses ERC721Enumerable to manage ERC721 withdrawal requests.
/// @dev Only one withdrawal request is allowed per caller until it is completed.
contract WBERAStakerVault is
    IWBERAStakerVault,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ERC4626Upgradeable
{
    using Utils for bytes4;
    using SafeTransferLib for address;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The PAUSER role
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice The MANAGER role.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice The WBERA token address, serves as underlying asset.
    address public constant WBERA = 0x6969696969696969696969696969696969696969;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Amount of assets reserved for pending withdrawals
    uint256 public reservedAssets;

    /// @notice Mapping of user to withdrawal request
    /// @dev Legacy withdrawal requests are managed by this contract.
    mapping(address => IWBERAStakerVaultWithdrawalRequest.WithdrawalRequest) public withdrawalRequests;

    /// @notice Contract managing withdrawal requests
    IWBERAStakerVaultWithdrawalRequest public withdrawalRequests721;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Allow contract to receive BERA when WBERA is unwrapped
    /// @dev Reverts if the caller is not WBERA token address, this prevents accidental ETH transfer to the vault.
    receive() external payable {
        if (msg.sender != WBERA) {
            UnauthorizedETHTransfer.selector.revertWith();
        }
    }

    function initialize(address governance) external initializer {
        __Pausable_init();
        __ReentrancyGuard_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ERC4626_init(IERC20(WBERA));
        __ERC20_init("POL Staked WBERA", "sWBERA");

        if (governance == address(0)) {
            ZeroAddress.selector.revertWith();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, governance);
        _setRoleAdmin(PAUSER_ROLE, MANAGER_ROLE);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    /// @inheritdoc IWBERAStakerVault
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (tokenAddress == WBERA) {
            CannotRecoverStakingToken.selector.revertWith();
        }
        tokenAddress.safeTransfer(msg.sender, tokenAmount);
        emit ERC20Recovered(tokenAddress, tokenAmount);
    }

    /// @inheritdoc IWBERAStakerVault
    function setWithdrawalRequests721(address withdrawalRequests_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(withdrawalRequests_) == address(0)) {
            ZeroAddress.selector.revertWith();
        }
        emit WithdrawalRequests721Updated(address(withdrawalRequests721), withdrawalRequests_);
        withdrawalRequests721 = IWBERAStakerVaultWithdrawalRequest(withdrawalRequests_);
    }

    /// @inheritdoc IWBERAStakerVault
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @inheritdoc IWBERAStakerVault
    function unpause() external onlyRole(MANAGER_ROLE) {
        _unpause();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     ERC4626 OVERRIDES                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice override to exclude reserved assets for withdrawal
    function totalAssets() public view override returns (uint256) {
        return WBERA.balanceOf(address(this)) - reservedAssets;
    }

    /// @notice override to use whenNotPaused modifier
    function deposit(uint256 assets, address receiver) public override whenNotPaused returns (uint256) {
        return super.deposit(assets, receiver);
    }

    /// @notice override to use whenNotPaused modifier
    function mint(uint256 shares, address receiver) public override whenNotPaused returns (uint256) {
        return super.mint(shares, receiver);
    }

    /// @inheritdoc IWBERAStakerVault
    function depositNative(uint256 assets, address receiver) public payable whenNotPaused returns (uint256) {
        if (msg.value != assets) InsufficientNativeValue.selector.revertWith();
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        uint256 shares = previewDeposit(assets);
        _depositNative(_msgSender(), receiver, assets, shares);
        return shares;
    }

    /// @inheritdoc IWBERAStakerVault
    /// @dev Legacy withdrawal requests are completed by this method.
    function completeWithdrawal(bool isNative) external nonReentrant whenNotPaused {
        IWBERAStakerVaultWithdrawalRequest.WithdrawalRequest memory request = withdrawalRequests[msg.sender];
        // check if the withdrawal request exists
        if (request.requestTime == 0) WithdrawalNotRequested.selector.revertWith();
        // check if the withdrawal request is ready to be completed
        if (block.timestamp < request.requestTime + WITHDRAWAL_COOLDOWN()) {
            WithdrawalNotReady.selector.revertWith();
        }
        // complete the withdrawal request
        reservedAssets -= request.assets;
        if (isNative) {
            WETH(payable(WBERA)).withdraw(request.assets);
            request.receiver.safeTransferETH(request.assets);
        } else {
            WBERA.safeTransfer(request.receiver, request.assets);
        }
        delete withdrawalRequests[msg.sender];
        emit WithdrawalCompleted(msg.sender, request.receiver, request.owner, request.assets, request.shares);
    }

    /// @inheritdoc IWBERAStakerVault
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

    /// @inheritdoc IWBERAStakerVault
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

    /// @inheritdoc IWBERAStakerVault
    function cancelQueuedWithdrawal(uint256 requestId) external nonReentrant whenNotPaused {
        // only NFT owner can cancel the withdrawal request.
        // ownerOf reverts with ERC721NonexistentToken if the requestId does not exist.
        if (msg.sender != IERC721(address(withdrawalRequests721)).ownerOf(requestId)) {
            OnlyNFTOwnerAllowed.selector.revertWith();
        }
        // get the request from the withdrawalRequests721 contract.
        IWBERAStakerVaultWithdrawalRequest.WithdrawalRequest memory request =
            withdrawalRequests721.getRequest(requestId);
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

    /// @inheritdoc IWBERAStakerVault
    function completeWithdrawal(bool isNative, uint256 requestId) external nonReentrant whenNotPaused {
        // Non existent (already completed / never created) and not ready requests are handled by the ERC721 contract
        _completeWithdrawal(isNative, requestId);
    }

    /// @inheritdoc IWBERAStakerVault
    function receiveRewards(uint256 amount) external {
        WBERA.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardsReceived(msg.sender, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      HELPER FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IWBERAStakerVault
    function WITHDRAWAL_COOLDOWN() public view returns (uint256) {
        return withdrawalRequests721.WITHDRAWAL_COOLDOWN();
    }

    /// @inheritdoc IWBERAStakerVault
    function getERC721WithdrawalRequest(uint256 requestId)
        external
        view
        returns (IWBERAStakerVaultWithdrawalRequest.WithdrawalRequest memory)
    {
        return withdrawalRequests721.getRequest(requestId);
    }

    /// @inheritdoc IWBERAStakerVault
    function getUserERC721WithdrawalRequestCount(address user) external view returns (uint256) {
        return IERC721(address(withdrawalRequests721)).balanceOf(user);
    }

    /// @inheritdoc IWBERAStakerVault
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

    /// @inheritdoc IWBERAStakerVault
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

    /// @dev Override to remove the token transfer and store the withdrawal request to enforce the cooldown mechanism
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    )
        internal
        override
        whenNotPaused
    {
        // check if any previous pending withdrawal request exists for the caller
        // if exists, revert with `WithdrawalAlreadyRequested` as only one withdrawal request is allowed per caller
        // till its not completed
        IWBERAStakerVaultWithdrawalRequest.WithdrawalRequest memory request = withdrawalRequests[caller];
        if (request.requestTime != 0) {
            WithdrawalAlreadyRequested.selector.revertWith();
        }

        // check if the caller has approved the owner to spend the shares
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // If _asset is ERC-777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
        // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
        // shares are burned and after the assets are transferred, which is a valid state.
        _burn(owner, shares);

        // Store withdrawal request for the caller
        // Storing for caller to keep the same logic of ERC4626 where during withdraw/redeem, the caller is able to
        // withdraw funds to the receiver address
        withdrawalRequests[caller] = IWBERAStakerVaultWithdrawalRequest.WithdrawalRequest({
            assets: assets,
            shares: shares,
            requestTime: block.timestamp,
            owner: owner,
            receiver: receiver
        });
        reservedAssets += assets;

        emit WithdrawalRequested(caller, receiver, owner, assets, shares);
    }

    /// @dev Custom deposit to handle native currency deposit by wrapping the native currency to WETH
    function _depositNative(address caller, address receiver, uint256 assets, uint256 shares) internal {
        WETH(payable(WBERA)).deposit{ value: assets }();
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
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
    function _completeWithdrawal(bool isNative, uint256 requestId) internal {
        // get the request from the withdrawalRequests721 contract
        IWBERAStakerVaultWithdrawalRequest.WithdrawalRequest memory request =
            withdrawalRequests721.getRequest(requestId);
        // checks for request existence and cooldown period and burns the NFT along with deleting the request from the
        // mapping.
        withdrawalRequests721.burn(requestId);

        reservedAssets -= request.assets;
        if (isNative) {
            WETH(payable(WBERA)).withdraw(request.assets);
            request.receiver.safeTransferETH(request.assets);
        } else {
            WBERA.safeTransfer(request.receiver, request.assets);
        }

        emit WithdrawalCompleted(msg.sender, request.receiver, request.owner, request.assets, request.shares);
    }
}
