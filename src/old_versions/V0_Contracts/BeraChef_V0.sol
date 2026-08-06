// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { Utils } from "src/libraries/Utils.sol";
import { IBeaconDeposit } from "src/pol/interfaces/IBeaconDeposit.sol";
import { IBeraChef_V0 } from "./interfaces/IBeraChef_V0.sol";
import { RewardVault_V0 } from "./RewardVault_V0.sol";
import { IRewardVaultFactory_V0 } from "./interfaces/IRewardVaultFactory_V0.sol";

/// @title BeraChef_V0
/// @author Berachain Team
/// @notice The BeraChef contract is responsible for managing the reward allocations and the whitelisted vaults.
/// Reward allocation is a list of weights that determine the percentage of rewards that goes to each reward vault.
/// Each validator could have a custom reward allocation, if not, the default reward allocation is used.
/// @dev It should be owned by the governance module.
contract BeraChef_V0 is IBeraChef_V0, OwnableUpgradeable, UUPSUpgradeable {
    using Utils for bytes4;

    /// @dev Represents 100%. Chosen to be less granular.
    uint96 internal constant ONE_HUNDRED_PERCENT = 1e4;
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

    /// @inheritdoc IBeraChef_V0
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

    /// @inheritdoc IBeraChef_V0
    function setRewardAllocationBlockDelay(uint64 _rewardAllocationBlockDelay) external onlyOwner {
        if (_rewardAllocationBlockDelay > MAX_REWARD_ALLOCATION_BLOCK_DELAY) {
            RewardAllocationBlockDelayTooLarge.selector.revertWith();
        }
        rewardAllocationBlockDelay = _rewardAllocationBlockDelay;
        emit RewardAllocationBlockDelaySet(_rewardAllocationBlockDelay);
    }

    /// @inheritdoc IBeraChef_V0
    function setVaultWhitelistedStatus(
        address receiver,
        bool isWhitelisted,
        string memory metadata
    )
        external
        onlyOwner
    {
        // Check if the proposed receiver (vault) is registered in the factory
        address stakeToken = address(RewardVault_V0(receiver).stakeToken());
        address factoryVault = IRewardVaultFactory_V0(factory).getVault(stakeToken);
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

    /// @inheritdoc IBeraChef_V0
    function updateWhitelistedVaultMetadata(address vault, string memory metadata) external onlyOwner {
        if (!isWhitelistedVault[vault]) {
            NotWhitelistedVault.selector.revertWith();
        }
        emit WhitelistedVaultMetadataUpdated(vault, metadata);
    }

    /// @inheritdoc IBeraChef_V0
    function setDefaultRewardAllocation(RewardAllocation calldata ra) external onlyOwner {
        // validate if the weights are valid.
        _validateWeights(ra.weights);

        emit SetDefaultRewardAllocation(ra);
        defaultRewardAllocation = ra;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          SETTERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBeraChef_V0
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

    /// @inheritdoc IBeraChef_V0
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

    /// @inheritdoc IBeraChef_V0
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

    /// @inheritdoc IBeraChef_V0
    function getQueuedRewardAllocation(bytes calldata valPubkey) external view returns (RewardAllocation memory) {
        return queuedRewardAllocations[valPubkey];
    }

    /// @inheritdoc IBeraChef_V0
    function getSetActiveRewardAllocation(bytes calldata valPubkey) external view returns (RewardAllocation memory) {
        return activeRewardAllocations[valPubkey];
    }

    /// @inheritdoc IBeraChef_V0
    function getDefaultRewardAllocation() external view returns (RewardAllocation memory) {
        return defaultRewardAllocation;
    }

    /// @inheritdoc IBeraChef_V0
    function isQueuedRewardAllocationReady(bytes calldata valPubkey, uint256 blockNumber) public view returns (bool) {
        uint64 startBlock = queuedRewardAllocations[valPubkey].startBlock;
        return startBlock != 0 && startBlock <= blockNumber;
    }

    /// @inheritdoc IBeraChef_V0
    function isReady() external view returns (bool) {
        // return that the default reward allocation is set.
        return defaultRewardAllocation.weights.length > 0;
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
}
