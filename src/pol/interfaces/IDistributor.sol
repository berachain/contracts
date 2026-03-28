// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import { IPOLErrors } from "./IPOLErrors.sol";
import { IBeraChef } from "./IBeraChef.sol";
import { IDedicatedEmissionStreamManager } from "./IDedicatedEmissionStreamManager.sol";

/// @notice Interface of the Distributor contract.
interface IDistributor is IPOLErrors {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    event Distributed(bytes indexed valPubkey, uint64 indexed nextTimestamp, address indexed receiver, uint256 amount);
    event DedicatedEmissionStreamManagerSet(
        address indexed oldDedicatedEmissionStreamManager, address indexed newDedicatedEmissionStreamManager
    );

    /// @notice Distribute the rewards to the reward allocation receivers according to BRIP-0004.
    /// @dev This will be called for block N at the top of block N+1.
    /// @dev Only system calls allowed i.e only the execution layer client can call this function.
    /// @param pubkey The validator pubkey of the proposer.
    function distributeFor(bytes calldata pubkey) external;

    /// @notice Returns the address of the BeraChef contract.
    function beraChef() external view returns (IBeraChef);

    /// @notice Returns the address of the dedicated emission stream manager contract.
    function dedicatedEmissionStreamManager() external view returns (IDedicatedEmissionStreamManager);

    /// @notice Sets the address of the dedicated emission stream manager contract.
    function setDedicatedEmissionStreamManager(address _dedicatedEmissionStreamManager) external;
}
