// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { IGovernor } from "@openzeppelin/contracts/governance/IGovernor.sol";
import {
    GovernorVotesQuorumFractionUpgradeable
} from "@openzeppelin-gov-ext/GovernorVotesQuorumFractionUpgradeable.sol";

import { Salt } from "src/base/Salt.sol";
import { BerachainGovernance } from "src/gov/BerachainGovernance.sol";
import { GovDeployer } from "src/gov/GovDeployer.sol";
import { TimeLock } from "src/gov/TimeLock.sol";

import { MockBGT } from "../mock/token/MockBGT.sol";
import { MockERC20 } from "../mock/token/MockERC20.sol";

contract GovDeployerTest is Test {
    address private immutable _voteToken;
    address private immutable _guardian;
    uint256 private constant PROPOSAL_TRESHOLD = 1000e18;
    uint256 private constant VOTING_DELAY = 2 seconds;
    uint256 private constant VOTING_PERIOD = 2 seconds;
    uint256 private constant QUORUM_NUMERATOR_VALUE = 90;
    uint256 private constant TIMELOCK_MIN_DELAY = 1 days;
    Salt private GOV_SALT = Salt({ implementation: 0, proxy: 0 });
    Salt private TIMELOCK_SALT = Salt({ implementation: 0, proxy: 0 });

    constructor() {
        _voteToken = address(new MockBGT());
        _guardian = makeAddr("guardian");
    }

    function test_GovDeployRevertVoteTokenIsAddressZero() public {
        vm.expectRevert();
        new GovDeployer(
            address(0),
            _guardian,
            PROPOSAL_TRESHOLD,
            VOTING_DELAY,
            VOTING_PERIOD,
            QUORUM_NUMERATOR_VALUE,
            TIMELOCK_MIN_DELAY,
            GOV_SALT,
            TIMELOCK_SALT
        );
    }

    function test_GovDeployerRevertWhenQuorumNumeratorValueIsGreatherThanOneHundred() external {
        uint256 quorumNumerator = 101;
        vm.expectRevert(
            abi.encodeWithSelector(
                GovernorVotesQuorumFractionUpgradeable.GovernorInvalidQuorumFraction.selector, quorumNumerator, 100
            )
        );
        new GovDeployer(
            _voteToken,
            _guardian,
            PROPOSAL_TRESHOLD,
            VOTING_DELAY,
            VOTING_PERIOD,
            quorumNumerator,
            TIMELOCK_MIN_DELAY,
            GOV_SALT,
            TIMELOCK_SALT
        );
    }

    function test_GovDeployWithNoVotesToken() public {
        address fakeVoteToken = address(new MockERC20());
        vm.expectRevert("GovDeployer: token is not a valid ERC20Votes or ERC20Metadata");
        new GovDeployer(
            fakeVoteToken,
            _guardian,
            PROPOSAL_TRESHOLD,
            VOTING_DELAY,
            VOTING_PERIOD,
            QUORUM_NUMERATOR_VALUE,
            TIMELOCK_MIN_DELAY,
            GOV_SALT,
            TIMELOCK_SALT
        );
    }

    function test_GovDeployer() public {
        GovDeployer deployer = new GovDeployer(
            _voteToken,
            _guardian,
            PROPOSAL_TRESHOLD,
            VOTING_DELAY,
            VOTING_PERIOD,
            QUORUM_NUMERATOR_VALUE,
            TIMELOCK_MIN_DELAY,
            GOV_SALT,
            TIMELOCK_SALT
        );
        address payable governor = payable(deployer.GOVERNOR());
        address payable timelockAddress = payable(deployer.TIMELOCK_CONTROLLER());

        BerachainGovernance governance = BerachainGovernance(governor);
        TimeLock timeLock = TimeLock(timelockAddress);

        assertEq(address(governance.token()), _voteToken);
        assertEq(governance.timelock(), timelockAddress);
        assertTrue(timeLock.hasRole(timeLock.CANCELLER_ROLE(), _guardian));
        // Check if governor has the necessary roles
        assertTrue(timeLock.hasRole(timeLock.PROPOSER_ROLE(), governor));
        assertTrue(timeLock.hasRole(timeLock.CANCELLER_ROLE(), governor));
        assertTrue(timeLock.hasRole(timeLock.EXECUTOR_ROLE(), governor));

        assertFalse(timeLock.hasRole(timeLock.DEFAULT_ADMIN_ROLE(), address(deployer)));
    }
}
