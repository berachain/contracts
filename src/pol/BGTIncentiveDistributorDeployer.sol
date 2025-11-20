// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BGTIncentiveDistributor } from "src/pol/rewards/BGTIncentiveDistributor.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { Salt } from "src/base/Salt.sol";

contract BGTIncentiveDistributorDeployer is Create2Deployer {
    BGTIncentiveDistributor public bgtIncentiveDistributor;

    constructor(address owner, Salt memory bgtIncentiveDistributorSalt) {
        _deployBGTIncentiveDistributor(owner, bgtIncentiveDistributorSalt);
    }

    /// @notice Deploy BGTIncentiveDistributor contract
    function _deployBGTIncentiveDistributor(
        address owner,
        Salt memory bgtIncentiveDistributorSalt
    )
        internal
        returns (address)
    {
        address bgtIncentiveDistributorImpl =
            deployWithCreate2(bgtIncentiveDistributorSalt.implementation, type(BGTIncentiveDistributor).creationCode);
        bgtIncentiveDistributor = BGTIncentiveDistributor(
            deployProxyWithCreate2(bgtIncentiveDistributorImpl, bgtIncentiveDistributorSalt.proxy)
        );
        bgtIncentiveDistributor.initialize(owner);
        return address(bgtIncentiveDistributor);
    }
}
