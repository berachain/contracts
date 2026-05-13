// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { Multicallable } from "solady/src/utils/Multicallable.sol";

import { Utils } from "../../libraries/Utils.sol";
import { IBeraChef } from "../interfaces/IBeraChef.sol";
import { IBlockRewardController } from "../interfaces/IBlockRewardController.sol";
import { IDistributor } from "../interfaces/IDistributor.sol";
import { IRewardVault } from "../interfaces/IRewardVault.sol";
import { BeaconRootsHelper } from "../BeaconRootsHelper.sol";
import { IDedicatedEmissionStreamManager } from "../interfaces/IDedicatedEmissionStreamManager.sol";
import { IRewardAllocation } from "../interfaces/IRewardAllocation.sol";

/// @title Distributor
/// @author Berachain Team
/// @notice The Distributor contract is responsible for distributing the block rewards from the reward controller
/// and the reward allocation weights, to the reward allocation receivers.
/// @dev Each validator has its own reward allocation, if it does not exist, a default reward allocation is used.
/// And if governance has not set the default reward allocation, the rewards are not minted and distributed.
contract Distributor is
    IDistributor,
    BeaconRootsHelper,
    ReentrancyGuardUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    Multicallable
{
    using Utils for bytes4;
    using Utils for address;

    /// @notice The MANAGER role.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @dev Represents 100%. Chosen to be less granular.
    uint96 internal constant ONE_HUNDRED_PERCENT = 1e4;

    /// @dev Address controlled by the execution layer client and used to call `distributeFor` function.
    address private constant SYSTEM_ADDRESS = 0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE;

    /// @dev Pectra11 hard fork timestamp.
    /// @dev Bepolia: 1_754_496_000, 2025-08-06T16:00:00.000Z
    /// @dev Mainnet: 1_756_915_200, 2025-09-03T16:00:00.000Z
    uint64 private constant PECTRA11_HARD_FORK_TIMESTAMP = 1_756_915_200;

    /// @notice The WBERA token address.
    address private constant WBERA_ADDRESS = 0x6969696969696969696969696969696969696969;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The BeraChef contract that we are getting the reward allocation from.
    IBeraChef public beraChef;

    /// @notice The rewards controller contract that we are getting the rewards rate from.
    /// @dev Contract is responsible for minting the emission token.
    IBlockRewardController public blockRewardController;

    /// @notice The emission token contract that we are distributing to the reward allocation receivers.
    address public emissionToken;

    /// @notice The dedicated emission stream manager contract.
    IDedicatedEmissionStreamManager public dedicatedEmissionStreamManager;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _berachef,
        address _emissionToken,
        address _blockRewardController,
        address _governance,
        uint64 _zeroValidatorPubkeyGIndex,
        uint64 _proposerIndexGIndex
    )
        external
        initializer
    {
        __AccessControl_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _governance);
        beraChef = IBeraChef(_berachef);
        emissionToken = _emissionToken;
        blockRewardController = IBlockRewardController(_blockRewardController);
        super.setZeroValidatorPubkeyGIndex(_zeroValidatorPubkeyGIndex);
        super.setProposerIndexGIndex(_proposerIndexGIndex);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    /// @dev This is necessary to call when the beacon chain hard forks (and specifically the underlying structure of
    /// beacon block header is modified).
    function setZeroValidatorPubkeyGIndex(uint64 _zeroValidatorPubkeyGIndex) public override onlyRole(MANAGER_ROLE) {
        super.setZeroValidatorPubkeyGIndex(_zeroValidatorPubkeyGIndex);
    }

    /// @dev This is necessary to call when the beacon chain hard forks (and specifically the underlying structure of
    /// beacon block header is modified).
    function setProposerIndexGIndex(uint64 _proposerIndexGIndex) public override onlyRole(MANAGER_ROLE) {
        super.setProposerIndexGIndex(_proposerIndexGIndex);
    }

    /// @inheritdoc IDistributor
    function setDedicatedEmissionStreamManager(address _dedicatedEmissionStreamManager)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (_dedicatedEmissionStreamManager == address(0)) {
            ZeroAddress.selector.revertWith();
        }
        emit DedicatedEmissionStreamManagerSet(
            address(dedicatedEmissionStreamManager), _dedicatedEmissionStreamManager
        );
        dedicatedEmissionStreamManager = IDedicatedEmissionStreamManager(_dedicatedEmissionStreamManager);
    }

    /// @inheritdoc IDistributor
    function setEmissionToken() external onlyRole(DEFAULT_ADMIN_ROLE) {
        emissionToken = WBERA_ADDRESS;
        emit EmissionTokenSet(emissionToken);
    }

    /// @inheritdoc IDistributor
    function distributeFor(
        uint64 nextTimestamp,
        uint64 proposerIndex,
        bytes calldata pubkey,
        bytes32[] calldata proposerIndexProof,
        bytes32[] calldata pubkeyProof
    )
        external
        nonReentrant
    {
        // only allow permissionless distribution using proofs till hard fork timestamp
        if (nextTimestamp >= PECTRA11_HARD_FORK_TIMESTAMP) {
            OnlySystemCallAllowed.selector.revertWith();
        }
        // Process the timestamp in the history buffer, reverting if already processed.
        bytes32 beaconBlockRoot = _processTimestampInBuffer(nextTimestamp);

        // Verify the given proposer index is the true proposer index of the beacon block.
        _verifyProposerIndexInBeaconBlock(beaconBlockRoot, proposerIndexProof, proposerIndex);

        // Verify the given pubkey is of a validator in the beacon block, at the given validator index.
        _verifyValidatorPubkeyInBeaconBlock(beaconBlockRoot, pubkeyProof, pubkey, proposerIndex);

        // Distribute the rewards to the proposer validator.
        _distributeFor(pubkey, nextTimestamp);
    }

    /// @inheritdoc IDistributor
    function distributeFor(bytes calldata pubkey) external onlySystemCall {
        _distributeFor(pubkey, uint64(block.timestamp));
    }

    /// @dev Distributes the rewards for the given validator for the given timestamp's parent block.
    function _distributeFor(bytes calldata pubkey, uint64 nextTimestamp) internal {
        // Process the rewards with the block rewards controller for the specified block number.
        // Its dependent on the beraChef being ready, if not it will return zero rewards for the current block.
        uint256 rewardRate = blockRewardController.processRewards(pubkey, nextTimestamp, beraChef.isReady());

        if (rewardRate != 0) {
            if (address(dedicatedEmissionStreamManager) != address(0)) {
                uint256 emissionPerc = dedicatedEmissionStreamManager.emissionPerc();
                IRewardAllocation.Weight[] memory rewardAllocation =
                    dedicatedEmissionStreamManager.getRewardAllocation();

                if (emissionPerc > 0 && rewardAllocation.length > 0) {
                    uint256 graAmount = FixedPointMathLib.fullMulDiv(rewardRate, emissionPerc, ONE_HUNDRED_PERCENT);
                    uint256 excessEmission =
                        _distributeRewards(graAmount, rewardAllocation, pubkey, nextTimestamp, true);

                    // Decrease the reward rate by the reward allocation amount.
                    rewardRate -= graAmount - excessEmission;
                }
            }

            // Activate the queued reward allocation if it is ready.
            beraChef.activateReadyQueuedRewardAllocation(pubkey);

            // Get the active reward allocation for the validator.
            // This will return the default reward allocation if the validator does not have an active reward
            // allocation.
            IRewardAllocation.RewardAllocation memory ra = beraChef.getActiveRewardAllocation(pubkey);
            _distributeRewards(rewardRate, ra.weights, pubkey, nextTimestamp, false);
        }

        blockRewardController.burnExceedingBalance();
    }

    /// @dev Accumulates any excess emission that cannot be distributed to a vault in the global reward allocation,
    /// due to the requested emission amount exceeding the vault's target emission (as governed by the dedicated
    /// emission stream manager logic). This excess is considered "distributed" for the purpose of accounting within
    /// the reward allocation, but is actually reallocated to the validator's (default) reward allocation.
    function _distributeRewards(
        uint256 amount,
        IRewardAllocation.Weight[] memory weights,
        bytes calldata pubkey,
        uint64 nextTimestamp,
        bool isDedicatedEmission
    )
        internal
        returns (uint256 excessEmission)
    {
        if (amount == 0) {
            return 0;
        }

        uint256 totalRewardDistributed;
        uint256 length = weights.length;

        for (uint256 i; i < length;) {
            IRewardAllocation.Weight memory weight = weights[i];
            address receiver = weight.receiver;

            uint256 rewardAmount;
            // Compute base reward amount for this vault.
            if (i == length - 1) {
                // For the last vault, distribute the remaining rewards, excluding any excess emission.
                rewardAmount = amount - totalRewardDistributed - excessEmission;
            } else {
                rewardAmount = FixedPointMathLib.fullMulDiv(amount, weight.percentageNumerator, ONE_HUNDRED_PERCENT);
            }

            if (isDedicatedEmission) {
                uint256 maxEmission = dedicatedEmissionStreamManager.getMaxEmission(receiver, rewardAmount);
                excessEmission += rewardAmount - maxEmission;
                // Only distribute the maximum allowable emission to the vault.
                rewardAmount = maxEmission;
            }

            if (i != length - 1) {
                totalRewardDistributed += rewardAmount;
            }

            if (rewardAmount > 0) {
                // The reward vault will pull the rewards from this contract so we can keep the approvals for the
                // emission token.
                emissionToken.safeIncreaseAllowance(receiver, rewardAmount);

                // Notify the receiver of the reward.
                IRewardVault(receiver).notifyRewardAmount(pubkey, rewardAmount);

                if (isDedicatedEmission) {
                    dedicatedEmissionStreamManager.notifyEmission(receiver, rewardAmount);
                }

                emit Distributed(pubkey, nextTimestamp, receiver, rewardAmount);
            }

            unchecked {
                ++i;
            }
        }

        return excessEmission;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       MODIFIERS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Modifier to restrict function access to system address.
    /// @dev This ensures only the execution layer client can call `distributeFor` function.
    modifier onlySystemCall() {
        if (msg.sender != SYSTEM_ADDRESS) {
            NotSystemAddress.selector.revertWith();
        }
        _;
    }
}
