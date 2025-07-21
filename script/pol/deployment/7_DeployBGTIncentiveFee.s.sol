// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { RBAC } from "../../base/RBAC.sol";
import { Storage } from "../../base/Storage.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BGTIncentiveFeeDeployer } from "src/pol/BGTIncentiveFeeDeployer.sol";

import {
    BGT_INCENTIVE_FEE_DEPLOYER_SALT,
    WBERA_STAKER_VAULT_SALT,
    BGT_INCENTIVE_FEE_COLLECTOR_SALT
} from "../POLSalts.sol";

contract DeployBGTIncentiveFeeScript is BaseScript, RBAC, Storage, Create2Deployer {
    // The amount to be paid out to the incentive fee collector in order to claim fees.
    uint256 internal constant PAYOUT_AMOUNT = 50_000 ether; // WBERA

    /// @notice The initial deposit amount to the WBERAStakerVault to avoid inflation attack.
    uint256 public constant INITIAL_DEPOSIT_AMOUNT = 10e18;

    /// @notice The WBERA token address, serves as underlying asset.
    IERC20 public constant WBERA = IERC20(0x6969696969696969696969696969696969696969);

    function run() public broadcast {
        console2.log("deploying BGTIncentiveFeeDeployer");
        console2.log("Broadcaster address:", msg.sender);
        console2.log("WBERA balance of broadcaster:", WBERA.balanceOf(msg.sender));
        address predictedAddress = getCreate2AddressWithArgs(
            BGT_INCENTIVE_FEE_DEPLOYER_SALT,
            type(BGTIncentiveFeeDeployer).creationCode,
            abi.encode(
                msg.sender, msg.sender, PAYOUT_AMOUNT, WBERA_STAKER_VAULT_SALT, BGT_INCENTIVE_FEE_COLLECTOR_SALT
            )
        );
        console2.log("BGTIncentiveFeeDeployer predicted address:", predictedAddress);
        // approve the deployer to spend the tokens
        WBERA.approve(predictedAddress, INITIAL_DEPOSIT_AMOUNT);

        // log the allowance
        console2.log("WBERA allowance of the deployer:", WBERA.allowance(msg.sender, predictedAddress));

        // deploy the BGTIncentiveFeeDeployer
        BGTIncentiveFeeDeployer bgtIncentiveFeeDeployer = BGTIncentiveFeeDeployer(
            deployWithCreate2WithArgs(
                BGT_INCENTIVE_FEE_DEPLOYER_SALT,
                type(BGTIncentiveFeeDeployer).creationCode,
                abi.encode(
                    msg.sender, msg.sender, PAYOUT_AMOUNT, WBERA_STAKER_VAULT_SALT, BGT_INCENTIVE_FEE_COLLECTOR_SALT
                )
            )
        );
        wberaStakerVault = bgtIncentiveFeeDeployer.wberaStakerVault();
        bgtIncentiveFeeCollector = bgtIncentiveFeeDeployer.bgtIncentiveFeeCollector();

        console2.log("BGTIncentiveFeeDeployer deployed at", address(bgtIncentiveFeeDeployer));
        console2.log("WBERAStakerVault deployed at", address(wberaStakerVault));
        console2.log("BGTIncentiveFeeCollector deployed at", address(bgtIncentiveFeeCollector));

        //  grant MANAGER and PAUSER roles to the deployer
        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        RBAC.RoleDescription memory incentiveFeeCollectorManagerRole = RBAC.RoleDescription({
            contractName: "BGTIncentiveFeeCollector",
            contractAddr: address(bgtIncentiveFeeCollector),
            name: "MANAGER_ROLE",
            role: bgtIncentiveFeeCollector.MANAGER_ROLE()
        });

        RBAC.RoleDescription memory incentiveFeeCollectorPauserRole = RBAC.RoleDescription({
            contractName: "BGTIncentiveFeeCollector",
            contractAddr: address(bgtIncentiveFeeCollector),
            name: "PAUSER_ROLE",
            role: bgtIncentiveFeeCollector.PAUSER_ROLE()
        });

        RBAC.RoleDescription memory wberaStakerVaultManagerRole = RBAC.RoleDescription({
            contractName: "WBERAStakerVault",
            contractAddr: address(wberaStakerVault),
            name: "MANAGER_ROLE",
            role: wberaStakerVault.MANAGER_ROLE()
        });

        RBAC.RoleDescription memory wberaStakerVaultPauserRole = RBAC.RoleDescription({
            contractName: "WBERAStakerVault",
            contractAddr: address(wberaStakerVault),
            name: "PAUSER_ROLE",
            role: wberaStakerVault.PAUSER_ROLE()
        });

        _grantRole(wberaStakerVaultManagerRole, deployer);
        _grantRole(wberaStakerVaultPauserRole, deployer);
        console2.log("Granted MANAGER and PAUSER roles to the deployer for WBERAStakerVault");

        _grantRole(incentiveFeeCollectorManagerRole, deployer);
        _grantRole(incentiveFeeCollectorPauserRole, deployer);
        console2.log("Granted MANAGER and PAUSER roles to the deployer for BGTIncentiveFeeCollector");
    }
}
