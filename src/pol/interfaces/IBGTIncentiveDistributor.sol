// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IPOLErrors } from "./IPOLErrors.sol";

interface IBGTIncentiveDistributor is IPOLErrors {
    /**
     * @param identifier Identifier of the distribution
     * @param token The address of the token to distribute
     * @param pubkey The pubkey of the validator
     * @param merkleRoot The merkle root of the distribution
     * @param proof The proof of the distribution
     */
    struct Distribution {
        bytes32 identifier;
        bytes pubkey;
        address token;
        bytes32 merkleRoot;
        bytes32 proof;
    }

    /**
     * @param token Address of the token to distribute
     * @param merkleRoot Merkle root of the distribution
     * @param proof The proof of the distribution
     * @param activeAt Timestamp at which the reward claim becomes active
     * @param pubkey The pubkey of the validator
     */
    struct Reward {
        address token;
        bytes32 merkleRoot;
        bytes32 proof;
        uint256 activeAt;
        bytes pubkey;
    }

    /**
     * @param identifier Identifier of the distribution
     * @param account The address of the account to claim the reward
     * @param amount The amount of tokens to claim
     * @param merkleProof The merkle proof of the distribution
     */
    struct Claim {
        bytes32 identifier;
        address account;
        uint256 amount;
        bytes32[] merkleProof;
    }

    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /*                          EVENTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Event emitted when the reward claim delay is set
     * @param delay The delay in seconds
     */
    event RewardClaimDelaySet(uint64 delay);

    /**
     * @notice Event emitted when a reward is claimed
     * @param identifier The identifier of the reward
     * @param token The address of the reward token
     * @param account The address of the account that claimed the reward
     * @param pubkey The pubkey of the validator corresponding to `identifier`
     * @param amount The amount of tokens claimed
     */
    event RewardClaimed(
        bytes32 indexed identifier, address indexed token, address indexed account, bytes pubkey, uint256 amount
    );

    /**
     * @notice Event emitted when a reward metadata is updated
     * @param identifier The identifier of the reward
     * @param token The address of the reward token
     * @param merkleRoot The merkle root of the reward
     * @param proof The proof of the reward
     * @param activeAt The timestamp at which the reward claim becomes active
     */
    event RewardMetadataUpdated(
        bytes32 indexed identifier,
        bytes indexed pubkey,
        address indexed token,
        bytes32 merkleRoot,
        bytes32 proof,
        uint256 activeAt
    );

    /**
     * @notice Event emitted when an incentive is received by the contract
     * @param pubkey The pubkey of the validator
     * @param token The address of the incentive token
     * @param amount The amount of tokens received
     */
    event IncentiveReceived(bytes indexed pubkey, address indexed token, uint256 amount);

    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /*                          FUNCTIONS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Get the amount of incentive tokens held by the contract for a validator
     * @param pubkey The pubkey of the validator
     * @param token The address of the incentive token
     * @return The amount of tokens held by the contract for the validator
     */
    function incentiveTokensPerValidator(bytes calldata pubkey, address token) external view returns (uint256);

    /**
     * @notice Set the reward claim delay
     * @dev Only address with DEFAULT_ADMIN_ROLE can call this function
     * @param _delay The delay in seconds
     */
    function setRewardClaimDelay(uint64 _delay) external;

    /**
     * @notice Receive incentive tokens from POL reward vaults
     * @dev Token approval must be given by the caller to this function before calling it.
     * @param pubkey The pubkey of the validator
     * @param token The address of the incentive token
     * @param _amount The amount of tokens received
     */
    function receiveIncentive(bytes calldata pubkey, address token, uint256 _amount) external;

    /**
     * @notice Claim rewards based on the specified metadata
     * @param _claims Claim[] List of claim metadata
     */
    function claim(Claim[] calldata _claims) external;

    /**
     * @notice Set the contract's pause state.
     * @dev Only address with PAUSER_ROLE can call this function
     * @param state Pause state
     */
    function setPauseState(bool state) external;

    /**
     * @notice Update the rewards metadata
     * @dev Only address with MANAGER_ROLE can call this function
     * @dev During the updated of a distribution, reverts if the token address is not the same as the one set for the
     * given identifier to avoid accidental wrong updates.
     * @param _distributions Distribution[] List of reward metadata
     */
    function updateRewardsMetadata(Distribution[] calldata _distributions) external;
}
