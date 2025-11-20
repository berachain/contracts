// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IVotes } from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import { TimelockControllerUpgradeable } from "@openzeppelin-gov/TimelockControllerUpgradeable.sol";

import { Create2Deployer } from "../base/Create2Deployer.sol";
import { Salt } from "../base/Salt.sol";
import { BerachainGovernance, InitialGovernorParameters } from "./BerachainGovernance.sol";
import { TimeLock } from "./TimeLock.sol";

/// @title GovDeployer
/// @notice The contract responsible for deploying the governance contracts.
/// @dev This contracts exists in order to avoid front-running issues upon deploy.
contract GovDeployer is Create2Deployer {
    /// @notice The expected EIP-6372 clock mode of the governance token upon which this contract is based
    string internal constant GOV_TOKEN_CLOCK_MODE = "mode=timestamp";

    /// @notice The deployed governor contract
    address public immutable GOVERNOR;
    /// @notice The deployed timelock contract
    address public immutable TIMELOCK_CONTROLLER;

    /// @param token The address of the BGT
    /// @param guardian The guardian multi-sig, if any
    /// @param proposalThreshold The minimum amount of delegated governance tokens for proposal creation
    /// @param votingDelay The time delay between proposal creation and voting period
    /// @param votingPeriod The time duration of the voting period
    /// @param quorumNumeratorValue The numerator of the needed quorum percentage
    /// @param timelockMinDelay The time duration of the enforced time-lock
    constructor(
        address token,
        address guardian,
        uint256 proposalThreshold,
        uint256 votingDelay,
        uint256 votingPeriod,
        uint256 quorumNumeratorValue,
        uint256 timelockMinDelay,
        Salt memory govSalt,
        Salt memory timelockSalt
    ) {
        // Check if the token implements ERC20Votes and ERC20 metadata
        _checkIfERC20Votes(token);

        BerachainGovernance governance = BerachainGovernance(_deploy(type(BerachainGovernance).creationCode, govSalt));

        GOVERNOR = address(governance);

        TimeLock timelock = TimeLock(_deploy(type(TimeLock).creationCode, timelockSalt));
        TIMELOCK_CONTROLLER = address(timelock);

        address[] memory enabledContracts = new address[](1);
        enabledContracts[0] = GOVERNOR;
        // NOTE: temporary grant the admin role to this contract in order to set the guardian.
        timelock.initialize(timelockMinDelay, enabledContracts, enabledContracts, address(this));
        if (guardian != address(0)) {
            timelock.grantRole(timelock.CANCELLER_ROLE(), guardian);
        }
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));

        InitialGovernorParameters memory params = InitialGovernorParameters({
            proposalThreshold: proposalThreshold * (10 ** IERC20Metadata(token).decimals()),
            quorumNumeratorValue: quorumNumeratorValue,
            votingDelay: uint48(votingDelay),
            votingPeriod: uint32(votingPeriod)
        });

        governance.initialize(IVotes(token), TimelockControllerUpgradeable(timelock), params);

        require(
            keccak256(bytes(governance.CLOCK_MODE())) == keccak256(bytes(GOV_TOKEN_CLOCK_MODE)),
            "Unexpected EIP-6372 clock mode"
        );
    }

    /**
     * @notice Deploy a proxied contract with CREATE2.
     * @param creationCode The type(Contract).creationCode value.
     * @param salt The salt value.
     * @return proxy The address of the deployed proxy.
     */
    function _deploy(bytes memory creationCode, Salt memory salt) internal returns (address payable proxy) {
        address impl = deployWithCreate2(salt.implementation, creationCode);
        proxy = payable(deployProxyWithCreate2(impl, salt.proxy));
    }

    /**
     * @notice Check if the token implements ERC20Votes and ERC20Metadata
     * @param token The address of the token
     */
    function _checkIfERC20Votes(address token) internal view {
        if (!_supportsERC20VotesAndMetadata(token)) {
            revert("GovDeployer: token is not a valid ERC20Votes or ERC20Metadata");
        }
    }

    /**
     * @notice Perform call to check if token implements IVotes and ERC20Metadata
     * @param token The address of the token
     * @return True if the token implements both IVotes and ERC20Metadata, false otherwise.
     */
    function _supportsERC20VotesAndMetadata(address token) internal view returns (bool) {
        try IVotes(token).getVotes(address(this)) {
            // Check if the token implements ERC20 by checking name() and decimals()
            IERC20Metadata(token).name();
            IERC20Metadata(token).decimals();

            return true;
        } catch {
            return false;
        }
    }
}
