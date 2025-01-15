// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import { GovernorUpgradeable } from "@openzeppelin-gov/GovernorUpgradeable.sol";
import { TimelockControllerUpgradeable } from "@openzeppelin-gov/TimelockControllerUpgradeable.sol";
import { GovernorSettingsUpgradeable } from "@openzeppelin-gov-ext/GovernorSettingsUpgradeable.sol";
import { GovernorCountingSimpleUpgradeable } from "@openzeppelin-gov-ext/GovernorCountingSimpleUpgradeable.sol";
import { GovernorStorageUpgradeable } from "@openzeppelin-gov-ext/GovernorStorageUpgradeable.sol";
import { GovernorVotesUpgradeable } from "@openzeppelin-gov-ext/GovernorVotesUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { GovernorVotesQuorumFractionUpgradeable } from
    "@openzeppelin-gov-ext/GovernorVotesQuorumFractionUpgradeable.sol";
import { GovernorTimelockControlUpgradeable } from "@openzeppelin-gov-ext/GovernorTimelockControlUpgradeable.sol";
import { IVotes } from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import { Utils } from "../libraries/Utils.sol";

struct InitialGovernorParameters {
    uint256 proposalThreshold;
    uint256 quorumNumeratorValue;
    uint48 votingDelay;
    uint32 votingPeriod;
}

/// @custom:security-contact security@berachain.com
contract BerachainGovernance is
    UUPSUpgradeable,
    GovernorUpgradeable,
    GovernorSettingsUpgradeable,
    GovernorCountingSimpleUpgradeable,
    GovernorStorageUpgradeable,
    GovernorVotesUpgradeable,
    GovernorVotesQuorumFractionUpgradeable,
    GovernorTimelockControlUpgradeable
{
    using Utils for bytes4;

    /**
     * @dev The voter has zero delegated voting power.
     */
    error GovernorZeroVoteWeight();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        IVotes _token,
        TimelockControllerUpgradeable _timelock,
        InitialGovernorParameters memory params
    )
        public
        initializer
    {
        /// Upgradeability mechanism for UUPS proxy.
        __UUPSUpgradeable_init();
        /// Governor name.
        __Governor_init("BerachainGovernance");
        /// Voting delay, voting period and proposal threshold.
        __GovernorSettings_init(params.votingDelay, params.votingPeriod, params.proposalThreshold);
        /// Simple counting.
        __GovernorCountingSimple_init();
        /// Upgradeable storage.
        __GovernorStorage_init();
        /// Token used for voting.
        __GovernorVotes_init(_token);
        /// Quorum.
        __GovernorVotesQuorumFraction_init(params.quorumNumeratorValue);
        /// Timelock controller.
        __GovernorTimelockControl_init(_timelock);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance { }

    /// @inheritdoc GovernorTimelockControlUpgradeable
    function state(uint256 proposalId)
        public
        view
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (ProposalState)
    {
        ProposalState currentState = GovernorTimelockControlUpgradeable.state(proposalId);

        // Accelerate the proposal if it has reached the quorum; regardless of the deadline.
        if (currentState == ProposalState.Active && _quorumReached(proposalId) && _voteSucceeded(proposalId)) {
            // NOTE: once allecerated, the state must be fixed to keep it consistent
            if (proposalEta(proposalId) == 0) {
                // The proposal has not been queued yet
                return ProposalState.Succeeded;
            } else if (_isProposalPendingOnTimelock(proposalId)) {
                return ProposalState.Queued;
            } else {
                // The proposal has been cancelled by the guardianship
                return ProposalState.Canceled;
            }
        }

        return currentState;
    }

    /**
     * @dev Helper method in place of GovernorTimelockControlUpgradeable private methods
     */
    function _isProposalPendingOnTimelock(uint256 proposalId) private view returns (bool) {
        TimelockControllerUpgradeable timelock = TimelockControllerUpgradeable(payable(_executor()));

        // Compute timelock operation ID:
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) =
            proposalDetails(proposalId);
        bytes32 salt = bytes20(address(this)) ^ descriptionHash;
        bytes32 operationId = timelock.hashOperationBatch(targets, values, calldatas, 0, salt);

        return timelock.isOperationPending(operationId);
    }

    function _countVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 totalWeight,
        bytes memory params
    )
        internal
        override(GovernorUpgradeable, GovernorCountingSimpleUpgradeable)
        returns (uint256)
    {
        // Avoid off-chain issues.
        if (totalWeight == 0) {
            GovernorZeroVoteWeight.selector.revertWith();
        }

        return GovernorCountingSimpleUpgradeable._countVote(proposalId, account, support, totalWeight, params);
    }

    // The following functions are overrides required by Solidity.

    /// @inheritdoc GovernorTimelockControlUpgradeable
    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (bool)
    {
        return GovernorTimelockControlUpgradeable.proposalNeedsQueuing(proposalId);
    }

    /// @inheritdoc GovernorSettingsUpgradeable
    function proposalThreshold()
        public
        view
        override(GovernorUpgradeable, GovernorSettingsUpgradeable)
        returns (uint256)
    {
        return GovernorSettingsUpgradeable.proposalThreshold();
    }

    function _propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        address proposer
    )
        internal
        override(GovernorUpgradeable, GovernorStorageUpgradeable)
        returns (uint256)
    {
        return GovernorStorageUpgradeable._propose(targets, values, calldatas, description, proposer);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    )
        internal
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (uint48)
    {
        return GovernorTimelockControlUpgradeable._queueOperations(
            proposalId, targets, values, calldatas, descriptionHash
        );
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    )
        internal
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
    {
        GovernorTimelockControlUpgradeable._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    )
        internal
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (uint256)
    {
        return GovernorTimelockControlUpgradeable._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor()
        internal
        view
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (address)
    {
        return GovernorTimelockControlUpgradeable._executor();
    }
}
