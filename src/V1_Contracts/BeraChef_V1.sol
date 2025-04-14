// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { Utils } from "../libraries/Utils.sol";
import { IBeaconDeposit } from "../pol/interfaces/IBeaconDeposit.sol";
import { IBeraChef_V1 } from "./interfaces/IBeraChef_V1.sol";
import { RewardVault } from "../pol/rewards/RewardVault.sol";
import { IRewardVaultFactory } from "../pol/interfaces/IRewardVaultFactory.sol";

/// @title BeraChef
/// @author Berachain Team
/// @notice The BeraChef contract is responsible for managing the reward allocations and the whitelisted vaults.
/// Reward allocation is a list of weights that determine the percentage of rewards that goes to each reward vault.
/// Each validator could have a custom reward allocation, if not, the default reward allocation is used.
/// @dev It should be owned by the governance module.
contract BeraChef_V1 is IBeraChef_V1, OwnableUpgradeable, UUPSUpgradeable {
    using Utils for bytes4;

    /// @dev Represents 100%. Chosen to be less granular.
    uint96 internal constant ONE_HUNDRED_PERCENT = 1e4;

    /// @dev Represents default commission rate, set to 5%.
    uint96 internal constant DEFAULT_COMMISSION_RATE = 0.05e4;

    /// @dev The maximum delay in block for a validator to change its commission rate.
    /// @dev taken as sum of max boost delay and max drop boost delay from BGT.sol
    uint64 internal constant MAX_COMMISSION_CHANGE_DELAY = 2 * 8191;

    /// @dev With 2 second block time, this is ~30 days.
    uint64 public constant MAX_REWARD_ALLOCATION_BLOCK_DELAY = 1_315_000;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The address of the distributor contract.
    address public distributor;
    /// @notice The address of the reward vault factory contract.
    address public factory;

    IBeaconDeposit public beaconDepositContract;

    /// @notice The delay in blocks before a new reward allocation can go into effect.
    uint64 public rewardAllocationBlockDelay;

    /// @dev The maximum number of weights per reward allocation.
    uint8 public maxNumWeightsPerRewardAllocation;

    /// @dev Mapping of validator public key to active reward allocation.
    mapping(bytes valPubkey => RewardAllocation) internal activeRewardAllocations;

    /// @dev Mapping of validator public key address to queued reward allocation.
    mapping(bytes valPubkey => RewardAllocation) internal queuedRewardAllocations;

    /// @notice Mapping of receiver address to whether they are white-listed or not.
    mapping(address receiver => bool) public isWhitelistedVault;

    /// @notice The Default reward allocation is used when a validator does not have a reward allocation.
    RewardAllocation internal defaultRewardAllocation;

    /// @notice The delay in blocks before a new commission rate can go into effect.
    uint64 public commissionChangeDelay;

    /// @notice Mapping of validator pubkey to its queued commission struct.
    mapping(bytes valPubkey => QueuedCommissionRateChange) internal valQueuedCommission;

    /// @notice Mapping of validator pubkey to its commission rate on incentive tokens
    mapping(bytes valPubkey => CommissionRate) internal valCommission;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _distributor,
        address _factory,
        address _governance,
        address _beaconDepositContract,
        uint8 _maxNumWeightsPerRewardAllocation
    )
        external
        initializer
    {
        __Ownable_init(_governance);
        __UUPSUpgradeable_init();
        // slither-disable-next-line missing-zero-check
        distributor = _distributor;
        // slither-disable-next-line missing-zero-check
        factory = _factory;
        // slither-disable-next-line missing-zero-check
        beaconDepositContract = IBeaconDeposit(_beaconDepositContract);
        if (_maxNumWeightsPerRewardAllocation == 0) {
            MaxNumWeightsPerRewardAllocationIsZero.selector.revertWith();
        }
        emit MaxNumWeightsPerRewardAllocationSet(_maxNumWeightsPerRewardAllocation);
        maxNumWeightsPerRewardAllocation = _maxNumWeightsPerRewardAllocation;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyDistributor() {
        if (msg.sender != distributor) {
            NotDistributor.selector.revertWith();
        }
        _;
    }

    modifier onlyOperator(bytes calldata valPubkey) {
        if (msg.sender != beaconDepositContract.getOperator(valPubkey)) {
            NotOperator.selector.revertWith();
        }
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBeraChef_V1
    function setMaxNumWeightsPerRewardAllocation(uint8 _maxNumWeightsPerRewardAllocation) external onlyOwner {
        if (_maxNumWeightsPerRewardAllocation == 0) {
            MaxNumWeightsPerRewardAllocationIsZero.selector.revertWith();
        }

        // Check if change the max number of weights could invalidate the default reward allocation
        if (_maxNumWeightsPerRewardAllocation < defaultRewardAllocation.weights.length) {
            InvalidateDefaultRewardAllocation.selector.revertWith();
        }

        maxNumWeightsPerRewardAllocation = _maxNumWeightsPerRewardAllocation;
        emit MaxNumWeightsPerRewardAllocationSet(_maxNumWeightsPerRewardAllocation);
    }

    /// @inheritdoc IBeraChef_V1
    function setRewardAllocationBlockDelay(uint64 _rewardAllocationBlockDelay) external onlyOwner {
        if (_rewardAllocationBlockDelay > MAX_REWARD_ALLOCATION_BLOCK_DELAY) {
            RewardAllocationBlockDelayTooLarge.selector.revertWith();
        }
        rewardAllocationBlockDelay = _rewardAllocationBlockDelay;
        emit RewardAllocationBlockDelaySet(_rewardAllocationBlockDelay);
    }

    /// @inheritdoc IBeraChef_V1
    function setVaultWhitelistedStatus(
        address receiver,
        bool isWhitelisted,
        string memory metadata
    )
        external
        onlyOwner
    {
        // Check if the proposed receiver (vault) is registered in the factory
        address stakeToken = address(RewardVault(receiver).stakeToken());
        address factoryVault = IRewardVaultFactory(factory).getVault(stakeToken);
        if (receiver != factoryVault) {
            NotFactoryVault.selector.revertWith();
        }

        isWhitelistedVault[receiver] = isWhitelisted;
        if (!isWhitelisted) {
            // If the receiver is no longer whitelisted, check if the default reward allocation is still valid.
            if (!_checkIfStillValid(defaultRewardAllocation.weights)) {
                InvalidRewardAllocationWeights.selector.revertWith();
            }
        }
        emit VaultWhitelistedStatusUpdated(receiver, isWhitelisted, metadata);
    }

    /// @inheritdoc IBeraChef_V1
    function updateWhitelistedVaultMetadata(address vault, string memory metadata) external onlyOwner {
        if (!isWhitelistedVault[vault]) {
            NotWhitelistedVault.selector.revertWith();
        }
        emit WhitelistedVaultMetadataUpdated(vault, metadata);
    }

    /// @inheritdoc IBeraChef_V1
    function setDefaultRewardAllocation(RewardAllocation calldata ra) external onlyOwner {
        // validate if the weights are valid.
        _validateWeights(ra.weights);

        emit SetDefaultRewardAllocation(ra);
        defaultRewardAllocation = ra;
    }

    /// @inheritdoc IBeraChef_V1
    function setCommissionChangeDelay(uint64 _commissionChangeDelay) external onlyOwner {
        if (_commissionChangeDelay == 0 || _commissionChangeDelay > MAX_COMMISSION_CHANGE_DELAY) {
            InvalidCommissionChangeDelay.selector.revertWith();
        }
        commissionChangeDelay = _commissionChangeDelay;
        emit CommissionChangeDelaySet(_commissionChangeDelay);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          SETTERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBeraChef_V1
    function queueNewRewardAllocation(
        bytes calldata valPubkey,
        uint64 startBlock,
        Weight[] calldata weights
    )
        external
        onlyOperator(valPubkey)
    {
        // adds a delay before a new reward allocation can go into effect
        if (startBlock <= block.number + rewardAllocationBlockDelay) {
            InvalidStartBlock.selector.revertWith();
        }

        RewardAllocation storage qra = queuedRewardAllocations[valPubkey];

        // do not allow to queue a new reward allocation if there is already one queued
        if (qra.startBlock > 0) {
            RewardAllocationAlreadyQueued.selector.revertWith();
        }

        // validate if the weights are valid.
        _validateWeights(weights);

        // queue the new reward allocation
        qra.startBlock = startBlock;
        Weight[] storage storageWeights = qra.weights;
        for (uint256 i; i < weights.length;) {
            storageWeights.push(weights[i]);
            unchecked {
                ++i;
            }
        }
        emit QueueRewardAllocation(valPubkey, startBlock, weights);
    }

    /// @inheritdoc IBeraChef_V1
    function queueValCommission(bytes calldata valPubkey, uint96 commissionRate) external onlyOperator(valPubkey) {
        if (commissionRate > ONE_HUNDRED_PERCENT) {
            InvalidCommissionValue.selector.revertWith();
        }
        QueuedCommissionRateChange storage qcr = valQueuedCommission[valPubkey];
        if (qcr.blockNumberLast > 0) {
            CommissionChangeAlreadyQueued.selector.revertWith();
        }
        (qcr.blockNumberLast, qcr.commissionRate) = (uint32(block.number), commissionRate);
        emit QueuedValCommission(valPubkey, commissionRate);
    }

    /// @inheritdoc IBeraChef_V1
    function activateQueuedValCommission(bytes calldata valPubkey) external {
        QueuedCommissionRateChange storage qcr = valQueuedCommission[valPubkey];
        (uint32 blockNumberLast, uint96 commissionRate) = (qcr.blockNumberLast, qcr.commissionRate);
        uint32 activationBlock = uint32(blockNumberLast + commissionChangeDelay);
        if (blockNumberLast == 0 || block.number < activationBlock) {
            CommissionNotQueuedOrDelayNotPassed.selector.revertWith();
        }
        uint96 oldCommission = _getOperatorCommission(valPubkey);
        valCommission[valPubkey] = CommissionRate({ activationBlock: activationBlock, commissionRate: commissionRate });
        emit ValCommissionSet(valPubkey, oldCommission, commissionRate);
        // delete the queued commission
        delete valQueuedCommission[valPubkey];
    }

    /// @inheritdoc IBeraChef_V1
    function activateReadyQueuedRewardAllocation(bytes calldata valPubkey) external onlyDistributor {
        if (!isQueuedRewardAllocationReady(valPubkey, block.number)) return;
        RewardAllocation storage qra = queuedRewardAllocations[valPubkey];
        uint64 startBlock = qra.startBlock;
        activeRewardAllocations[valPubkey] = qra;
        emit ActivateRewardAllocation(valPubkey, startBlock, qra.weights);
        // delete the queued reward allocation
        delete queuedRewardAllocations[valPubkey];
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          GETTERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBeraChef_V1
    /// @dev Returns the active reward allocation if validator has a reward allocation and the weights are still valid,
    /// otherwise the default reward allocation.
    function getActiveRewardAllocation(bytes calldata valPubkey) external view returns (RewardAllocation memory) {
        RewardAllocation memory ara = activeRewardAllocations[valPubkey];

        // check if the weights are still valid.
        if (ara.startBlock > 0 && _checkIfStillValid(ara.weights)) {
            return ara;
        }

        // If we reach here, either the weights are not valid or validator does not have any reward allocation, return
        // the default reward allocation.
        // @dev The validator or its operator need to update their reward allocation to a valid one for them to direct
        // the block rewards.
        return defaultRewardAllocation;
    }

    /// @inheritdoc IBeraChef_V1
    function getQueuedRewardAllocation(bytes calldata valPubkey) external view returns (RewardAllocation memory) {
        return queuedRewardAllocations[valPubkey];
    }

    /// @inheritdoc IBeraChef_V1
    function getSetActiveRewardAllocation(bytes calldata valPubkey) external view returns (RewardAllocation memory) {
        return activeRewardAllocations[valPubkey];
    }

    /// @inheritdoc IBeraChef_V1
    function getDefaultRewardAllocation() external view returns (RewardAllocation memory) {
        return defaultRewardAllocation;
    }

    /// @inheritdoc IBeraChef_V1
    function isQueuedRewardAllocationReady(bytes calldata valPubkey, uint256 blockNumber) public view returns (bool) {
        uint64 startBlock = queuedRewardAllocations[valPubkey].startBlock;
        return startBlock != 0 && startBlock <= blockNumber;
    }

    /// @inheritdoc IBeraChef_V1
    function isReady() external view returns (bool) {
        // return that the default reward allocation is set.
        return defaultRewardAllocation.weights.length > 0;
    }

    /// @inheritdoc IBeraChef_V1
    function getValCommissionOnIncentiveTokens(bytes calldata valPubkey) external view returns (uint96) {
        return _getOperatorCommission(valPubkey);
    }

    /// @inheritdoc IBeraChef_V1
    function getValQueuedCommissionOnIncentiveTokens(bytes calldata valPubkey)
        external
        view
        returns (QueuedCommissionRateChange memory)
    {
        return valQueuedCommission[valPubkey];
    }

    /// @inheritdoc IBeraChef_V1
    function getValidatorIncentiveTokenShare(
        bytes calldata valPubkey,
        uint256 incentiveTokenAmount
    )
        external
        view
        returns (uint256)
    {
        uint96 operatorCommission = _getOperatorCommission(valPubkey);
        uint256 operatorShare = (incentiveTokenAmount * operatorCommission) / ONE_HUNDRED_PERCENT;
        return operatorShare;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         INTERNAL                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Validates the weights of a reward allocation.
     * @param weights The weights of the reward allocation.
     */
    function _validateWeights(Weight[] calldata weights) internal view {
        if (weights.length > maxNumWeightsPerRewardAllocation) {
            TooManyWeights.selector.revertWith();
        }

        // ensure that the total weight is 100%.
        uint96 totalWeight;
        for (uint256 i; i < weights.length;) {
            Weight calldata weight = weights[i];

            if (weight.percentageNumerator == 0) {
                ZeroPercentageWeight.selector.revertWith();
            }

            // ensure that all receivers are approved for every weight in the reward allocation.
            if (!isWhitelistedVault[weight.receiver]) {
                NotWhitelistedVault.selector.revertWith();
            }
            totalWeight += weight.percentageNumerator;
            unchecked {
                ++i;
            }
        }
        if (totalWeight != ONE_HUNDRED_PERCENT) {
            InvalidRewardAllocationWeights.selector.revertWith();
        }
    }

    /**
     * @notice Checks if the weights of a reward allocation are still valid.
     * @notice This method is used to check if the weights of a reward allocation are still valid in flight.
     * @param weights The weights of the reward allocation.
     * @return True if the weights are still valid, otherwise false.
     */
    function _checkIfStillValid(Weight[] memory weights) internal view returns (bool) {
        uint256 length = weights.length;

        // If the max number of weights was changed after that the reward allocation was set
        // and the length now exeeds the new max, the reward allocation becomes invalid.
        if (length > maxNumWeightsPerRewardAllocation) {
            return false;
        }

        for (uint256 i; i < length;) {
            // At the first occurrence of a receiver that is not whitelisted, return false.
            if (!isWhitelistedVault[weights[i].receiver]) {
                return false;
            }
            unchecked {
                ++i;
            }
        }

        // If all receivers are whitelisted vaults, return true.
        return true;
    }

    /**
     * @notice Gets the operator commission for a validator.
     * @dev If the operator commission was never set, default is 5%.
     * @param valPubkey The public key of the validator.
     * @return The operator commission for the validator.
     */
    function _getOperatorCommission(bytes calldata valPubkey) internal view returns (uint96) {
        CommissionRate memory operatorCommission = valCommission[valPubkey];
        // If the operator commission was never set, default is 5%.
        if (operatorCommission.activationBlock == 0) return DEFAULT_COMMISSION_RATE;
        return operatorCommission.commissionRate;
    }
}
