// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BaseScript } from "../../base/Base.s.sol";
import { RBAC } from "../../base/RBAC.sol";
import { BGTIncentiveDistributor } from "src/pol/rewards/BGTIncentiveDistributor.sol";
import { BGTIncentiveDistributorDeployer } from "src/pol/BGTIncentiveDistributorDeployer.sol";
import { AddressBook } from "../../base/AddressBook.sol";

contract DeployBGTIncentiveDistributorScript is BaseScript, RBAC, AddressBook {
    constructor() AddressBook(_chainType) { }

    function run() public broadcast {
        BGTIncentiveDistributorDeployer bgtIncentiveDistributor =
            new BGTIncentiveDistributorDeployer(msg.sender, _saltsForProxy(type(BGTIncentiveDistributor).creationCode));
        address bgtIncentiveDistributorAddress = address(bgtIncentiveDistributor.bgtIncentiveDistributor());
        _checkDeploymentAddress(
            "BGTIncentiveDistributor", bgtIncentiveDistributorAddress, _polAddresses.bgtIncentiveDistributor
        );

        //  grant MANAGER and PAUSER roles to the deployer
        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        RBAC.RoleDescription memory bgtIncentiveDistributorManagerRole = RBAC.RoleDescription({
            contractName: "BGTIncentiveDistributor",
            contractAddr: _polAddresses.bgtIncentiveDistributor,
            name: "MANAGER_ROLE",
            role: BGTIncentiveDistributor(bgtIncentiveDistributorAddress).MANAGER_ROLE()
        });

        RBAC.RoleDescription memory bgtIncentiveDistributorPauserRole = RBAC.RoleDescription({
            contractName: "BGTIncentiveDistributor",
            contractAddr: _polAddresses.bgtIncentiveDistributor,
            name: "PAUSER_ROLE",
            role: BGTIncentiveDistributor(bgtIncentiveDistributorAddress).PAUSER_ROLE()
        });

        _grantRole(bgtIncentiveDistributorManagerRole, deployer);
        _grantRole(bgtIncentiveDistributorPauserRole, deployer);
    }
}
