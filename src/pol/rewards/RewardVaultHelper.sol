// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IRewardVault } from "src/pol/interfaces/IRewardVault.sol";
import { IRewardVaultHelper } from "src/pol/interfaces/IRewardVaultHelper.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Utils } from "src/libraries/Utils.sol";
import { IWBERA } from "../interfaces/IWBERA.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

/// @title RewardVaultHelper
/// @author Berachain Team
/// @notice Helper contract that allows claiming rewards from multiple RewardVault contracts in a single transaction.
contract RewardVaultHelper is IRewardVaultHelper, AccessControlUpgradeable, UUPSUpgradeable {
    using Utils for bytes4;
    using SafeTransferLib for address;

    /// @notice The WBERA token address.
    address payable public constant WBERA_ADDRESS = payable(0x6969696969696969696969696969696969696969);

    /// @notice The sWBERA token address.
    address public sWBERA;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    receive() external payable { }

    function initialize(address governance) external initializer {
        if (governance == address(0)) ZeroAddress.selector.revertWith();

        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, governance);
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    /// @notice Set the sWBERA address.
    /// @dev Can only be called by the DEFAULT_ADMIN_ROLE.
    /// @param _sWBERA The address of the sWBERA token.
    function setSWBERA(address _sWBERA) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_sWBERA == address(0)) ZeroAddress.selector.revertWith();
        sWBERA = _sWBERA;
        emit SWBERASet(_sWBERA);
    }

    /// @inheritdoc IRewardVaultHelper
    function claimAllRewards(address[] memory vaults, address receiver) external {
        uint256 rewardsAmount = _claimRewards(vaults, receiver);
        emit RewardsClaimed(rewardsAmount, receiver, WBERA_ADDRESS);
    }

    /// @inheritdoc IRewardVaultHelper
    function claimAllRewards(address[] memory vaults, address receiver, address outputToken) external {
        if (outputToken != WBERA_ADDRESS && outputToken != sWBERA && outputToken != address(0)) {
            InvalidToken.selector.revertWith();
        }

        address _receiver = address(this);
        if (outputToken == WBERA_ADDRESS) _receiver = receiver;

        uint256 rewardsAmount = _claimRewards(vaults, _receiver);

        if (outputToken == address(0)) _unwrapWBERA(rewardsAmount, receiver); // native BERA
        else if (outputToken == sWBERA) _stakeWBERA(rewardsAmount, receiver);

        emit RewardsClaimed(rewardsAmount, receiver, outputToken);
    }

    /// @inheritdoc IRewardVaultHelper
    function withdrawAllFromVaults(address[] memory vaults, address receiver) external {
        if (receiver == address(0)) ZeroAddress.selector.revertWith();

        for (uint256 i = 0; i < vaults.length; i++) {
            IRewardVault vault = IRewardVault(vaults[i]);
            uint256 amount = vault.withdrawAllFor(msg.sender);
            if (amount > 0) address(vault.stakeToken()).safeTransfer(receiver, amount);
        }
    }

    function _claimRewards(address[] memory vaults, address receiver) internal returns (uint256 rewardsAmount) {
        for (uint256 i = 0; i < vaults.length; i++) {
            address vault = vaults[i];
            rewardsAmount += IRewardVault(vault).getReward(msg.sender, receiver);
        }
        return rewardsAmount;
    }

    function _unwrapWBERA(uint256 amount, address receiver) internal {
        IWBERA(WBERA_ADDRESS).withdraw(amount);
        SafeTransferLib.safeTransferETH(receiver, amount);
    }

    function _stakeWBERA(uint256 amount, address receiver) internal {
        IERC20(WBERA_ADDRESS).approve(address(sWBERA), amount);
        IERC4626(sWBERA).deposit(amount, receiver);
    }
}
