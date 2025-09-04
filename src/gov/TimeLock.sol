// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { TimelockControllerUpgradeable } from "@openzeppelin-gov/TimelockControllerUpgradeable.sol";

/// @title TimeLock
/// @author Berachain Team
/// @notice The TimeLock contract is in charge of introducing a delay between a proposal and its execution.
/// @dev This contract extends OpenZeppelin's TimelockController for secure governance operations.
/// @dev See: https://docs.openzeppelin.com/contracts/4.x/api/governance
contract TimeLock is UUPSUpgradeable, TimelockControllerUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }
}
