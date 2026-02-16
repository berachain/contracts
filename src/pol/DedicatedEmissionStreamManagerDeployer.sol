// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { DedicatedEmissionStreamManager } from "src/pol/rewards/DedicatedEmissionStreamManager.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { Salt } from "src/base/Salt.sol";

contract DedicatedEmissionStreamManagerDeployer is Create2Deployer {
    DedicatedEmissionStreamManager public dedicatedEmissionStreamManager;

    constructor(address owner, address distributor, address beraChef, Salt memory dedicatedEmissionStreamManagerSalt) {
        _deployDedicatedEmissionStreamManager(owner, distributor, beraChef, dedicatedEmissionStreamManagerSalt);
    }

    /// @notice Deploy DedicatedEmissionStreamManager contract
    function _deployDedicatedEmissionStreamManager(
        address owner,
        address distributor,
        address beraChef,
        Salt memory dedicatedEmissionStreamManagerSalt
    )
        internal
        returns (address)
    {
        address dedicatedEmissionStreamManagerImpl = deployWithCreate2(
            dedicatedEmissionStreamManagerSalt.implementation, type(DedicatedEmissionStreamManager).creationCode
        );
        dedicatedEmissionStreamManager = DedicatedEmissionStreamManager(
            deployProxyWithCreate2(dedicatedEmissionStreamManagerImpl, dedicatedEmissionStreamManagerSalt.proxy)
        );
        dedicatedEmissionStreamManager.initialize(owner, distributor, beraChef);
        return address(dedicatedEmissionStreamManager);
    }
}
