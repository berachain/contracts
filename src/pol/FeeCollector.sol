// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { Utils } from "../libraries/Utils.sol";
import { IFeeCollector } from "./interfaces/IFeeCollector.sol";
import { BGTStaker } from "./BGTStaker.sol";

/**
 * @title FeeCollector
 * @author Berachain Team
 * @notice The Fee Collector contract is responsible for collecting fees from Berachain Dapps
 * and auctioning them for a Payout token, which then is distributed among the BGT stakers.
 * @dev This contract is inspired by the Uniswap V3 Factory Owner contract.
 * https://github.com/uniswapfoundation/UniStaker/blob/main/src/V3FactoryOwner.sol
 */
contract FeeCollector is IFeeCollector, PausableUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    using Utils for bytes4;

    /// @notice The MANAGER role.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice The PAUSER role
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @inheritdoc IFeeCollector
    address public payoutToken;

    /// @inheritdoc IFeeCollector
    uint256 public queuedPayoutAmount;

    /// @inheritdoc IFeeCollector
    uint256 public payoutAmount;

    /// @inheritdoc IFeeCollector
    address public rewardReceiver;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address governance,
        address _payoutToken,
        address _rewardReceiver,
        uint256 _payoutAmount
    )
        external
        initializer
    {
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        if (governance == address(0) || _payoutToken == address(0) || _rewardReceiver == address(0)) {
            ZeroAddress.selector.revertWith();
        }
        if (_payoutAmount == 0) PayoutAmountIsZero.selector.revertWith();

        _grantRole(DEFAULT_ADMIN_ROLE, governance);
        // Allow the MANAGER to control the PAUSER_ROLE
        _setRoleAdmin(PAUSER_ROLE, MANAGER_ROLE);

        payoutToken = _payoutToken;
        payoutAmount = _payoutAmount;
        rewardReceiver = _rewardReceiver;

        emit PayoutAmountSet(0, _payoutAmount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    /// @inheritdoc IFeeCollector
    function queuePayoutAmountChange(uint256 _newPayoutAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newPayoutAmount == 0) PayoutAmountIsZero.selector.revertWith();
        emit QueuedPayoutAmount(_newPayoutAmount, payoutAmount);
        queuedPayoutAmount = _newPayoutAmount;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       WRITE FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IFeeCollector
    function claimFees(address _recipient, address[] calldata _feeTokens) external whenNotPaused {
        // Transfer the payout amount of the payout token to the BGTStaker contract from msg.sender.
        IERC20(payoutToken).safeTransferFrom(msg.sender, rewardReceiver, payoutAmount);
        // Notify that the reward amount has been updated.
        BGTStaker(rewardReceiver).notifyRewardAmount(payoutAmount);
        // From all the specified fee tokens, transfer them to the recipient.
        for (uint256 i; i < _feeTokens.length;) {
            address feeToken = _feeTokens[i];
            uint256 feeTokenAmountToTransfer = IERC20(feeToken).balanceOf(address(this));
            IERC20(feeToken).safeTransfer(_recipient, feeTokenAmountToTransfer);
            emit FeesClaimed(msg.sender, _recipient, feeToken, feeTokenAmountToTransfer);
            unchecked {
                ++i;
            }
        }
        emit FeesClaimed(msg.sender, _recipient);

        if (queuedPayoutAmount != 0) _setPayoutAmount();
    }

    /// @inheritdoc IFeeCollector
    function donate(uint256 amount) external whenNotPaused {
        // donate amount should be at least payoutAmount to notify the reward receiver.
        if (amount < payoutAmount) DonateAmountLessThanPayoutAmount.selector.revertWith();

        // Directly send the fees to the reward receiver.
        IERC20(payoutToken).safeTransferFrom(msg.sender, rewardReceiver, amount);
        BGTStaker(rewardReceiver).notifyRewardAmount(amount);

        emit PayoutDonated(msg.sender, amount);
    }

    /// @inheritdoc IFeeCollector
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @inheritdoc IFeeCollector
    function unpause() external onlyRole(MANAGER_ROLE) {
        _unpause();
    }

    /// @notice Set the payout amount to the queued payout amount
    function _setPayoutAmount() internal {
        emit PayoutAmountSet(payoutAmount, queuedPayoutAmount);
        payoutAmount = queuedPayoutAmount;
        queuedPayoutAmount = 0;
    }
}
