// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { RBAC } from "../../base/RBAC.sol";
import { BGTIncentiveDistributor } from "src/pol/rewards/BGTIncentiveDistributor.sol";
import { BGTIncentiveDistributorDeployer } from "src/pol/BGTIncentiveDistributorDeployer.sol";

import { BGT_INCENTIVE_DISTRIBUTOR_SALT } from "../POLSalts.sol";
import { BGT_INCENTIVE_DISTRIBUTOR_ADDRESS } from "../POLAddresses.sol";

contract DeployBGTIncentiveDistributorScript is BaseScript, RBAC {
    function run() public broadcast {
        BGTIncentiveDistributorDeployer bgtIncentiveDistributor =
            new BGTIncentiveDistributorDeployer(msg.sender, BGT_INCENTIVE_DISTRIBUTOR_SALT);
        address bgtIncentiveDistributorAddress = address(bgtIncentiveDistributor.bgtIncentiveDistributor());
        _checkDeploymentAddress(
            "BGTIncentiveDistributor", bgtIncentiveDistributorAddress, BGT_INCENTIVE_DISTRIBUTOR_ADDRESS
        );

        //  grant MANAGER and PAUSER roles to the deployer
        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        RBAC.RoleDescription memory bgtIncentiveDistributorManagerRole = RBAC.RoleDescription({
            contractName: "BGTIncentiveDistributor",
            contractAddr: BGT_INCENTIVE_DISTRIBUTOR_ADDRESS,
            name: "MANAGER_ROLE",
            role: BGTIncentiveDistributor(bgtIncentiveDistributorAddress).MANAGER_ROLE()
        });

        RBAC.RoleDescription memory bgtIncentiveDistributorPauserRole = RBAC.RoleDescription({
            contractName: "BGTIncentiveDistributor",
            contractAddr: BGT_INCENTIVE_DISTRIBUTOR_ADDRESS,
            name: "PAUSER_ROLE",
            role: BGTIncentiveDistributor(bgtIncentiveDistributorAddress).PAUSER_ROLE()
        });

        _grantRole(bgtIncentiveDistributorManagerRole, deployer);
        _grantRole(bgtIncentiveDistributorPauserRole, deployer);
    }
}
