// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseDeployScript } from "../../base/BaseDeploy.s.sol";
import { RBAC } from "../../base/RBAC.sol";
import { Storage } from "../../base/Storage.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IncentivesCollectorDeployer } from "src/pol/IncentivesCollectorDeployer.sol";
import { WBERAStakerVault } from "src/pol/WBERAStakerVault.sol";
import { IncentivesCollector } from "src/pol/IncentivesCollector.sol";

contract DeployBGTIncentiveFeeScript is BaseDeployScript, RBAC, Storage {
    // The amount to be paid out to the incentive fee collector in order to claim fees.
    uint256 internal constant PAYOUT_AMOUNT = 50_000 ether; // WBERA

    /// @notice The initial deposit amount to the WBERAStakerVault to avoid inflation attack.
    uint256 public constant INITIAL_DEPOSIT_AMOUNT = 10e18;

    /// @notice The WBERA token address, serves as underlying asset.
    IERC20 public constant WBERA = IERC20(0x6969696969696969696969696969696969696969);

    function run() public broadcast {
        console2.log("deploying IncentivesCollectorDeployer");
        console2.log("Broadcaster address:", msg.sender);
        console2.log("WBERA balance of broadcaster:", WBERA.balanceOf(msg.sender));

        bytes memory args = abi.encode(
            msg.sender,
            msg.sender,
            PAYOUT_AMOUNT,
            _saltsForProxy(type(WBERAStakerVault).creationCode),
            _saltsForProxy(type(IncentivesCollector).creationCode)
        );

        address predictedAddress = _predictAddressWithArgs(type(IncentivesCollectorDeployer).creationCode, args);
        console2.log("IncentivesCollectorDeployer predicted address:", predictedAddress);
        // approve the deployer to spend the tokens
        WBERA.approve(predictedAddress, INITIAL_DEPOSIT_AMOUNT);

        // log the allowance
        console2.log("WBERA allowance of the deployer:", WBERA.allowance(msg.sender, predictedAddress));

        // deploy the IncentivesCollectorDeployer
        IncentivesCollectorDeployer incentivesCollectorDeployer = IncentivesCollectorDeployer(
            _deployWithArgs(
                "IncentivesCollectorDeployer", type(IncentivesCollectorDeployer).creationCode, args, predictedAddress
            )
        );
        wberaStakerVault = incentivesCollectorDeployer.wberaStakerVault();
        incentivesCollector = incentivesCollectorDeployer.incentivesCollector();

        console2.log("IncentivesCollectorDeployer deployed at", address(incentivesCollectorDeployer));
        console2.log("WBERAStakerVault deployed at", address(wberaStakerVault));
        console2.log("IncentivesCollector deployed at", address(incentivesCollector));

        //  grant MANAGER and PAUSER roles to the deployer
        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        RBAC.RoleDescription memory incentiveFeeCollectorManagerRole = RBAC.RoleDescription({
            contractName: "IncentivesCollector",
            contractAddr: address(incentivesCollector),
            name: "MANAGER_ROLE",
            role: incentivesCollector.MANAGER_ROLE()
        });

        RBAC.RoleDescription memory incentiveFeeCollectorPauserRole = RBAC.RoleDescription({
            contractName: "IncentivesCollector",
            contractAddr: address(incentivesCollector),
            name: "PAUSER_ROLE",
            role: incentivesCollector.PAUSER_ROLE()
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
        console2.log("Granted MANAGER and PAUSER roles to the deployer for IncentivesCollector");
    }
}
