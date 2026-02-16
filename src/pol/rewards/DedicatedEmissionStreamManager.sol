// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IDedicatedEmissionStreamManager } from "../interfaces/IDedicatedEmissionStreamManager.sol";
import { IBeraChef } from "../interfaces/IBeraChef.sol";
import { Utils } from "../../libraries/Utils.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

/// @title DedicatedEmissionStreamManager
/// @author Berachain Team
/// @notice The DedicatedEmissionStreamManager contract manages the emission percentage and reward allocation for the
/// dedicated emission stream program.
contract DedicatedEmissionStreamManager is IDedicatedEmissionStreamManager, AccessControlUpgradeable, UUPSUpgradeable {
    using Utils for bytes4;

    /// @notice The ALLOCATION_MANAGER role.
    bytes32 public constant ALLOCATION_MANAGER_ROLE = keccak256("ALLOCATION_MANAGER_ROLE");

    /// @notice Represents 100%. Chosen to be less granular.
    uint96 public constant ONE_HUNDRED_PERCENT = 1e4;

    /// @notice The beraChef contract that is allowed to set the reward allocation.
    address public beraChef;

    /// @notice The distributor contract that is allowed to notify emissions.
    address public distributor;

    /// @notice The reward allocation.
    Weight[] internal _rewardAllocation;

    /// @notice The reward allocation percentage.
    uint96 public emissionPerc;

    /// @notice The target emission for vaults.
    mapping(address => uint256) public targetEmission;

    /// @notice The debt of the vaults.
    mapping(address => uint256) public debt;

    modifier onlyDistributor() {
        if (msg.sender != distributor) NotDistributor.selector.revertWith();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _governance, address _distributor, address _beraChef) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _governance);

        if (_distributor == address(0) || _beraChef == address(0)) {
            ZeroAddress.selector.revertWith();
        }

        distributor = _distributor;
        emit DistributorSet(distributor);
        beraChef = _beraChef;
        emit BeraChefSet(address(beraChef));
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    /// @inheritdoc IDedicatedEmissionStreamManager
    function setDistributor(address _distributor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_distributor == address(0)) {
            ZeroAddress.selector.revertWith();
        }
        distributor = _distributor;
        emit DistributorSet(distributor);
    }

    /// @inheritdoc IDedicatedEmissionStreamManager
    function setBeraChef(address _beraChef) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_beraChef == address(0)) {
            ZeroAddress.selector.revertWith();
        }
        beraChef = _beraChef;
        emit BeraChefSet(beraChef);
    }

    /// @inheritdoc IDedicatedEmissionStreamManager
    function setEmissionPerc(uint96 _emissionPerc) external onlyRole(ALLOCATION_MANAGER_ROLE) {
        if (_emissionPerc > ONE_HUNDRED_PERCENT) {
            InvalidEmissionPerc.selector.revertWith();
        }
        emissionPerc = _emissionPerc;
        emit EmissionPercSet(emissionPerc);
    }

    /// @inheritdoc IDedicatedEmissionStreamManager
    function setRewardAllocation(Weight[] memory newRewardAllocation) external onlyRole(ALLOCATION_MANAGER_ROLE) {
        _validateRewardAllocation(newRewardAllocation);
        delete _rewardAllocation;
        uint256 length = newRewardAllocation.length;
        for (uint256 i; i < length;) {
            _rewardAllocation.push(newRewardAllocation[i]);
            unchecked {
                ++i;
            }
        }

        emit RewardAllocationSet(_rewardAllocation);
    }

    /// @inheritdoc IDedicatedEmissionStreamManager
    function setTargetEmission(address vault, uint256 _targetEmission) external onlyRole(ALLOCATION_MANAGER_ROLE) {
        if (debt[vault] > _targetEmission) {
            InvalidTargetEmission.selector.revertWith();
        }
        targetEmission[vault] = _targetEmission;
        emit TargetEmissionSet(vault, _targetEmission);
    }

    /// @inheritdoc IDedicatedEmissionStreamManager
    function notifyEmission(address vault, uint256 amount) external onlyDistributor {
        debt[vault] += amount;
        emit NotifyEmission(vault, amount);
    }

    /// @inheritdoc IDedicatedEmissionStreamManager
    function getRewardAllocation() external view returns (Weight[] memory) {
        return _rewardAllocation;
    }

    /// @inheritdoc IDedicatedEmissionStreamManager
    function getMaxEmission(address vault, uint256 emission) external view returns (uint256) {
        if (debt[vault] < targetEmission[vault]) {
            uint256 remainingEmission = targetEmission[vault] - debt[vault];
            return FixedPointMathLib.min(emission, remainingEmission);
        }
        return 0;
    }

    function _validateRewardAllocation(Weight[] memory rewardAllocation) internal view {
        // Ensure that the total weight is 100%.
        uint96 totalWeight;
        for (uint256 i; i < rewardAllocation.length;) {
            Weight memory rewardAllocationItem = rewardAllocation[i];
            if (
                rewardAllocationItem.percentageNumerator == 0
                    || rewardAllocationItem.percentageNumerator > ONE_HUNDRED_PERCENT
            ) {
                InvalidRewardAllocationWeights.selector.revertWith();
            }

            // ensure that all receivers are approved for every weight in the reward allocation.
            if (!IBeraChef(beraChef).isWhitelistedVault(rewardAllocationItem.receiver)) {
                NotWhitelistedVault.selector.revertWith();
            }

            totalWeight += rewardAllocationItem.percentageNumerator;
            unchecked {
                ++i;
            }
        }

        if (totalWeight != ONE_HUNDRED_PERCENT) {
            InvalidRewardAllocationWeights.selector.revertWith();
        }
    }
}
