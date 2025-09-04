// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { Utils } from "../libraries/Utils.sol";
import { IBGTStaker } from "./interfaces/IBGTStaker.sol";
import { IPOLErrors } from "./interfaces/IPOLErrors.sol";
import { StakingRewards } from "../base/StakingRewards.sol";

/// @title BGTStaker
/// @author Berachain Team
/// @notice A contract that enables BGT token holders to stake their tokens and earn dApp fees without transferring
/// their tokens. This contract acts as a non-custodial staking solution where BGT tokens remain in the holder's
/// wallet while still allowing them to participate in fee distribution. The contract integrates with the FeeCollector
/// to distribute protocol fees to BGT delegators.
/// @dev Inherits StakingRewards for reward distribution mechanics and uses a custom staking mechanism that doesn't
/// require token transfers.
contract BGTStaker is IBGTStaker, OwnableUpgradeable, UUPSUpgradeable, StakingRewards {
    using Utils for bytes4;
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The fee collector contract that is allowed to notify rewards.
    address public FEE_COLLECTOR;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         INITIALIZER                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _bgt,
        address _feeCollector,
        address _governance,
        address _rewardToken
    )
        external
        initializer
    {
        __Ownable_init(_governance);
        __StakingRewards_init(_bgt, _rewardToken, 7 days);
        __UUPSUpgradeable_init();
        FEE_COLLECTOR = _feeCollector;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Throws if called by any account other than BGT contract.
    modifier onlyBGT() {
        if (msg.sender != address(stakeToken)) NotBGT.selector.revertWith();
        _;
    }

    /// @dev Throws if called by any account other than the fee collector.
    modifier onlyFeeCollector() {
        if (msg.sender != FEE_COLLECTOR) NotFeeCollector.selector.revertWith();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    /// @inheritdoc IBGTStaker
    function notifyRewardAmount(uint256 reward) external onlyFeeCollector {
        _notifyRewardAmount(reward);
    }

    /// @inheritdoc IBGTStaker
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        if (tokenAddress == address(rewardToken)) CannotRecoverRewardToken.selector.revertWith();
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    /// @inheritdoc IBGTStaker
    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        _setRewardsDuration(_rewardsDuration);
    }

    /// @inheritdoc IBGTStaker
    function stake(address account, uint256 amount) external onlyBGT {
        _stake(account, amount);
    }

    /// @inheritdoc IBGTStaker
    function withdraw(address account, uint256 amount) external onlyBGT {
        _withdraw(account, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  STATE MUTATING FUNCTIONS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBGTStaker
    function getReward() external returns (uint256) {
        return _getReward(msg.sender, msg.sender);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Override the internal function to prevent transferring BGT.
    function _safeTransferFromStakeToken(address from, uint256 amount) internal override { }

    /// @dev Override the internal function to prevent transferring BGT.
    function _safeTransferStakeToken(address to, uint256 amount) internal override { }
}
