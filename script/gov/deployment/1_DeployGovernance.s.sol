// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { GovDeployer } from "src/gov/GovDeployer.sol";
import { BerachainGovernance } from "src/gov/BerachainGovernance.sol";
import { TimeLock } from "src/gov/TimeLock.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { AddressBook } from "../../base/AddressBook.sol";

contract DeployGovernanceScript is BaseScript, AddressBook {
    // Placeholder. Change before deployment
    /// @notice The guardian multi-sig, if any
    /// @dev If address(0) the deployer will not grant the canceler role
    address constant GOV_GUARDIAN = address(0);

    /// Governance params
    /// @notice Minimum amount of delegated governance tokens for proposal creation
    /// @dev This is a pure number; the decimals are handled later on.
    uint256 public constant GOV_PROPOSAL_THRESHOLD = 10_000;
    /// @notice Time delay between proposal creation and voting period
    uint256 public constant GOV_VOTING_DELAY = 1 hours;
    /// @notice Time duration of the voting period
    uint256 public constant GOV_VOTING_PERIOD = 5 days;
    /// @notice Numerator of the needed quorum percentage
    uint256 public constant GOV_QUORUM_NUMERATOR = 20;
    /// @notice Time duration of the enforced time-lock
    uint256 public constant TIMELOCK_MIN_DELAY = 2 days;

    function run() public broadcast {
        _validateCode("BGT", _polAddresses.bgt);
        require(GOV_GUARDIAN != address(0), "GOV_GUARDIAN must be set");

        GovDeployer govDeployer = new GovDeployer(
            _polAddresses.bgt,
            GOV_GUARDIAN,
            GOV_PROPOSAL_THRESHOLD,
            GOV_VOTING_DELAY,
            GOV_VOTING_PERIOD,
            GOV_QUORUM_NUMERATOR,
            TIMELOCK_MIN_DELAY,
            _saltsForProxy(type(BerachainGovernance).creationCode),
            _saltsForProxy(type(TimeLock).creationCode)
        );
        _checkDeploymentAddress("Governance", govDeployer.GOVERNOR(), _governanceAddresses.governance);
        _checkDeploymentAddress(
            "Governance timelock", govDeployer.TIMELOCK_CONTROLLER(), _governanceAddresses.timelock
        );

        BerachainGovernance gov = BerachainGovernance(payable(govDeployer.GOVERNOR()));
        require(address(gov.token()) == _polAddresses.bgt, "Governance token address mismatch");
        require(address(gov.timelock()) == _governanceAddresses.timelock, "Governance timelock address mismatch");
        uint256 threshold = GOV_PROPOSAL_THRESHOLD * 10 ** IERC20(_polAddresses.bgt).decimals();
        require(gov.proposalThreshold() == threshold, "Governance proposal threshold mismatch");
        require(gov.votingDelay() == GOV_VOTING_DELAY, "Governance voting delay mismatch");
        require(gov.votingPeriod() == GOV_VOTING_PERIOD, "Governance voting period mismatch");
        require(gov.quorumNumerator() == GOV_QUORUM_NUMERATOR, "Governance quorum numerator mismatch");

        TimeLock timelock = TimeLock(payable(govDeployer.TIMELOCK_CONTROLLER()));
        require(timelock.getMinDelay() == TIMELOCK_MIN_DELAY, "Timelock min delay mismatch");
        require(timelock.hasRole(timelock.CANCELLER_ROLE(), GOV_GUARDIAN), "Timelock guardian mismatch");
        require(!timelock.hasRole(timelock.CANCELLER_ROLE(), address(govDeployer)), "Timelock guardian mismatch");
        require(
            timelock.hasRole(timelock.PROPOSER_ROLE(), _governanceAddresses.governance), "Timelock proposer mismatch"
        );
        require(
            timelock.hasRole(timelock.EXECUTOR_ROLE(), _governanceAddresses.governance), "Timelock executor mismatch"
        );

        console2.log("Please provide the needed roles/permissions to the TimeLock contract");
    }
}
