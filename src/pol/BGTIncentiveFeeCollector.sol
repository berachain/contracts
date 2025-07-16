// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { Utils } from "../libraries/Utils.sol";
import { IWBERAStakerVault } from "./interfaces/IWBERAStakerVault.sol";
import { IBGTIncentiveFeeCollector } from "./interfaces/IBGTIncentiveFeeCollector.sol";

/// @title BGTIncentiveFeeCollector
/// @author Berachain Team
/// @notice Collects the fees on the incentives posted on reward vaults and auction them for WBERA.
/// Accrued WBERA serves as a payout for the stakers of `WBERAStakerVault.sol`.
/// @dev This contract is inspired by the `FeeCollector.sol` for auctioning collected tokens.
contract BGTIncentiveFeeCollector is
    IBGTIncentiveFeeCollector,
    PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;
    using Utils for bytes4;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*.                         CONSTANTS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The PAUSER role
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice The MANAGER role.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice The WBERA token address, serves as payout token.
    address public constant WBERA = 0x6969696969696969696969696969696969696969;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*.                          STORAGE                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBGTIncentiveFeeCollector
    uint256 public queuedPayoutAmount;

    /// @inheritdoc IBGTIncentiveFeeCollector
    uint256 public payoutAmount;

    /// @inheritdoc IBGTIncentiveFeeCollector
    address public wberaStakerVault;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the contract.
    /// @param governance The address of the governance contract.
    /// @param _payoutAmount The payout amount.
    function initialize(address governance, uint256 _payoutAmount, address _wberaStakerVault) public initializer {
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        if (governance == address(0)) ZeroAddress.selector.revertWith();
        if (_payoutAmount == 0) PayoutAmountIsZero.selector.revertWith();
        if (_wberaStakerVault == address(0)) ZeroAddress.selector.revertWith();

        _grantRole(DEFAULT_ADMIN_ROLE, governance);
        // Allow the MANAGER to control the PAUSER_ROLE
        _setRoleAdmin(PAUSER_ROLE, MANAGER_ROLE);

        payoutAmount = _payoutAmount;
        emit PayoutAmountSet(0, _payoutAmount);

        wberaStakerVault = _wberaStakerVault;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    /// @inheritdoc IBGTIncentiveFeeCollector
    function queuePayoutAmountChange(uint256 _newPayoutAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newPayoutAmount == 0) PayoutAmountIsZero.selector.revertWith();
        emit QueuedPayoutAmount(_newPayoutAmount, payoutAmount);
        queuedPayoutAmount = _newPayoutAmount;
    }

    /// @inheritdoc IBGTIncentiveFeeCollector
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @inheritdoc IBGTIncentiveFeeCollector
    function unpause() external onlyRole(MANAGER_ROLE) {
        _unpause();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       TOKENS AUCTION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBGTIncentiveFeeCollector
    function claimFees(address _recipient, address[] calldata _feeTokens) external whenNotPaused {
        // Transfer the payout amount of the payout token to the WBERAStakerVault contract from msg.sender.
        IERC20(WBERA).safeTransferFrom(msg.sender, wberaStakerVault, payoutAmount);
        // From all the specified fee tokens, transfer them to the recipient.
        for (uint256 i; i < _feeTokens.length;) {
            address feeToken = _feeTokens[i];
            uint256 feeTokenAmountToTransfer = IERC20(feeToken).balanceOf(address(this));
            IERC20(feeToken).safeTransfer(_recipient, feeTokenAmountToTransfer);
            emit IncentiveFeeTokenClaimed(msg.sender, _recipient, feeToken, feeTokenAmountToTransfer);
            unchecked {
                ++i;
            }
        }
        emit IncentiveFeesClaimed(msg.sender, _recipient);

        if (queuedPayoutAmount != 0) _setPayoutAmount();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Set the payout amount to the queued payout amount
    function _setPayoutAmount() internal {
        emit PayoutAmountSet(payoutAmount, queuedPayoutAmount);
        payoutAmount = queuedPayoutAmount;
        queuedPayoutAmount = 0;
    }
}
