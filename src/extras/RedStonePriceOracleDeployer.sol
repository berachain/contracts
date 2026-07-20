// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Create2Deployer } from "../base/Create2Deployer.sol";
import { Salt } from "../base/Salt.sol";
import { RedStonePriceOracle } from "./RedStonePriceOracle.sol";

contract RedStonePriceOracleDeployer is Create2Deployer {
    /// @notice The RedStonePriceOracle contract.
    // solhint-disable-next-line immutable-vars-naming
    RedStonePriceOracle public immutable oracle;

    constructor(address governance, address redstonePriceFeedAdapter, Salt memory oracleSalt) {
        // deploy the RedStonePriceOracle implementation
        address oracleImpl = deployWithCreate2(oracleSalt.implementation, type(RedStonePriceOracle).creationCode);
        // deploy the RedStonePriceOracle proxy
        oracle = RedStonePriceOracle(deployProxyWithCreate2(oracleImpl, oracleSalt.proxy));

        // initialize the contracts
        oracle.initialize(governance, redstonePriceFeedAdapter);
    }
}
