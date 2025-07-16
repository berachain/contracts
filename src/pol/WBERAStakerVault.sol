// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { WETH } from "solady/src/tokens/WETH.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

import { Utils } from "../libraries/Utils.sol";
import { IWBERAStakerVault } from "./interfaces/IWBERAStakerVault.sol";

/// @title WBERA Staker Vault
/// @author Berachain Team
/// @notice ERC4626 compliant vault for WBERA staking, receive WBERA rewards from `BGTIncentiveFeeCollector`
/// @dev Contract overrides internal `_withdraw` to enforce cooldown mechanism, all withdraw/redeem call be stored as
/// withdrawal request and can be completed after cooldown period
/// @dev Only one withdrawal request is allowed per caller until its not completed.
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

    /// @notice The withdrawal cooldown period.
    uint256 public constant WITHDRAWAL_COOLDOWN = 7 days;

    /// @notice The PAUSER role
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice The MANAGER role.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice The WBERA token address, serves as underlying asset.
    address public constant WBERA = 0x6969696969696969696969696969696969696969;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Struct to hold withdrawal request data
    struct WithdrawalRequest {
        uint256 assets;
        uint256 shares;
        uint256 requestTime;
        address owner;
        address receiver;
    }

    /// @notice Amount of assets reserved for pending withdrawals
    uint256 public reservedAssets;

    /// @notice Mapping of user to withdrawal request
    mapping(address => WithdrawalRequest) public withdrawalRequests;

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
    function completeWithdrawal(bool isNative) external nonReentrant whenNotPaused {
        WithdrawalRequest memory request = withdrawalRequests[msg.sender];
        // check if the withdrawal request exists
        if (request.requestTime == 0) WithdrawalNotRequested.selector.revertWith();
        // check if the withdrawal request is ready to be completed
        if (block.timestamp < request.requestTime + WITHDRAWAL_COOLDOWN) {
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

    /// @dev Custom deposit to handle native currency deposit by wrapping the native currency to WETH
    function _depositNative(address caller, address receiver, uint256 assets, uint256 shares) internal {
        WETH(payable(WBERA)).deposit{ value: assets }();
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

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
    {
        // check if any previous pending withdrawal request exists for the caller
        // if exists, revert with `WithdrawalAlreadyRequested` as only one withdrawal request is allowed per caller
        // till its not completed
        WithdrawalRequest memory request = withdrawalRequests[caller];
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
        withdrawalRequests[caller] = WithdrawalRequest({
            assets: assets,
            shares: shares,
            requestTime: block.timestamp,
            owner: owner,
            receiver: receiver
        });
        reservedAssets += assets;
        emit WithdrawalRequested(caller, receiver, owner, assets, shares);
    }
}
