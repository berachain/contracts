// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { Utils } from "../../libraries/Utils.sol";
import { IBeaconDeposit } from "../interfaces/IBeaconDeposit.sol";
import { IRewardVault } from "../interfaces/IRewardVault.sol";
import { FactoryOwnable } from "../../base/FactoryOwnable.sol";
import { StakingRewards } from "../../base/StakingRewards.sol";
import { IBeraChef } from "../interfaces/IBeraChef.sol";
import { IDistributor } from "../interfaces/IDistributor.sol";
import { IBGTIncentiveDistributor } from "../interfaces/IBGTIncentiveDistributor.sol";
import { IRewardVaultFactory } from "../interfaces/IRewardVaultFactory.sol";

/// @title Rewards Vault
/// @author Berachain Team
/// @notice This contract is the vault for the Berachain rewards, it handles the staking and rewards accounting of BGT.
/// @dev This contract is taken from the stable and tested:
/// https://github.com/Synthetixio/synthetix/blob/develop/contracts/StakingRewards.sol
/// We are using this model instead of 4626 because we want to incentivize staying in the vault for x period of time
/// to be considered a 'miner' and not a 'trader'.
contract RewardVault is PausableUpgradeable, ReentrancyGuardUpgradeable, FactoryOwnable, StakingRewards, IRewardVault {
    using Utils for bytes4;
    using SafeERC20 for IERC20;
    using Utils for address;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STRUCTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Struct to hold delegate stake data.
    /// @param delegateTotalStaked The total amount staked by delegates.
    /// @param stakedByDelegate The mapping of the amount staked by each delegate.
    struct DelegateStake {
        uint256 delegateTotalStaked;
        mapping(address delegate => uint256 amount) stakedByDelegate;
    }

    /// @notice Struct to hold an incentive data.
    /// @param minIncentiveRate The minimum amount of the token to incentivize per BGT emission.
    /// @param incentiveRate The amount of the token to incentivize per BGT emission.
    /// @param amountRemaining The amount of the token remaining to incentivize.
    /// @param manager The address of the manager that can addIncentive for this incentive token.
    struct Incentive {
        uint256 minIncentiveRate;
        uint256 incentiveRate;
        uint256 amountRemaining;
        address manager;
    }

    uint256 private constant MAX_INCENTIVE_RATE = 1e36; // for 18 decimal token, this will mean 1e18 incentiveTokens
    // per BGT emission.

    // Safe gas limit for low level call operations to avoid griefing.
    // This is mostly for low level call like approve, receiveIncentive (IBGTIncentiveDistributor which uses
    // transferFrom).
    uint256 private constant SAFE_GAS_LIMIT = 500_000;

    /// @notice The minimum reward duration.
    uint256 public constant MIN_REWARD_DURATION = 3 days;
    /// @notice The maximum reward duration.
    uint256 public constant MAX_REWARD_DURATION = 7 days;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The maximum count of incentive tokens that can be stored.
    uint8 public maxIncentiveTokensCount;

    /// @notice The address of the distributor contract.
    address public distributor;

    /// @notice The BeaconDeposit contract.
    IBeaconDeposit public beaconDepositContract;

    mapping(address account => DelegateStake) internal _delegateStake;

    /// @notice The mapping of accounts to their operators.
    mapping(address account => address operator) internal _operators;

    /// @notice The mapping of incentive token to its incentive data.
    mapping(address token => Incentive) public incentives;

    /// @notice The list of whitelisted tokens.
    address[] public whitelistedTokens;

    /// @notice The address authorized to manage reward vault operations and configurations.
    /// @dev This role is typically assigned to dApp teams to enable them to configure reward distribution parameters.
    address public rewardVaultManager;

    // deprecated
    uint256 private _lastRewardDurationChangeTimestamp;

    /// @notice The target rewards per second, scaled by PRECISION.
    /// @dev This acts as both a maximum and a target rate. When the calculated reward rate exceeds this value,
    /// the duration is dynamically adjusted to achieve this target rate, but never goes below MIN_REWARD_DURATION.
    /// This prevents the issue where a spike in rewards would permanently expand the duration, causing subsequent
    /// smaller rewards to be spread over longer periods with very low rates.
    uint256 public targetRewardsPerSecond;

    /// @notice The pending rewards duration.
    /// @dev Comes into effect during the next `notifyRewardAmount` call.
    uint256 public pendingRewardsDuration;

    /// @notice The reward duration in case targetRewardsPerSecond is not met.
    /// @dev must be between MIN_REWARD_DURATION and MAX_REWARD_DURATION and can be set only by reward vault manager.
    uint256 public minRewardDurationForTargetRate;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IRewardVault
    function initialize(
        address _beaconDepositContract,
        address _bgt,
        address _distributor,
        address _stakingToken
    )
        external
        initializer
    {
        __FactoryOwnable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
        __StakingRewards_init(_stakingToken, _bgt, 7 days);
        maxIncentiveTokensCount = 3;
        // slither-disable-next-line missing-zero-check
        distributor = _distributor;
        beaconDepositContract = IBeaconDeposit(_beaconDepositContract);
        emit DistributorSet(_distributor);
        emit MaxIncentiveTokensCountUpdated(maxIncentiveTokensCount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyDistributor() {
        if (msg.sender != distributor) NotDistributor.selector.revertWith();
        _;
    }

    modifier onlyUserOrOperator(address account) {
        IRewardVaultFactory factory = IRewardVaultFactory(factory());
        address rewardVaultHelper = factory.rewardVaultHelper();

        if (msg.sender != account && msg.sender != rewardVaultHelper) {
            if (msg.sender != _operators[account]) {
                NotOperator.selector.revertWith();
            }
        }
        _;
    }

    modifier checkSelfStakedBalance(address account, uint256 amount) {
        _checkSelfStakedBalance(account, amount);
        _;
    }

    modifier onlyWhitelistedToken(address token) {
        if (incentives[token].minIncentiveRate == 0) TokenNotWhitelisted.selector.revertWith();
        _;
    }

    modifier onlyRewardVaultManager() {
        if (msg.sender != rewardVaultManager) NotRewardVaultManager.selector.revertWith();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRewardVault
    function setDistributor(address _rewardDistribution) external onlyFactoryOwner {
        if (_rewardDistribution == address(0)) ZeroAddress.selector.revertWith();
        distributor = _rewardDistribution;
        emit DistributorSet(_rewardDistribution);
    }

    /// @inheritdoc IRewardVault
    function notifyRewardAmount(bytes calldata pubkey, uint256 reward) external onlyDistributor {
        _notifyRewardAmount(reward);
        _processIncentives(pubkey, reward);
    }

    /// @inheritdoc IRewardVault
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyFactoryOwner {
        if (incentives[tokenAddress].minIncentiveRate != 0) CannotRecoverIncentiveToken.selector.revertWith();
        if (tokenAddress == address(stakeToken)) {
            uint256 maxRecoveryAmount = IERC20(stakeToken).balanceOf(address(this)) - totalSupply;
            if (tokenAmount > maxRecoveryAmount) {
                NotEnoughBalance.selector.revertWith();
            }
        }
        IERC20(tokenAddress).safeTransfer(msg.sender, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    /// @inheritdoc IRewardVault
    function setRewardsDuration(uint256 _rewardsDuration) external onlyRewardVaultManager {
        // protocol must not have switched to targetRewardsPerSecond logic.
        if (targetRewardsPerSecond != 0) DurationChangeNotAllowed.selector.revertWith();
        // check if the reward duration is within the allowed range.
        if (_rewardsDuration < MIN_REWARD_DURATION || _rewardsDuration > MAX_REWARD_DURATION) {
            InvalidRewardDuration.selector.revertWith();
        }
        // store the pending rewards duration.
        pendingRewardsDuration = _rewardsDuration;
    }

    /// @inheritdoc IRewardVault
    function setTargetRewardsPerSecond(uint256 _targetRewardsPerSecond) external onlyRewardVaultManager {
        // set the `minRewardDurationForTargetRate` to `MIN_REWARD_DURATION` if it is not set.
        if (minRewardDurationForTargetRate == 0) {
            minRewardDurationForTargetRate = MIN_REWARD_DURATION;
            emit MinRewardDurationForTargetRateUpdated(MIN_REWARD_DURATION, 0);
        }
        // if we are setting target rate to 0, this means we are switching back to duration based distribution
        // in duration based distribution, duration must be within the allowed range.
        // duration will never go below `MIN_REWARD_DURATION` as `minRewardDurationForTargetRate` can never be less
        // than `MIN_REWARD_DURATION`.
        // so we need to check if current duration is higher than `MAX_REWARD_DURATION`, if yes, set it to
        // `MAX_REWARD_DURATION`.
        if (_targetRewardsPerSecond == 0 && rewardsDuration > MAX_REWARD_DURATION) {
            pendingRewardsDuration = MAX_REWARD_DURATION;
        }

        emit TargetRewardsPerSecondUpdated(_targetRewardsPerSecond, targetRewardsPerSecond);
        targetRewardsPerSecond = _targetRewardsPerSecond;
    }

    /// @inheritdoc IRewardVault
    function setMinRewardDurationForTargetRate(uint256 _minRewardDurationForTargetRate)
        external
        onlyRewardVaultManager
    {
        // check if the reward duration is within the allowed range.
        if (
            _minRewardDurationForTargetRate < MIN_REWARD_DURATION
                || _minRewardDurationForTargetRate > MAX_REWARD_DURATION
        ) {
            InvalidRewardDuration.selector.revertWith();
        }
        emit MinRewardDurationForTargetRateUpdated(_minRewardDurationForTargetRate, minRewardDurationForTargetRate);
        minRewardDurationForTargetRate = _minRewardDurationForTargetRate;
    }

    /// @inheritdoc IRewardVault
    function whitelistIncentiveToken(
        address token,
        uint256 minIncentiveRate,
        address manager
    )
        external
        onlyFactoryOwner
    {
        // validate `minIncentiveRate` value
        if (minIncentiveRate == 0) MinIncentiveRateIsZero.selector.revertWith();
        if (minIncentiveRate > MAX_INCENTIVE_RATE) IncentiveRateTooHigh.selector.revertWith();

        // validate token and manager address
        if (token == address(0) || manager == address(0)) ZeroAddress.selector.revertWith();

        Incentive storage incentive = incentives[token];
        if (whitelistedTokens.length == maxIncentiveTokensCount || incentive.minIncentiveRate != 0) {
            TokenAlreadyWhitelistedOrLimitReached.selector.revertWith();
        }
        whitelistedTokens.push(token);
        //set the incentive rate to the minIncentiveRate.
        incentive.incentiveRate = minIncentiveRate;
        incentive.minIncentiveRate = minIncentiveRate;
        // set the manager
        incentive.manager = manager;
        emit IncentiveTokenWhitelisted(token, minIncentiveRate, manager);
    }

    /// @inheritdoc IRewardVault
    function removeIncentiveToken(address token) external onlyFactoryVaultManager onlyWhitelistedToken(token) {
        delete incentives[token];
        // delete the token from the list.
        _deleteWhitelistedTokenFromList(token);
        emit IncentiveTokenRemoved(token);
    }

    /// @inheritdoc IRewardVault
    function updateIncentiveManager(
        address token,
        address newManager
    )
        external
        onlyFactoryOwner
        onlyWhitelistedToken(token)
    {
        if (newManager == address(0)) ZeroAddress.selector.revertWith();
        Incentive storage incentive = incentives[token];
        // cache the current manager
        address currentManager = incentive.manager;
        incentive.manager = newManager;
        emit IncentiveManagerChanged(token, newManager, currentManager);
    }

    /// @inheritdoc IRewardVault
    function setMaxIncentiveTokensCount(uint8 _maxIncentiveTokensCount) external onlyFactoryOwner {
        if (_maxIncentiveTokensCount < whitelistedTokens.length) {
            InvalidMaxIncentiveTokensCount.selector.revertWith();
        }
        maxIncentiveTokensCount = _maxIncentiveTokensCount;
        emit MaxIncentiveTokensCountUpdated(_maxIncentiveTokensCount);
    }

    /// @inheritdoc IRewardVault
    function pause() external onlyFactoryVaultPauser {
        _pause();
    }

    /// @inheritdoc IRewardVault
    function unpause() external onlyFactoryVaultManager {
        _unpause();
    }

    /// @inheritdoc IRewardVault
    function setRewardVaultManager(address _rewardVaultManager) external onlyFactoryVaultManager {
        if (_rewardVaultManager == address(0)) ZeroAddress.selector.revertWith();
        emit RewardVaultManagerSet(_rewardVaultManager, rewardVaultManager);
        rewardVaultManager = _rewardVaultManager;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          GETTERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRewardVault
    function operator(address account) external view returns (address) {
        return _operators[account];
    }

    /// @inheritdoc IRewardVault
    function getWhitelistedTokensCount() external view returns (uint256) {
        return whitelistedTokens.length;
    }

    /// @inheritdoc IRewardVault
    function getWhitelistedTokens() public view returns (address[] memory) {
        return whitelistedTokens;
    }

    /// @inheritdoc IRewardVault
    function getTotalDelegateStaked(address account) external view returns (uint256) {
        return _delegateStake[account].delegateTotalStaked;
    }

    /// @inheritdoc IRewardVault
    function getDelegateStake(address account, address delegate) external view returns (uint256) {
        return _delegateStake[account].stakedByDelegate[delegate];
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          WRITES                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRewardVault
    function stake(uint256 amount) external nonReentrant whenNotPaused {
        _stake(msg.sender, amount);
    }

    /// @inheritdoc IRewardVault
    function delegateStake(address account, uint256 amount) external nonReentrant whenNotPaused {
        if (msg.sender == account) NotDelegate.selector.revertWith();

        _stake(account, amount);
        unchecked {
            DelegateStake storage info = _delegateStake[account];
            // Overflow is not possible for `delegateTotalStaked` as it is bounded by the `totalSupply` which has
            // been incremented in `_stake`.
            info.delegateTotalStaked += amount;

            // If the total staked by all delegates does not overflow, this increment is safe.
            info.stakedByDelegate[msg.sender] += amount;
        }
        emit DelegateStaked(account, msg.sender, amount);
    }

    /// @inheritdoc IRewardVault
    function stakeOnBehalf(address account, uint256 amount) external nonReentrant whenNotPaused {
        _stake(account, amount);
    }

    /// @inheritdoc IRewardVault
    function withdraw(uint256 amount) external nonReentrant checkSelfStakedBalance(msg.sender, amount) whenNotPaused {
        _withdraw(msg.sender, amount);
    }

    /// @inheritdoc IRewardVault
    function delegateWithdraw(address account, uint256 amount) external nonReentrant whenNotPaused {
        if (msg.sender == account) NotDelegate.selector.revertWith();

        unchecked {
            DelegateStake storage info = _delegateStake[account];
            uint256 stakedByDelegate = info.stakedByDelegate[msg.sender];
            if (stakedByDelegate < amount) InsufficientDelegateStake.selector.revertWith();
            info.stakedByDelegate[msg.sender] = stakedByDelegate - amount;
            // underflow is impossible because `info.delegateTotalStaked` >= `stakedByDelegate` >= `amount`
            info.delegateTotalStaked -= amount;
        }
        _withdraw(account, amount);
        emit DelegateWithdrawn(account, msg.sender, amount);
    }

    /// @inheritdoc IRewardVault
    function getReward(
        address account,
        address recipient
    )
        external
        nonReentrant
        whenNotPaused
        onlyUserOrOperator(account)
        returns (uint256)
    {
        return _getReward(account, recipient);
    }

    /// @inheritdoc IRewardVault
    function getPartialReward(
        address account,
        address recipient,
        uint256 amount
    )
        external
        nonReentrant
        whenNotPaused
        onlyUserOrOperator(account)
    {
        _getPartialReward(account, recipient, amount);
    }

    /// @inheritdoc IRewardVault
    function exit(address recipient) external nonReentrant whenNotPaused {
        // self-staked amount
        uint256 amount = _accountInfo[msg.sender].balance - _delegateStake[msg.sender].delegateTotalStaked;
        _withdraw(msg.sender, amount);
        _getReward(msg.sender, recipient);
    }

    /// @inheritdoc IRewardVault
    function setOperator(address _operator) external {
        _operators[msg.sender] = _operator;
        emit OperatorSet(msg.sender, _operator);
    }

    /// @inheritdoc IRewardVault
    function addIncentive(
        address token,
        uint256 amount,
        uint256 incentiveRate
    )
        external
        nonReentrant
        onlyWhitelistedToken(token)
    {
        if (incentiveRate > MAX_INCENTIVE_RATE) IncentiveRateTooHigh.selector.revertWith();
        Incentive storage incentive = incentives[token];
        (uint256 minIncentiveRate, uint256 incentiveRateStored, uint256 amountRemainingBefore, address manager) =
            (incentive.minIncentiveRate, incentive.incentiveRate, incentive.amountRemaining, incentive.manager);

        // Only allow the incentive token manager to add incentive.
        if (msg.sender != manager) NotIncentiveManager.selector.revertWith();

        // The incentive amount should be equal to or greater than the `minIncentiveRate` to avoid spamming.
        // If the `minIncentiveRate` is 100 USDC/BGT, the amount should be at least 100 USDC.
        if (amount < minIncentiveRate) AmountLessThanMinIncentiveRate.selector.revertWith();

        // The incentive rate should be greater than or equal to the `minIncentiveRate`.
        if (incentiveRate < minIncentiveRate) InvalidIncentiveRate.selector.revertWith();

        // Transfer the full amount to the contract.
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        incentive.amountRemaining = amountRemainingBefore + amount;

        // Allows updating the incentive rate if the remaining incentive amount is 0.
        // Allow to decrease the incentive rate when accounted incentives are finished.
        if (amountRemainingBefore == 0) {
            incentive.incentiveRate = incentiveRate;
        }
        // Always allow to increase the incentive rate.
        else if (incentiveRate >= incentiveRateStored) {
            incentive.incentiveRate = incentiveRate;
        }
        // If the remaining incentive amount is not 0 and the new rate is less than the current rate, revert.
        else {
            InvalidIncentiveRate.selector.revertWith();
        }

        emit IncentiveAdded(token, msg.sender, amount, incentive.incentiveRate);
    }

    /// @inheritdoc IRewardVault
    function accountIncentives(address token, uint256 amount) external nonReentrant onlyWhitelistedToken(token) {
        Incentive storage incentive = incentives[token];
        (uint256 minIncentiveRate, uint256 incentiveRateStored, uint256 amountRemainingBefore, address manager) =
            (incentive.minIncentiveRate, incentive.incentiveRate, incentive.amountRemaining, incentive.manager);

        // Only allow the incentive token manager to account for cumulated incentives.
        if (msg.sender != manager) NotIncentiveManager.selector.revertWith();

        if (amount < minIncentiveRate) AmountLessThanMinIncentiveRate.selector.revertWith();

        uint256 incentiveBalance = IERC20(token).balanceOf(address(this));
        if (token == address(stakeToken)) {
            incentiveBalance -= totalSupply;
        }

        if (amount > incentiveBalance - amountRemainingBefore) NotEnoughBalance.selector.revertWith();

        incentive.amountRemaining += amount;

        emit IncentiveAdded(token, msg.sender, amount, incentiveRateStored);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        INTERNAL FUNCTIONS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Check if the account has enough self-staked balance.
    /// @param account The account to check the self-staked balance for.
    /// @param amount The amount being withdrawn.
    function _checkSelfStakedBalance(address account, uint256 amount) internal view {
        unchecked {
            uint256 selfStaked = _accountInfo[account].balance - _delegateStake[account].delegateTotalStaked;
            if (selfStaked < amount) InsufficientSelfStake.selector.revertWith();
        }
    }

    /// @dev The Distributor grants this contract the allowance to transfer the BGT in its balance.
    function _safeTransferRewardToken(address to, uint256 amount) internal override {
        rewardToken.safeTransferFrom(distributor, to, amount);
    }

    // Ensure the provided reward amount is not more than the balance in the contract.
    // This keeps the reward rate in the right range, preventing overflows due to
    // very high values of rewardRate in the earned and rewardsPerToken functions;
    // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
    function _checkRewardSolvency() internal view override {
        uint256 allowance = rewardToken.allowance(distributor, address(this));
        if (undistributedRewards / PRECISION > allowance) InsolventReward.selector.revertWith();
    }

    /// @notice process the incentives for a validator.
    /// @notice If a token transfer consumes more than 500k gas units, the transfer alone will fail.
    /// @param pubkey The pubkey of the validator to process the incentives for.
    /// @param bgtEmitted The amount of BGT emitted by the validator.
    function _processIncentives(bytes calldata pubkey, uint256 bgtEmitted) internal {
        // Validator's operator corresponding to the pubkey receives the incentives.
        // The pubkey -> operator relationship is maintained by the BeaconDeposit contract.
        address _operator = beaconDepositContract.getOperator(pubkey);
        IBeraChef beraChef = IDistributor(distributor).beraChef();
        address bgtIncentiveDistributor = getBGTIncentiveDistributor();

        uint256 whitelistedTokensCount = whitelistedTokens.length;
        unchecked {
            for (uint256 i; i < whitelistedTokensCount; ++i) {
                address token = whitelistedTokens[i];
                Incentive storage incentive = incentives[token];
                uint256 amount = FixedPointMathLib.mulDiv(bgtEmitted, incentive.incentiveRate, PRECISION);
                uint256 amountRemaining = incentive.amountRemaining;
                amount = FixedPointMathLib.min(amount, amountRemaining);
                // collect the incentive fee.
                (amount, amountRemaining) = _collectIncentiveFee(token, amount, amountRemaining);

                uint256 validatorShare;
                if (amount > 0) {
                    validatorShare = beraChef.getValidatorIncentiveTokenShare(pubkey, amount);
                    amount -= validatorShare;
                }

                if (validatorShare > 0) {
                    // Transfer the validator share of the incentive to its operator address.
                    // slither-disable-next-line arbitrary-send-erc20
                    bool success = token.trySafeTransfer(_operator, validatorShare);
                    if (success) {
                        // Update the remaining amount only if tokens were transferred.
                        amountRemaining -= validatorShare;
                        emit IncentivesProcessed(pubkey, token, bgtEmitted, validatorShare);
                    } else {
                        emit IncentivesProcessFailed(pubkey, token, bgtEmitted, validatorShare);
                    }
                }

                if (amount > 0) {
                    // Transfer the remaining amount of the incentive to the bgtIncentiveDistributor contract for
                    // distribution among BGT boosters.
                    // give the bgtIncentiveDistributor the allowance to transfer the incentive token.
                    bytes memory data = abi.encodeCall(IERC20.approve, (bgtIncentiveDistributor, amount));
                    (bool success,) = token.call{ gas: SAFE_GAS_LIMIT }(data);
                    if (success) {
                        // reuse the already defined data variable to avoid stack too deep error.
                        data = abi.encodeCall(IBGTIncentiveDistributor.receiveIncentive, (pubkey, token, amount));
                        (success,) = bgtIncentiveDistributor.call{ gas: SAFE_GAS_LIMIT }(data);
                        if (success) {
                            amountRemaining -= amount;
                            emit BGTBoosterIncentivesProcessed(pubkey, token, bgtEmitted, amount);
                        } else {
                            // If the transfer fails, set the allowance back to 0.
                            // If we don't reset the allowance, the approved tokens remain unused, and future calls to
                            // _processIncentives would revert for tokens like USDT that require allowance to be 0
                            // before setting a new value, blocking the entire incentive distribution process.
                            data = abi.encodeCall(IERC20.approve, (bgtIncentiveDistributor, 0));
                            (success,) = token.call{ gas: SAFE_GAS_LIMIT }(data);
                            emit BGTBoosterIncentivesProcessFailed(pubkey, token, bgtEmitted, amount);
                        }
                    }
                    // if the approve fails, log the failure in sending the incentive to the bgtIncentiveDistributor.
                    else {
                        emit BGTBoosterIncentivesProcessFailed(pubkey, token, bgtEmitted, amount);
                    }
                }
                incentive.amountRemaining = amountRemaining;
            }
        }
    }

    function _deleteWhitelistedTokenFromList(address token) internal {
        uint256 activeTokens = whitelistedTokens.length;
        // The length of `whitelistedTokens` cannot be 0 because the `onlyWhitelistedToken` check has already been
        // performed.
        unchecked {
            for (uint256 i; i < activeTokens; ++i) {
                if (token == whitelistedTokens[i]) {
                    whitelistedTokens[i] = whitelistedTokens[activeTokens - 1];
                    whitelistedTokens.pop();
                    return;
                }
            }
        }
    }

    function _collectIncentiveFee(
        address token,
        uint256 amount,
        uint256 amountRemaining
    )
        internal
        returns (uint256, uint256)
    {
        // Computes the fee amount based on the incentive fee rate, and transfers it to the collector.
        IRewardVaultFactory factory = IRewardVaultFactory(factory());
        uint256 feeAmount = factory.getIncentiveFeeAmount(amount);
        if (feeAmount > 0) {
            amount -= feeAmount;
            bool success = token.trySafeTransfer(factory.bgtIncentiveFeeCollector(), feeAmount);
            if (success) {
                amountRemaining -= feeAmount;
                emit IncentiveFeeCollected(token, feeAmount);
            } else {
                emit IncentiveFeeCollectionFailed(token, feeAmount);
            }
        }
        return (amount, amountRemaining);
    }

    function _setRewardRate() internal override {
        // if the pending rewards duration is 0, use the current rewards duration,
        // otherwise use the pending rewards duration.
        uint256 _rewardsDuration = pendingRewardsDuration == 0 ? rewardsDuration : pendingRewardsDuration;
        // clear the pending rewards duration.
        pendingRewardsDuration = 0;
        uint256 _targetRewardsPerSecond = targetRewardsPerSecond; // cache storage read
        uint256 _rewardRate = undistributedRewards / _rewardsDuration;

        if (_targetRewardsPerSecond > 0) {
            // Always try to achieve the target rate by adjusting duration
            uint256 targetDuration = undistributedRewards / _targetRewardsPerSecond;

            // Ensure the duration doesn't go below the minimum
            if (targetDuration < minRewardDurationForTargetRate) {
                // If we can't achieve the target rate within min duration,
                // calculate the rate based on minimum duration
                _rewardRate = undistributedRewards / minRewardDurationForTargetRate;
                targetDuration = minRewardDurationForTargetRate;
            } else {
                // Use the target rate and update duration
                _rewardRate = _targetRewardsPerSecond;
            }
            _rewardsDuration = targetDuration;
        }
        // update the rewards duration if it has changed
        if (_rewardsDuration != rewardsDuration) {
            _setRewardsDuration(_rewardsDuration);
        }
        rewardRate = _rewardRate;
        periodFinish = block.timestamp + _rewardsDuration;
        undistributedRewards -= _rewardRate * _rewardsDuration;
    }

    function _getPartialReward(address account, address recipient, uint256 amount) internal updateReward(account) {
        Info storage info = _accountInfo[account];
        uint256 reward = info.unclaimedReward; // get the rewards owed to the account
        if (amount > reward) AmountGreaterThanReward.selector.revertWith();
        if (amount != 0) {
            info.unclaimedReward = reward - amount;
            _safeTransferRewardToken(recipient, amount);
            emit RewardPaid(account, recipient, amount);
        }
    }
}
