// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Create2Deployer } from "../base/Create2Deployer.sol";
import { Salt } from "../base/Salt.sol";
import { WBERAStakerVault } from "./WBERAStakerVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BGTIncentiveFeeCollector } from "./BGTIncentiveFeeCollector.sol";

/// @title BGTIncentiveFeeDeployer
/// @author Berachain Team
/// @notice This contract is used to deploy the BGTIncentiveFeeCollector and WBERAStakerVault contracts.
/// @dev Caller must have BERA balance of `INITIAL_DEPOSIT_AMOUNT` which is used to deposit in the vault to avoid
/// inflation attack.
contract BGTIncentiveFeeDeployer is Create2Deployer {
    /// @notice The initial deposit amount to the WBERAStakerVault to avoid inflation attack.
    uint256 public constant INITIAL_DEPOSIT_AMOUNT = 10e18;

    /// @notice The WBERAStakerVault contract.
    WBERAStakerVault public immutable wberaStakerVault;

    /// @notice The BGTIncentiveFeeCollector contract.
    BGTIncentiveFeeCollector public immutable bgtIncentiveFeeCollector;

    /// @notice The WBERA token address, serves as underlying asset.
    IERC20 public constant WBERA = IERC20(0x6969696969696969696969696969696969696969);

    /// @notice Constructor for the BGTIncentiveFeeDeployer.
    /// @param governance The address of the governance contract.
    /// @param tokenProvider The address of the token provider for initial deposit.
    /// @param payoutAmount The amount of payout for the BGTIncentiveFeeCollector.
    /// @param wberaStakerVaultSalt The salt for the WBERAStakerVault.
    /// @param bgtIncentiveFeeCollectorSalt The salt for the BGTIncentiveFeeCollector.
    constructor(
        address governance,
        address tokenProvider,
        uint256 payoutAmount,
        Salt memory wberaStakerVaultSalt,
        Salt memory bgtIncentiveFeeCollectorSalt
    ) {
        // deploy the WBERAStakerVault implementation
        address wberaStakerVaultImpl =
            deployWithCreate2(wberaStakerVaultSalt.implementation, type(WBERAStakerVault).creationCode);
        // deploy the WBERAStakerVault proxy
        wberaStakerVault =
            WBERAStakerVault(payable(deployProxyWithCreate2(wberaStakerVaultImpl, wberaStakerVaultSalt.proxy)));

        // deploy the BGTIncentiveFeeCollector implementation
        address bgtIncentiveFeeCollectorImpl =
            deployWithCreate2(bgtIncentiveFeeCollectorSalt.implementation, type(BGTIncentiveFeeCollector).creationCode);
        // deploy the BGTIncentiveFeeCollector proxy
        bgtIncentiveFeeCollector = BGTIncentiveFeeCollector(
            deployProxyWithCreate2(bgtIncentiveFeeCollectorImpl, bgtIncentiveFeeCollectorSalt.proxy)
        );

        // initialize the contracts
        wberaStakerVault.initialize(governance);
        bgtIncentiveFeeCollector.initialize(governance, payoutAmount, address(wberaStakerVault));

        // deposit `INITIAL_DEPOSIT_AMOUNT` to the vault to avoid inflation attack
        // first get tokens from the token provider
        WBERA.transferFrom(tokenProvider, address(this), INITIAL_DEPOSIT_AMOUNT);
        // then approve the vault to spend the tokens
        WBERA.approve(address(wberaStakerVault), INITIAL_DEPOSIT_AMOUNT);
        wberaStakerVault.deposit(INITIAL_DEPOSIT_AMOUNT, governance);

        // make sure the inflation attack is avoided
        require(wberaStakerVault.totalSupply() == INITIAL_DEPOSIT_AMOUNT, "Inflation attack happened");
    }
}
