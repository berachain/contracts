// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { RBAC } from "../../base/RBAC.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { AddressBook } from "../../base/AddressBook.sol";

import { RewardAllocatorFactory } from "src/pol/rewards/RewardAllocatorFactory.sol";
import { RewardAllocatorFactoryDeployer } from "src/pol/RewardAllocatorFactoryDeployer.sol";

contract DeployRewardAllocatorFactoryScript is RBAC, BaseScript, AddressBook {
    constructor() AddressBook(_chainType) { }

    function run() public pure {
        console2.log("Please run specific function.");
    }

    /// @notice Deploy the  RewardAllocatorFactory contract.
    /// @dev This function is used to deploy the RewardAllocatorFactory contract.
    function deployRewardAllocatorFactory(address governance, address allocationBot) public broadcast {
        console2.log("deploying RewardAllocatorFactory");
        console2.log("governance address:", governance);
        console2.log("allocationBot address:", allocationBot);

        // deploy the RewardAllocatorFactory with deployer as the owner
        RewardAllocatorFactoryDeployer rewardAllocatorFactoryDeployer = new RewardAllocatorFactoryDeployer(
            msg.sender, _polAddresses.beraChef, _saltsForProxy(type(RewardAllocatorFactory).creationCode)
        );
        console2.log("RewardAllocatorFactoryDeployer deployed at", address(rewardAllocatorFactoryDeployer));

        RewardAllocatorFactory rewardAllocatorFactory = rewardAllocatorFactoryDeployer.rewardAllocatorFactory();

        _checkDeploymentAddress(
            "RewardAllocatorFactory Impl",
            address(rewardAllocatorFactoryDeployer.rewardAllocatorFactoryImpl()),
            _polAddresses.rewardAllocatorFactoryImpl
        );
        _checkDeploymentAddress(
            "RewardAllocatorFactory", address(rewardAllocatorFactory), _polAddresses.rewardAllocatorFactory
        );

        RBAC.AccountDescription memory deployerAccount =
            RBAC.AccountDescription({ name: "deployer", addr: msg.sender });
        RBAC.AccountDescription memory governanceAccount =
            RBAC.AccountDescription({ name: "governance", addr: governance });

        RBAC.AccountDescription memory allocationBotAccount =
            RBAC.AccountDescription({ name: "allocationBot", addr: allocationBot });

        // grant the allocation bot the ALLOCATION_SETTER_ROLE
        RBAC.RoleDescription memory allocationSetterRole = RBAC.RoleDescription({
            contractName: "RewardAllocatorFactory",
            contractAddr: _polAddresses.rewardAllocatorFactory,
            name: "ALLOCATION_SETTER_ROLE",
            role: rewardAllocatorFactory.ALLOCATION_SETTER_ROLE()
        });
        _grantRole(allocationSetterRole, allocationBotAccount);

        // transfer the DEFAULT_ADMIN_ROLE to the governance address
        RBAC.RoleDescription memory defaultAdminRole = RBAC.RoleDescription({
            contractName: "RewardAllocatorFactory",
            contractAddr: _polAddresses.rewardAllocatorFactory,
            name: "DEFAULT_ADMIN_ROLE",
            role: rewardAllocatorFactory.DEFAULT_ADMIN_ROLE()
        });
        _transferRole(defaultAdminRole, deployerAccount, governanceAccount);
    }
}
