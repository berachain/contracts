// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { LibClone } from "solady/src/utils/LibClone.sol";
import { IGovernor } from "@openzeppelin/contracts/governance/IGovernor.sol";
import { IVotes } from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC1967 } from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { TimelockControllerUpgradeable } from "@openzeppelin-gov/TimelockControllerUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { GovernorCountingSimpleUpgradeable } from "@openzeppelin-gov-ext/GovernorCountingSimpleUpgradeable.sol";
import { IGovernor } from "@openzeppelin/contracts/governance/IGovernor.sol";

import { BGT } from "src/pol/BGT.sol";
import { BerachainGovernance, InitialGovernorParameters } from "src/gov/BerachainGovernance.sol";
import { IBlockRewardController } from "src/pol/interfaces/IBlockRewardController.sol";
import { MockBGT } from "test/mock/token/MockBGT.sol";
import { TimeLock } from "src/gov/TimeLock.sol";
import { GovernanceBaseTest } from "./GovernanceBase.t.sol";

contract BerachainGovernanceTest is GovernanceBaseTest {
    bytes[] internal _calldatas;
    address[] internal _targets;
    MockBGT internal mockBgt;

    address internal _guardian;

    uint256 internal constant MIN_DELAY_TIMELOCK = 2 days;
    uint256 internal constant PROPOSAL_THRESHOLD = 1e9;
    uint256 internal constant QUORUM_NUMERATOR_VALUE = 10; // 10% of the totalSupply
    uint48 internal constant VOTING_DELAY = uint48(5400); // 5400 blocks
    uint32 internal constant VOTING_PERIOD = uint32(5400); // 5400 blocks

    uint8 internal constant VOTE_IN_FAVOUR = uint8(GovernorCountingSimpleUpgradeable.VoteType.For);
    uint8 internal constant VOTE_AGAINST = uint8(GovernorCountingSimpleUpgradeable.VoteType.Against);

    function setUp() public virtual override {
        gov = BerachainGovernance(payable(LibClone.deployERC1967(address(new BerachainGovernance()))));
        timelock = TimeLock(payable(LibClone.deployERC1967(address(new TimeLock()))));

        address[] memory proposers = new address[](1);
        proposers[0] = address(gov);
        address[] memory executors = new address[](1);
        executors[0] = address(gov);
        timelock.initialize(MIN_DELAY_TIMELOCK, proposers, executors, address(this));

        _guardian = makeAddr("guardian");
        timelock.grantRole(timelock.CANCELLER_ROLE(), _guardian);

        deployPOL(address(timelock));
        InitialGovernorParameters memory params = InitialGovernorParameters({
            proposalThreshold: PROPOSAL_THRESHOLD,
            quorumNumeratorValue: QUORUM_NUMERATOR_VALUE,
            votingDelay: VOTING_DELAY,
            votingPeriod: VOTING_PERIOD
        });

        // Deploy MockBGT
        mockBgt = MockBGT(payable(LibClone.deployERC1967(address(new MockBGT()))));
        mockBgt.initialize(address(this));

        gov.initialize(IVotes(address(mockBgt)), TimelockControllerUpgradeable(timelock), params);

        // Targets and calldata are used to simulate the action on the PoL contracts.
        _targets = new address[](2);
        _targets[0] = address(bgt);
        _targets[1] = address(blockRewardController);

        _calldatas = new bytes[](2);
        _calldatas[0] = abi.encodeCall(BGT.whitelistSender, (address(this), true));
        _calldatas[1] = abi.encodeCall(IBlockRewardController.setDistributor, (makeAddr("newDistributor")));

        // Mint and delegate more than the proposal threshold amount of BGT to self in order to create and vote
        // proposal
        mockBgt.mint(address(this), 10e18);
        mockBgt.delegate(address(this));

        // Bring the chain two block forward in order to contabilize the voting power to the contract
        vm.roll(block.number + 2);
        vm.warp(block.timestamp + 1);
    }

    function test_ProposeFailsWithInvalidDescription() public {
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorRestrictedProposer.selector, address(this)));
        // only 0x1234567890abcdef1234567890abcdef12345678 this address can propose the proposal with this description.
        gov.propose(
            _targets, new uint256[](2), _calldatas, "Test Proposal#proposer=0x1234567890abcdef1234567890abcdef12345678"
        );
    }

    function test_ProposeFailsIfInsufficienVotes() public {
        address proposer = makeAddr("proposer");
        uint256 proposalThreshold = gov.proposalThreshold();
        assertLt(gov.getVotes(proposer, block.timestamp - 1), PROPOSAL_THRESHOLD);
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorInsufficientProposerVotes.selector, proposer, 0, proposalThreshold
            )
        );
        vm.prank(proposer);
        gov.propose(_targets, new uint256[](2), _calldatas, "Test Proposal");
    }

    function test_CreatePendingProposal() public {
        assertGt(gov.getVotes(address(this), block.timestamp - 1), PROPOSAL_THRESHOLD);

        uint256 proposalId = _createTestProposal(address(this), _targets, _calldatas, "Test Proposal");

        assertTrue(gov.state(proposalId) == IGovernor.ProposalState.Pending);
        vm.warp(gov.proposalSnapshot(proposalId) + 1);
        assertTrue(gov.state(proposalId) == IGovernor.ProposalState.Active);
    }

    function test_CreateSucceededProposal() public returns (uint256 proposalId) {
        proposalId = _createTestProposal(address(this), _targets, _calldatas, "Test Proposal");
        vm.warp(gov.proposalSnapshot(proposalId) + 1);

        gov.castVote(proposalId, VOTE_IN_FAVOUR);

        vm.warp(gov.proposalDeadline(proposalId) + 1);
        assertTrue(gov.state(proposalId) == IGovernor.ProposalState.Succeeded);
    }

    function test_CreateFailedProposal() public returns (uint256 proposalId) {
        proposalId = _createTestProposal(address(this), _targets, _calldatas, "Test Proposal");
        vm.warp(gov.proposalSnapshot(proposalId) + 1);

        gov.castVote(proposalId, VOTE_AGAINST);

        vm.warp(gov.proposalDeadline(proposalId) + 1);
        assertTrue(gov.state(proposalId) == IGovernor.ProposalState.Defeated);
    }

    function test_CancelProposalFailsIfProposalActive() public {
        uint256 proposalId = _createTestProposal(address(this), _targets, _calldatas, "Test Proposal");
        vm.warp(gov.proposalSnapshot(proposalId) + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorUnexpectedProposalState.selector,
                proposalId,
                IGovernor.ProposalState.Active,
                bytes32(1 << uint8(IGovernor.ProposalState.Pending))
            )
        );
        gov.cancel(proposalId);
    }

    function test_CancelProposalFailsIfCallerNotProposer() public {
        address canceller = makeAddr("canceller");
        uint256 proposalId = _createTestProposal(address(this), _targets, _calldatas, "Test Proposal");

        vm.prank(canceller);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyProposer.selector, canceller));
        gov.cancel(proposalId);
    }

    function test_CancelProposal() public {
        uint256 proposalId = _createTestProposal(address(this), _targets, _calldatas, "Test Proposal");
        vm.expectEmit();
        emit IGovernor.ProposalCanceled(proposalId);

        gov.cancel(proposalId);
        assertTrue(gov.state(proposalId) == IGovernor.ProposalState.Canceled);
    }

    function test_VoteCastingFailsIfMissingVotingPower() public {
        uint256 proposalId = _createTestProposal(address(this), _targets, _calldatas, "Test Proposal");
        vm.warp(gov.proposalSnapshot(proposalId) + 1);
        assertTrue(gov.state(proposalId) == IGovernor.ProposalState.Active);

        address voter = makeAddr("voter");
        assertEq(0, gov.getVotes(voter, gov.proposalSnapshot(proposalId)));

        vm.prank(voter);
        vm.expectRevert(BerachainGovernance.GovernorZeroVoteWeight.selector);
        gov.castVote(proposalId, 1);
    }

    function test_QueueProposalFailsIfProposalNonExistent() public {
        uint256 proposalId = gov.hashProposal(_targets, new uint256[](2), _calldatas, keccak256("Test Proposal"));
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorNonexistentProposal.selector, proposalId));
        gov.queue(_targets, new uint256[](2), _calldatas, keccak256("Test Proposal"));
    }

    function test_QueueProposalFailsIfProposalNotSuccess() public {
        uint256 proposalId = _createTestProposal(address(this), _targets, _calldatas, "Test Proposal");
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorUnexpectedProposalState.selector,
                proposalId,
                IGovernor.ProposalState.Pending,
                bytes32(1 << uint8(IGovernor.ProposalState.Succeeded))
            )
        );
        gov.queue(proposalId);
    }

    function test_QueueProposalFailsIfProposalCanceled() public {
        uint256 proposalId = _createTestProposal(address(this), _targets, _calldatas, "Test Proposal");
        gov.cancel(proposalId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorUnexpectedProposalState.selector,
                proposalId,
                IGovernor.ProposalState.Canceled,
                bytes32(1 << uint8(IGovernor.ProposalState.Succeeded))
            )
        );
        gov.queue(proposalId);
    }

    function test_QueueProposal() public {
        uint256 proposalId =
            _createSuccessedProposal(address(this), _targets, _calldatas, "Test Proposal", address(this));
        // verify if a proposal needs queuing
        assertEq(gov.proposalNeedsQueuing(proposalId), true);
        vm.expectEmit();
        emit IGovernor.ProposalQueued(proposalId, block.timestamp + MIN_DELAY_TIMELOCK);
        gov.queue(proposalId);
        assertTrue(gov.state(proposalId) == IGovernor.ProposalState.Queued);
        assertEq(gov.proposalEta(proposalId), block.timestamp + MIN_DELAY_TIMELOCK);
    }

    function test_ExecuteProposal_FailsIfProposalNonExistent() public {
        uint256 proposalId = gov.hashProposal(_targets, new uint256[](2), _calldatas, keccak256("Test Proposal"));
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorNonexistentProposal.selector, proposalId));
        gov.execute(_targets, new uint256[](2), _calldatas, keccak256("Test Proposal"));
    }

    function test_ExecuteProposal_FailsIfProposalNotQueued() public {
        uint256 proposalId = _createTestProposal(address(this), _targets, _calldatas, "Test Proposal");
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorUnexpectedProposalState.selector,
                proposalId,
                IGovernor.ProposalState.Pending,
                bytes32(1 << uint8(IGovernor.ProposalState.Succeeded))
                    | bytes32(1 << uint8(IGovernor.ProposalState.Queued))
            )
        );
        gov.execute(proposalId);
    }

    function test_ExecuteProposal_FailsIfSucceededButNotQueued() public {
        uint256 proposalId =
            _createSuccessedProposal(address(this), _targets, _calldatas, "Test Proposal", address(this));
        bytes32 id = gov.getTimelockOperationId(proposalId);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockControllerUpgradeable.TimelockUnexpectedOperationState.selector,
                id,
                bytes32(1 << uint8(TimelockControllerUpgradeable.OperationState.Ready))
            )
        );
        gov.execute(proposalId);
    }

    function test_ExecuteProposal() public {
        uint256 proposalId = _createQueuedProposal(address(this), _targets, _calldatas, "Test Proposal", address(this));
        assertTrue(gov.state(proposalId) == IGovernor.ProposalState.Queued);

        vm.warp(block.timestamp + MIN_DELAY_TIMELOCK + 1);
        vm.expectEmit();
        emit IGovernor.ProposalExecuted(proposalId);
        gov.execute(proposalId);

        assertTrue(gov.state(proposalId) == IGovernor.ProposalState.Executed);
        assertEq(bgt.isWhitelistedSender(address(this)), true);
    }

    // Guardian tests

    function test_GuardianCancelProposalFailsIfAddressDoesNotHaveRole() public {
        address fakeGuardian = makeAddr("fakeGuardian");
        uint256 proposalId = _createQueuedProposal(address(this), _targets, _calldatas, "Test Proposal", address(this));
        bytes32 timelockProposalId = gov.getTimelockOperationId(proposalId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, fakeGuardian, timelock.CANCELLER_ROLE()
            )
        );
        vm.prank(fakeGuardian);
        timelock.cancel(timelockProposalId);
    }

    // ToDo: Guardian non può cancellare prima e dopo il periodo del timelock

    function test_GuardianCanCancelProposalWhenWaiting() public {
        address guardian = makeAddr("guardian");
        timelock.grantRole(timelock.CANCELLER_ROLE(), guardian);

        uint256 proposalId = _createQueuedProposal(address(this), _targets, _calldatas, "Test Proposal", address(this));
        bytes32 timelockProposalId = gov.getTimelockOperationId(proposalId);
        assertTrue(
            timelock.getOperationState(timelockProposalId) == TimelockControllerUpgradeable.OperationState.Waiting
        );

        vm.expectEmit();
        emit TimelockControllerUpgradeable.Cancelled(timelockProposalId);

        vm.prank(guardian);
        timelock.cancel(timelockProposalId);

        assertTrue(
            timelock.getOperationState(timelockProposalId) == TimelockControllerUpgradeable.OperationState.Unset
        );
    }

    function test_GuardianCanCancelProposalWhenReady() public {
        address guardian = makeAddr("guardian");
        timelock.grantRole(timelock.CANCELLER_ROLE(), guardian);

        uint256 proposalId = _createQueuedProposal(address(this), _targets, _calldatas, "Test Proposal", address(this));
        bytes32 timelockProposalId = gov.getTimelockOperationId(proposalId);

        vm.warp(block.timestamp + MIN_DELAY_TIMELOCK + 1);
        assertTrue(
            timelock.getOperationState(timelockProposalId) == TimelockControllerUpgradeable.OperationState.Ready
        );

        vm.expectEmit();
        emit TimelockControllerUpgradeable.Cancelled(timelockProposalId);

        vm.prank(guardian);
        timelock.cancel(timelockProposalId);

        assertTrue(
            timelock.getOperationState(timelockProposalId) == TimelockControllerUpgradeable.OperationState.Unset
        );
    }

    // tests to upgrade governance

    function test_UpgradeGovernance_FailsIfNotOwner() public {
        testFuzz_UpgradeGovernance_FailsIfNotOwner(address(this));
    }

    function testFuzz_UpgradeGovernance_FailsIfNotOwner(address caller) public {
        vm.assume(caller != address(timelock));
        address newGovImpl = address(new BerachainGovernance());
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, caller));
        gov.upgradeToAndCall(newGovImpl, "");
    }

    function test_UpgradeGovernanceViaVoting() public {
        address newGovImpl = address(new BerachainGovernance());
        _upgradeViaVoting(address(gov), newGovImpl);

        assertEq(newGovImpl, _getImplAddress(address(gov)));
    }

    // Tests to upgrade timelock
    function testFuzz_UpgradeTimelock_FailsIfNotOwner(address caller) public {
        vm.assume(caller != address(timelock) && caller != address(this));
        address newTimelockImpl = address(new TimeLock());
        bytes32 defaultAdminRole = timelock.DEFAULT_ADMIN_ROLE();
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, defaultAdminRole)
        );
        timelock.upgradeToAndCall(newTimelockImpl, "");
    }

    function test_UpgradeTimelockWithCallerAsTimelock() public {
        address newTimelockImpl = address(new TimeLock());
        vm.prank(address(timelock));
        vm.expectEmit();
        emit IERC1967.Upgraded(newTimelockImpl);
        timelock.upgradeToAndCall(newTimelockImpl, "");

        assertEq(newTimelockImpl, _getImplAddress(address(timelock)));
    }

    function test_UpgradeTimelockViaVoting() public {
        address newTimelockImpl = address(new TimeLock());
        _upgradeViaVoting(address(timelock), newTimelockImpl);

        assertEq(newTimelockImpl, _getImplAddress(address(timelock)));
    }

    // Test the 51% majority
    function test_ProposeSuccedsWithMajority() external {
        mockBgt.mint(address(this), 41e18);
        assertEq(51e18, mockBgt.balanceOf(address(this)));

        address otherVoter = _makeDelegatee("other-voter", 49e18);
        assertEq(49e18, mockBgt.balanceOf(otherVoter));

        assertEq(100e18, mockBgt.totalSupply());

        uint256 proposalId = _createTestProposal(address(this), _targets, _calldatas, "Test Proposal");
        vm.warp(gov.proposalSnapshot(proposalId) + 1);

        gov.castVote(proposalId, VOTE_IN_FAVOUR);
        vm.prank(otherVoter);
        gov.castVote(proposalId, VOTE_AGAINST);

        vm.warp(gov.proposalDeadline(proposalId) + 1);
        assertTrue(gov.state(proposalId) == IGovernor.ProposalState.Succeeded);
    }

    // Test the 51% majority
    function test_ProposeFailsWithoutMajority() external {
        mockBgt.mint(address(this), 40.9e18);
        assertEq(50.9e18, mockBgt.balanceOf(address(this)));

        address otherVoter = _makeDelegatee("other-voter", 49.1e18);
        assertEq(49.1e18, mockBgt.balanceOf(otherVoter));

        assertEq(100e18, mockBgt.totalSupply());

        uint256 proposalId = _createTestProposal(address(this), _targets, _calldatas, "Test Proposal");
        vm.warp(gov.proposalSnapshot(proposalId) + 1);

        gov.castVote(proposalId, VOTE_IN_FAVOUR);
        vm.prank(otherVoter);
        gov.castVote(proposalId, VOTE_AGAINST);

        vm.warp(gov.proposalDeadline(proposalId) + 1);
        assertTrue(gov.state(proposalId) == IGovernor.ProposalState.Defeated);
    }

    function _upgradeViaVoting(address _target, address _newImplementation) internal {
        address[] memory targetToUpgrade = new address[](1);
        targetToUpgrade[0] = _target;
        bytes[] memory callDataToUpgrade = new bytes[](1);
        callDataToUpgrade[0] = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (_newImplementation, ""));

        uint256 proposalId = gov.propose(targetToUpgrade, new uint256[](1), callDataToUpgrade, "Upgrade Timelock");

        // Voting Delay is of 1 day
        vm.warp(gov.proposalSnapshot(proposalId) + 1);
        gov.castVote(proposalId, VOTE_IN_FAVOUR);
        vm.warp(gov.proposalDeadline(proposalId) + 1);

        gov.queue(proposalId);
        vm.warp(block.timestamp + MIN_DELAY_TIMELOCK + 1);

        vm.expectEmit();
        emit IERC1967.Upgraded(_newImplementation);
        gov.execute(proposalId);
    }

    // Helpers
    function _makeDelegatee(string memory name, uint256 votingPower) internal returns (address delegatee) {
        delegatee = makeAddr(name);

        mockBgt.mint(delegatee, votingPower);
        vm.prank(delegatee);
        mockBgt.delegate(delegatee);
    }

    function _getImplAddress(address proxy) internal view returns (address) {
        bytes32 IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 impl = vm.load(proxy, IMPLEMENTATION_SLOT);
        return address(uint160(uint256(impl)));
    }

    function _createTestProposal(
        address proposer,
        address[] memory targets,
        bytes[] memory calldatas,
        string memory description
    )
        internal
        returns (uint256 proposalId)
    {
        uint256[] memory values = new uint256[](targets.length);
        vm.prank(proposer);
        return gov.propose(targets, values, calldatas, description);
    }

    function _createSuccessedProposal(
        address proposer,
        address[] memory targets,
        bytes[] memory calldatas,
        string memory description,
        address voter
    )
        internal
        returns (uint256 proposalId)
    {
        proposalId = _createTestProposal(proposer, targets, calldatas, description);
        vm.warp(gov.proposalSnapshot(proposalId) + 1);

        vm.prank(voter);
        gov.castVote(proposalId, 1);

        // Move time forward to pass the voting period
        vm.warp(gov.proposalDeadline(proposalId) + 1);
    }

    function _createQueuedProposal(
        address proposer,
        address[] memory targets,
        bytes[] memory calldatas,
        string memory description,
        address voter
    )
        internal
        returns (uint256 proposalId)
    {
        proposalId = _createSuccessedProposal(proposer, targets, calldatas, description, voter);

        gov.queue(targets, new uint256[](2), calldatas, keccak256(abi.encodePacked(description)));
    }
}
