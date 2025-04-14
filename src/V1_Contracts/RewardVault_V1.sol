// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { Utils } from "../libraries/Utils.sol";
import { IBeaconDeposit } from "../pol/interfaces/IBeaconDeposit.sol";
import { IRewardVault_V1 } from "./interfaces/IRewardVault_V1.sol";
import { FactoryOwnable } from "../base/FactoryOwnable.sol";
import { StakingRewards } from "../base/StakingRewards.sol";
import { IBeraChef } from "../pol/interfaces/IBeraChef.sol";
import { IDistributor } from "../pol/interfaces/IDistributor.sol";
import { IBGTIncentiveDistributor } from "../pol/interfaces/IBGTIncentiveDistributor.sol";
/// @title Rewards Vault
/// @author Berachain Team
/// @notice This contract is the vault for the Berachain rewards, it handles the staking and rewards accounting of BGT.
/// @dev This contract is taken from the stable and tested:
/// https://github.com/Synthetixio/synthetix/blob/develop/contracts/StakingRewards.sol
/// We are using this model instead of 4626 because we want to incentivize staying in the vault for x period of time to
/// to be considered a 'miner' and not a 'trader'.

contract RewardVault_V1 is
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    FactoryOwnable,
    StakingRewards,
    IRewardVault_V1
{
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

    /// @notice the mapping of incentive token to its incentive data.
    mapping(address token => Incentive) public incentives;

    /// @notice The list of whitelisted tokens.
    address[] public whitelistedTokens;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IRewardVault_V1
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
        maxIncentiveTokensCount = 2;
        // slither-disable-next-line missing-zero-check
        distributor = _distributor;
        beaconDepositContract = IBeaconDeposit(_beaconDepositContract);
        emit DistributorSet(_distributor);
        emit MaxIncentiveTokensCountUpdated(2);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyDistributor() {
        if (msg.sender != distributor) NotDistributor.selector.revertWith();
        _;
    }

    modifier onlyOperatorOrUser(address account) {
        if (msg.sender != account) {
            if (msg.sender != _operators[account]) NotOperator.selector.revertWith();
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

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRewardVault_V1
    function setDistributor(address _rewardDistribution) external onlyFactoryOwner {
        if (_rewardDistribution == address(0)) ZeroAddress.selector.revertWith();
        distributor = _rewardDistribution;
        emit DistributorSet(_rewardDistribution);
    }

    /// @inheritdoc IRewardVault_V1
    function notifyRewardAmount(bytes calldata pubkey, uint256 reward) external onlyDistributor {
        _notifyRewardAmount(reward);
        _processIncentives(pubkey, reward);
    }

    /// @inheritdoc IRewardVault_V1
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyFactoryOwner {
        if (tokenAddress == address(stakeToken)) CannotRecoverStakingToken.selector.revertWith();
        if (incentives[tokenAddress].minIncentiveRate != 0) CannotRecoverIncentiveToken.selector.revertWith();
        IERC20(tokenAddress).safeTransfer(msg.sender, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    /// @inheritdoc IRewardVault_V1
    function setRewardsDuration(uint256 _rewardsDuration) external onlyFactoryOwner {
        _setRewardsDuration(_rewardsDuration);
    }

    /// @inheritdoc IRewardVault_V1
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

    /// @inheritdoc IRewardVault_V1
    function removeIncentiveToken(address token) external onlyFactoryVaultManager onlyWhitelistedToken(token) {
        delete incentives[token];
        // delete the token from the list.
        _deleteWhitelistedTokenFromList(token);
        emit IncentiveTokenRemoved(token);
    }

    /// @inheritdoc IRewardVault_V1
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

    /// @inheritdoc IRewardVault_V1
    function setMaxIncentiveTokensCount(uint8 _maxIncentiveTokensCount) external onlyFactoryOwner {
        if (_maxIncentiveTokensCount < whitelistedTokens.length) {
            InvalidMaxIncentiveTokensCount.selector.revertWith();
        }
        maxIncentiveTokensCount = _maxIncentiveTokensCount;
        emit MaxIncentiveTokensCountUpdated(_maxIncentiveTokensCount);
    }

    /// @inheritdoc IRewardVault_V1
    function pause() external onlyFactoryVaultPauser {
        _pause();
    }

    /// @inheritdoc IRewardVault_V1
    function unpause() external onlyFactoryVaultManager {
        _unpause();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          GETTERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRewardVault_V1
    function operator(address account) external view returns (address) {
        return _operators[account];
    }

    /// @inheritdoc IRewardVault_V1
    function getWhitelistedTokensCount() external view returns (uint256) {
        return whitelistedTokens.length;
    }

    /// @inheritdoc IRewardVault_V1
    function getWhitelistedTokens() public view returns (address[] memory) {
        return whitelistedTokens;
    }

    /// @inheritdoc IRewardVault_V1
    function getTotalDelegateStaked(address account) external view returns (uint256) {
        return _delegateStake[account].delegateTotalStaked;
    }

    /// @inheritdoc IRewardVault_V1
    function getDelegateStake(address account, address delegate) external view returns (uint256) {
        return _delegateStake[account].stakedByDelegate[delegate];
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          WRITES                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRewardVault_V1
    function stake(uint256 amount) external nonReentrant whenNotPaused {
        _stake(msg.sender, amount);
    }

    /// @inheritdoc IRewardVault_V1
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

    /// @inheritdoc IRewardVault_V1
    function withdraw(uint256 amount) external nonReentrant checkSelfStakedBalance(msg.sender, amount) {
        _withdraw(msg.sender, amount);
    }

    /// @inheritdoc IRewardVault_V1
    function delegateWithdraw(address account, uint256 amount) external nonReentrant {
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

    /// @inheritdoc IRewardVault_V1
    function getReward(
        address account,
        address recipient
    )
        external
        nonReentrant
        onlyOperatorOrUser(account)
        returns (uint256)
    {
        return _getReward(account, recipient);
    }

    /// @inheritdoc IRewardVault_V1
    function exit(address recipient) external nonReentrant {
        // self-staked amount
        uint256 amount = _accountInfo[msg.sender].balance - _delegateStake[msg.sender].delegateTotalStaked;
        _withdraw(msg.sender, amount);
        _getReward(msg.sender, recipient);
    }

    /// @inheritdoc IRewardVault_V1
    function setOperator(address _operator) external {
        _operators[msg.sender] = _operator;
        emit OperatorSet(msg.sender, _operator);
    }

    /// @inheritdoc IRewardVault_V1
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

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        incentive.amountRemaining = amountRemainingBefore + amount;
        // Allows updating the incentive rate if the remaining incentive amount is 0 and
        // the `incentiveRate` is greater than or equal to the `minIncentiveRate`.
        if (amountRemainingBefore == 0 && incentiveRate >= minIncentiveRate) {
            incentive.incentiveRate = incentiveRate;
        }
        // Allows increasing the incentive rate, provided the `amount` suffices to incentivize the same amount of BGT.
        // If the current rate is 100 USDC/BGT and the amount remaining is 50 USDC, incentivizing 0.5 BGT,
        // then for a new rate of 150 USDC/BGT, the input amount should be at least 0.5 * (150 - 100) = 25 USDC,
        // ensuring that it will still incentivize 0.5 BGT.
        else if (incentiveRate > incentiveRateStored) {
            uint256 rateDelta;
            unchecked {
                rateDelta = incentiveRate - incentiveRateStored;
            }
            if (amount >= FixedPointMathLib.mulDiv(amountRemainingBefore, rateDelta, incentiveRateStored)) {
                incentive.incentiveRate = incentiveRate;
            }
        }
        emit IncentiveAdded(token, msg.sender, amount, incentive.incentiveRate);
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
}
