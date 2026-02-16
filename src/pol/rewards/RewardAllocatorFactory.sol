// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import { Utils } from "../../libraries/Utils.sol";
import { IBeraChef } from "../interfaces/IBeraChef.sol";
import { IRewardAllocation } from "../interfaces/IRewardAllocation.sol";
import { IRewardAllocatorFactory } from "../interfaces/IRewardAllocatorFactory.sol";

/// @title RewardAllocatorFactory
/// @author Berachain Team
/// @notice Factory contract to support baseline reward allocation which acts as a
/// 'fallback' strategy for validators that choose not to proactively manage their reward allocation themselves.
contract RewardAllocatorFactory is IRewardAllocatorFactory, AccessControlUpgradeable, UUPSUpgradeable {
    using Utils for bytes4;

    /// @notice The ALLOCATION_SETTER role (actions to be performed by the allocation bot).
    bytes32 public constant ALLOCATION_SETTER_ROLE = keccak256("ALLOCATION_SETTER_ROLE");

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The BeraChef contract.
    IBeraChef public beraChef;

    /// @notice The baseline reward allocation.
    IRewardAllocation.RewardAllocation internal _baselineAllocation;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _governance, address _beraChef) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _governance);

        beraChef = IBeraChef(_beraChef);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          ADMIN                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    /// @inheritdoc IRewardAllocatorFactory
    function setBaselineAllocation(IRewardAllocation.Weight[] calldata weights)
        external
        onlyRole(ALLOCATION_SETTER_ROLE)
    {
        beraChef.validateWeights(weights);

        _baselineAllocation.startBlock = uint64(block.number);
        delete _baselineAllocation.weights;
        for (uint256 i = 0; i < weights.length; ++i) {
            _baselineAllocation.weights.push(weights[i]);
        }
        emit BaselineAllocationSet(weights);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          READ                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRewardAllocatorFactory
    function getBaselineAllocation() external view returns (IRewardAllocation.RewardAllocation memory) {
        return _baselineAllocation;
    }
}
