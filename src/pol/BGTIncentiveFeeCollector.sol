// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { Utils } from "../libraries/Utils.sol";
import { IWBERAStakerVault } from "./interfaces/IWBERAStakerVault.sol";
import { IBGTIncentiveFeeCollector } from "./interfaces/IBGTIncentiveFeeCollector.sol";
import { IStakerVault } from "./interfaces/lst/IStakerVault.sol";
import { ILSTAdapter } from "./interfaces/lst/ILSTAdapter.sol";

/// @title BGTIncentiveFeeCollector
/// @author Berachain Team
/// @notice Collects the fees on the incentives posted on reward vaults and auction them for WBERA.
/// Accrued WBERA serves as a payout for the stakers of `WBERAStakerVault.sol` and added `LSTStakerVault.sol`s.
/// @dev This contract is inspired by the `FeeCollector.sol` for auctioning collected tokens.
contract BGTIncentiveFeeCollector is
    IBGTIncentiveFeeCollector,
    PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;
    using Utils for bytes4;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          CONSTANTS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The PAUSER role
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice The MANAGER role.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice The WBERA token address, serves as payout token.
    address public constant WBERA = 0x6969696969696969696969696969696969696969;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           STORAGE                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBGTIncentiveFeeCollector
    uint256 public queuedPayoutAmount;

    /// @inheritdoc IBGTIncentiveFeeCollector
    uint256 public payoutAmount;

    /// @inheritdoc IBGTIncentiveFeeCollector
    address public wberaStakerVault;

    /// @inheritdoc IBGTIncentiveFeeCollector
    address[] public lstStakerVaults;

    /// @inheritdoc IBGTIncentiveFeeCollector
    mapping(address lstVault => address lstAdapter) public lstAdapters;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the contract.
    /// @param governance The address of the governance contract.
    /// @param _payoutAmount The payout amount.
    function initialize(address governance, uint256 _payoutAmount, address _wberaStakerVault) public initializer {
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        if (governance == address(0)) ZeroAddress.selector.revertWith();
        if (_payoutAmount == 0) PayoutAmountIsZero.selector.revertWith();
        if (_wberaStakerVault == address(0)) ZeroAddress.selector.revertWith();

        _grantRole(DEFAULT_ADMIN_ROLE, governance);
        // Allow the MANAGER to control the PAUSER_ROLE
        _setRoleAdmin(PAUSER_ROLE, MANAGER_ROLE);

        payoutAmount = _payoutAmount;
        emit PayoutAmountSet(0, _payoutAmount);

        wberaStakerVault = _wberaStakerVault;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    /// @inheritdoc IBGTIncentiveFeeCollector
    function queuePayoutAmountChange(uint256 _newPayoutAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newPayoutAmount == 0) PayoutAmountIsZero.selector.revertWith();
        emit QueuedPayoutAmount(_newPayoutAmount, payoutAmount);
        queuedPayoutAmount = _newPayoutAmount;
    }

    /// @inheritdoc IBGTIncentiveFeeCollector
    function addLstStakerVault(address lstStakerVault, address lstAdapter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (lstStakerVault == address(0)) ZeroAddress.selector.revertWith();
        if (lstAdapter == address(0)) ZeroAddress.selector.revertWith();
        if (lstAdapters[lstStakerVault] != address(0)) LSTStakerVaultAlreadyAdded.selector.revertWith();

        if (IERC20Metadata(IERC4626(lstStakerVault).asset()).decimals() != 18) {
            InvalidToken.selector.revertWith(IERC4626(lstStakerVault).asset());
        }

        emit LstStakerVaultAdded(lstStakerVault, lstAdapter);
        lstStakerVaults.push(lstStakerVault);
        lstAdapters[lstStakerVault] = lstAdapter;
    }

    /// @inheritdoc IBGTIncentiveFeeCollector
    function removeLstStakerVault(address lstStakerVault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (lstAdapters[lstStakerVault] == address(0)) LSTStakerVaultNotFound.selector.revertWith();
        emit LstStakerVaultRemoved(lstStakerVault);

        for (uint256 i = 0; i < lstStakerVaults.length; i++) {
            if (lstStakerVaults[i] == lstStakerVault) {
                uint256 lastIndex = lstStakerVaults.length - 1;

                // Swap and pop
                if (i != lastIndex) {
                    lstStakerVaults[i] = lstStakerVaults[lastIndex];
                }
                lstStakerVaults.pop();

                delete lstAdapters[lstStakerVault];
                return;
            }
        }
    }

    /// @inheritdoc IBGTIncentiveFeeCollector
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @inheritdoc IBGTIncentiveFeeCollector
    function unpause() external onlyRole(MANAGER_ROLE) {
        _unpause();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       TOKENS AUCTION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBGTIncentiveFeeCollector
    function claimFees(address _recipient, address[] calldata _feeTokens) external whenNotPaused {
        // Transfer the payout amount of the payout token to this contract from msg.sender.
        IERC20(WBERA).safeTransferFrom(msg.sender, address(this), payoutAmount);
        uint256[] memory amounts = _splitAmount(payoutAmount);

        // Send rewards to vaults

        // WBERA
        {
            // approve the WBERAStakerVault contract to spend its share of the payout amount
            IERC20(WBERA).forceApprove(wberaStakerVault, amounts[0]);
            // send the payout amount to the WBERAStakerVault contract
            IWBERAStakerVault(wberaStakerVault).receiveRewards(amounts[0]);
        }

        // LSTs
        for (uint256 i = 1; i < amounts.length;) {
            IStakerVault vault = IStakerVault(lstStakerVaults[i - 1]);
            if (amounts[i] > 0) {
                ILSTAdapter lstAdapter = ILSTAdapter(lstAdapters[address(vault)]);
                IERC20(WBERA).forceApprove(address(lstAdapter), amounts[i]);
                uint256 lstAmount = lstAdapter.stake(amounts[i]);
                emit RewardConverted(address(vault), amounts[i], lstAmount);
                IERC20(IERC4626(address(vault)).asset()).forceApprove(address(vault), lstAmount);
                vault.receiveRewards(lstAmount);
            }
            unchecked {
                ++i;
            }
        }

        // From all the specified fee tokens, transfer them to the recipient.
        for (uint256 i; i < _feeTokens.length;) {
            address feeToken = _feeTokens[i];
            uint256 feeTokenAmountToTransfer = IERC20(feeToken).balanceOf(address(this));
            IERC20(feeToken).safeTransfer(_recipient, feeTokenAmountToTransfer);
            emit IncentiveFeeTokenClaimed(msg.sender, _recipient, feeToken, feeTokenAmountToTransfer);
            unchecked {
                ++i;
            }
        }

        emit IncentiveFeesClaimed(msg.sender, _recipient);
        if (queuedPayoutAmount != 0) _setPayoutAmount();
    }

    /// @inheritdoc IBGTIncentiveFeeCollector
    function lstStakerVaultsLength() external view returns (uint256) {
        return lstStakerVaults.length;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Set the payout amount to the queued payout amount
    function _setPayoutAmount() internal {
        emit PayoutAmountSet(payoutAmount, queuedPayoutAmount);
        payoutAmount = queuedPayoutAmount;
        queuedPayoutAmount = 0;
    }

    /// @dev Split the given `amount` between the WBERA staker vault (index 0) and all
    /// LST staker vaults (indices 1..len) proportionally to their stake in WBERA terms.
    /// @return amounts Array of length (lstStakerVaults.length + 1)
    function _splitAmount(uint256 amount) internal view returns (uint256[] memory amounts) {
        uint256 len = lstStakerVaults.length;

        amounts = new uint256[](len + 1);
        uint256[] memory stakes = new uint256[](len + 1);

        // WBERA net stake
        stakes[0] = IERC4626(wberaStakerVault).totalAssets();
        uint256 totalStake = stakes[0];

        // Iterate over vaults to fill stakes[1..len+1]
        for (uint256 i = 1; i < len + 1;) {
            IERC4626 vault = IERC4626(lstStakerVaults[i - 1]);
            uint256 stake = vault.totalAssets();

            if (stake > 0) {
                uint256 rate = ILSTAdapter(lstAdapters[address(vault)]).getRate();
                uint256 value = (stake * rate) / 1e18;
                stakes[i] = value;
                totalStake += value;
            }

            unchecked {
                ++i;
            }
        }

        // 0 edge case: no stakes or no amount to split
        if (totalStake == 0 || amount == 0) {
            return amounts;
        }

        // Make the splits
        uint256 distributed;
        for (uint256 i; i < len + 1;) {
            uint256 part = (amount * stakes[i]) / totalStake;
            amounts[i] = part;
            distributed += part;
            unchecked {
                ++i;
            }
        }

        // Assign dust to WBERA bucket
        if (distributed < amount) {
            unchecked {
                amounts[0] += amount - distributed;
            }
        }

        return amounts;
    }
}
