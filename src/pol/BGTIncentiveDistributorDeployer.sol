// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BGTIncentiveDistributor } from "src/pol/rewards/BGTIncentiveDistributor.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";

contract BGTIncentiveDistributorDeployer is Create2Deployer {
    BGTIncentiveDistributor public bgtIncentiveDistributor;

    constructor(address owner, uint256 bgtIncentiveDistributorSalt) {
        _deployBGTIncentiveDistributor(owner, bgtIncentiveDistributorSalt);
    }

    /// @notice Deploy BGTIncentiveDistributor contract
    function _deployBGTIncentiveDistributor(
        address owner,
        uint256 bgtIncentiveDistributorSalt
    )
        internal
        returns (address)
    {
        address bgtIncentiveDistributorImpl = deployWithCreate2(1, type(BGTIncentiveDistributor).creationCode);
        bgtIncentiveDistributor =
            BGTIncentiveDistributor(deployProxyWithCreate2(bgtIncentiveDistributorImpl, bgtIncentiveDistributorSalt));
        bgtIncentiveDistributor.initialize(owner);
        return address(bgtIncentiveDistributor);
    }
}
