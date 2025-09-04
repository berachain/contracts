// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import { Utils } from "../../libraries/Utils.sol";
import { IBGTIncentiveDistributor } from "../interfaces/IBGTIncentiveDistributor.sol";

/// @title BGTIncentiveDistributor
/// @author Berachain Team
/// @notice A contract that distributes POL incentives to BGT boosters using a merkle-based distribution system.
/// When BGT holders boost a validator, they become eligible for a share of the incentives from reward vaults.
/// These incentives are transferred to this contract and distributed based on off-chain computed merkle roots.
/// https://github.com/dinero-protocol/hidden-hand-contracts/blob/master/contracts/RewardDistributor.sol
contract BGTIncentiveDistributor is
    IBGTIncentiveDistributor,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using Utils for bytes4;
    using SafeERC20 for IERC20;

    /// @notice maximum value of delay to claim the rewards after an update of rewards metadata.
    uint64 public constant MAX_REWARD_CLAIM_DELAY = 3 hours;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice delay after which rewards can be claimed after an update of rewards metadata.
    uint64 public rewardClaimDelay;
    /// @notice Maps each of the identifiers to its reward metadata.
    mapping(bytes32 => Reward) public rewards;

    /// @notice Tracks the amount of claimed reward for the specified identifier+account.
    mapping(bytes32 => mapping(address => uint256)) public claimed;

    /// @notice Tracks the amount of incentive tokens currently held by the contract for each validator.
    mapping(bytes => mapping(address => uint256)) public incentiveTokensPerValidator;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*
    @notice initialize the contract
    @param _governance address of the governance
    */
    function initialize(address _governance) external initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        if (_governance == address(0)) ZeroAddress.selector.revertWith();
        _grantRole(DEFAULT_ADMIN_ROLE, _governance);
        _setRewardClaimDelay(MAX_REWARD_CLAIM_DELAY);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    /// @inheritdoc IBGTIncentiveDistributor
    function setRewardClaimDelay(uint64 _delay) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setRewardClaimDelay(_delay);
    }

    /// @inheritdoc IBGTIncentiveDistributor
    function updateRewardsMetadata(Distribution[] calldata _distributions) external onlyRole(MANAGER_ROLE) {
        uint256 dLen = _distributions.length;

        if (dLen == 0) InvalidDistribution.selector.revertWith();

        uint256 activeAt = block.timestamp + rewardClaimDelay;

        for (uint256 i; i < dLen;) {
            // Update the metadata and start the timer until the rewards will be active/claimable
            Distribution calldata distribution = _distributions[i];
            Reward storage reward = rewards[distribution.identifier];
            reward.merkleRoot = distribution.merkleRoot;
            reward.proof = distribution.proof;
            reward.activeAt = activeAt;
            reward.pubkey = distribution.pubkey;

            // Should only be set once per identifier.
            if (reward.token == address(0)) {
                reward.token = distribution.token;
            } else if (reward.token != distribution.token) {
                InvalidToken.selector.revertWith();
            }

            emit RewardMetadataUpdated(
                distribution.identifier,
                distribution.pubkey,
                distribution.token,
                distribution.merkleRoot,
                distribution.proof,
                activeAt
            );

            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IBGTIncentiveDistributor
    function setPauseState(bool state) external onlyRole(PAUSER_ROLE) {
        if (state) {
            _pause();
        } else {
            _unpause();
        }
    }

    /// @inheritdoc IBGTIncentiveDistributor
    function receiveIncentive(bytes calldata pubkey, address token, uint256 _amount) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);
        incentiveTokensPerValidator[pubkey][token] += _amount;
        emit IncentiveReceived(pubkey, token, _amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       USER FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBGTIncentiveDistributor
    function claim(Claim[] calldata _claims) external nonReentrant whenNotPaused {
        uint256 cLen = _claims.length;

        if (cLen == 0) InvalidArray.selector.revertWith();

        for (uint256 i; i < cLen;) {
            _claim(_claims[i].identifier, _claims[i].account, _claims[i].amount, _claims[i].merkleProof);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Claim a reward
     * @param _identifier Merkle identifier
     * @param _account Eligible user account
     * @param _amount Reward amount
     * @param _merkleProof Merkle proof
     */
    function _claim(bytes32 _identifier, address _account, uint256 _amount, bytes32[] calldata _merkleProof) private {
        Reward memory reward = rewards[_identifier];

        if (reward.merkleRoot == 0) InvalidMerkleRoot.selector.revertWith();
        if (reward.activeAt > block.timestamp) RewardInactive.selector.revertWith();

        uint256 lifeTimeAmount = claimed[_identifier][_account] + _amount;

        // Verify the merkle proof
        if (
            !MerkleProof.verifyCalldata(
                _merkleProof, reward.merkleRoot, keccak256(abi.encodePacked(_account, lifeTimeAmount))
            )
        ) InvalidProof.selector.revertWith();

        // Update the claimed amount to the current total
        claimed[_identifier][_account] = lifeTimeAmount;

        address token = reward.token;
        bytes memory pubkey = reward.pubkey;

        // Revert if the amount is greater than the incentive tokens available for the validator
        if (incentiveTokensPerValidator[pubkey][token] < _amount) {
            InsufficientIncentiveTokens.selector.revertWith();
        }
        unchecked {
            // Subtract the amount from the incentive tokens available for the validator
            incentiveTokensPerValidator[pubkey][token] -= _amount;
        }
        // Transfer the incentive tokens to the account
        IERC20(token).safeTransfer(_account, _amount);

        emit RewardClaimed(_identifier, token, _account, pubkey, _amount);
    }

    /**
     * @notice Set the reward claim delay
     * @dev Reverts if the delay is greater than the maximum allowed delay
     * @param _delay The delay in seconds
     */
    function _setRewardClaimDelay(uint64 _delay) internal {
        if (_delay > MAX_REWARD_CLAIM_DELAY) {
            InvalidRewardClaimDelay.selector.revertWith();
        }
        rewardClaimDelay = _delay;
        emit RewardClaimDelaySet(_delay);
    }
}
