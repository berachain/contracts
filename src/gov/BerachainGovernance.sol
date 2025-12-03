// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.26;

import { GovernorUpgradeable } from "@openzeppelin-gov/GovernorUpgradeable.sol";
import { TimelockControllerUpgradeable } from "@openzeppelin-gov/TimelockControllerUpgradeable.sol";
import { GovernorSettingsUpgradeable } from "@openzeppelin-gov-ext/GovernorSettingsUpgradeable.sol";
import { GovernorCountingSimpleUpgradeable } from "@openzeppelin-gov-ext/GovernorCountingSimpleUpgradeable.sol";
import { GovernorStorageUpgradeable } from "@openzeppelin-gov-ext/GovernorStorageUpgradeable.sol";
import { GovernorVotesUpgradeable } from "@openzeppelin-gov-ext/GovernorVotesUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    GovernorVotesQuorumFractionUpgradeable
} from "@openzeppelin-gov-ext/GovernorVotesQuorumFractionUpgradeable.sol";
import { GovernorTimelockControlUpgradeable } from "@openzeppelin-gov-ext/GovernorTimelockControlUpgradeable.sol";
import { IVotes } from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import { Utils } from "../libraries/Utils.sol";

struct InitialGovernorParameters {
    uint256 proposalThreshold;
    uint256 quorumNumeratorValue;
    uint48 votingDelay;
    uint32 votingPeriod;
}

/// @title BerachainGovernance
/// @author Berachain Team
/// @notice The Berachain Governance contract extends OpenZeppelin's governor contracts. It uses the $BGT token as its
/// governance token, which determines voting power in the governance system. Users must hold $BGT tokens to
/// participate
/// in governance activities such as creating proposals and voting.
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
    /*                       CUSTOM CHANGES                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _authorizeUpgrade(address newImplementation) internal override onlyGovernance { }

    /**
     * @notice We have a requirement of 51% threshold for proposal approval
     * @dev forVotes / (forVotes + againstVotes) >= 51%
     */
    function _voteSucceeded(uint256 proposalId)
        internal
        view
        virtual
        override(GovernorUpgradeable, GovernorCountingSimpleUpgradeable)
        returns (bool)
    {
        (uint256 againstVotes, uint256 forVotes,) = proposalVotes(proposalId);
        uint256 threshold = (forVotes + againstVotes) * 51 / 100;

        return forVotes >= threshold;
    }

    /**
     * @dev Helper method in place of GovernorTimelockControlUpgradeable private methods
     */
    function getTimelockOperationId(uint256 proposalId) external view returns (bytes32 operationId) {
        TimelockControllerUpgradeable timelock = TimelockControllerUpgradeable(payable(_executor()));

        // Compute timelock operation ID:
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) =
            proposalDetails(proposalId);
        bytes32 salt = bytes20(address(this)) ^ descriptionHash;
        operationId = timelock.hashOperationBatch(targets, values, calldatas, 0, salt);
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

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     REQUIRED OVERRIDES                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc GovernorTimelockControlUpgradeable
    function state(uint256 proposalId)
        public
        view
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (ProposalState)
    {
        return GovernorTimelockControlUpgradeable.state(proposalId);
    }

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
        return
            GovernorTimelockControlUpgradeable._queueOperations(
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
