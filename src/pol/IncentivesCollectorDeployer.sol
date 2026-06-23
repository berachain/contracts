// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Create2Deployer } from "../base/Create2Deployer.sol";
import { Salt } from "../base/Salt.sol";
import { WBERAStakerVault } from "./WBERAStakerVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IncentivesCollector } from "./IncentivesCollector.sol";

/// @title IncentivesCollectorDeployer
/// @author Berachain Team
/// @notice This contract is used to deploy the IncentivesCollector and WBERAStakerVault contracts.
/// @dev Caller must have BERA balance of `INITIAL_DEPOSIT_AMOUNT` which is used to deposit in the vault to avoid
/// inflation attack.
contract IncentivesCollectorDeployer is Create2Deployer {
    /// @notice The initial deposit amount to the WBERAStakerVault to avoid inflation attack.
    uint256 public constant INITIAL_DEPOSIT_AMOUNT = 10e18;

    /// @notice The WBERAStakerVault contract.
    WBERAStakerVault public immutable wberaStakerVault;

    /// @notice The IncentivesCollector contract.
    IncentivesCollector public immutable incentivesCollector;

    /// @notice The WBERA token address, serves as underlying asset.
    IERC20 public constant WBERA = IERC20(0x6969696969696969696969696969696969696969);

    /// @notice Constructor for the IncentivesCollectorDeployer.
    /// @param governance The address of the governance contract.
    /// @param tokenProvider The address of the token provider for initial deposit.
    /// @param payoutAmount The amount of payout for the IncentivesCollector.
    /// @param wberaStakerVaultSalt The salt for the WBERAStakerVault.
    /// @param incentivesCollectorSalt The salt for the IncentivesCollector.
    constructor(
        address governance,
        address tokenProvider,
        uint256 payoutAmount,
        Salt memory wberaStakerVaultSalt,
        Salt memory incentivesCollectorSalt
    ) {
        // deploy the WBERAStakerVault implementation
        address wberaStakerVaultImpl =
            deployWithCreate2(wberaStakerVaultSalt.implementation, type(WBERAStakerVault).creationCode);
        // deploy the WBERAStakerVault proxy
        wberaStakerVault =
            WBERAStakerVault(payable(deployProxyWithCreate2(wberaStakerVaultImpl, wberaStakerVaultSalt.proxy)));

        // deploy the IncentivesCollector implementation
        address incentivesCollectorImpl =
            deployWithCreate2(incentivesCollectorSalt.implementation, type(IncentivesCollector).creationCode);
        // deploy the IncentivesCollector proxy
        incentivesCollector =
            IncentivesCollector(deployProxyWithCreate2(incentivesCollectorImpl, incentivesCollectorSalt.proxy));

        // initialize the contracts
        wberaStakerVault.initialize(governance);
        incentivesCollector.initialize(governance, payoutAmount, address(wberaStakerVault));

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
