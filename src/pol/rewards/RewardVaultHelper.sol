// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IRewardVault } from "src/pol/interfaces/IRewardVault.sol";
import { IRewardVaultHelper } from "src/pol/interfaces/IRewardVaultHelper.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Utils } from "src/libraries/Utils.sol";

/// @title RewardVaultHelper
/// @author Berachain Team
/// @notice Helper contract that allows claiming rewards from multiple RewardVault contracts in a single transaction.
contract RewardVaultHelper is IRewardVaultHelper, AccessControlUpgradeable, UUPSUpgradeable {
    using Utils for bytes4;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address governance) external initializer {
        if (governance == address(0)) ZeroAddress.selector.revertWith();

        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, governance);
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    /// @inheritdoc IRewardVaultHelper
    function claimAllRewards(address[] memory vaults, address receiver) external {
        for (uint256 i = 0; i < vaults.length; i++) {
            address vault = vaults[i];
            IRewardVault(vault).getReward(msg.sender, receiver);
        }
    }
}
