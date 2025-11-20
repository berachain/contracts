// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Create2Deployer } from "../base/Create2Deployer.sol";
import { Salt } from "../base/Salt.sol";
import { PythPriceOracle } from "./PythPriceOracle.sol";

contract PythPriceOracleDeployer is Create2Deployer {
    /// @notice The PythPriceOracle contract.
    // solhint-disable-next-line immutable-vars-naming
    PythPriceOracle public immutable oracle;

    constructor(address governance, Salt memory oracleSalt) {
        // deploy the PythPriceOracle implementation
        address oracleImpl = deployWithCreate2(oracleSalt.implementation, type(PythPriceOracle).creationCode);
        // deploy the PythPriceOracle proxy
        oracle = PythPriceOracle(deployProxyWithCreate2(oracleImpl, oracleSalt.proxy));

        // initialize the contracts
        oracle.initialize(governance);
    }
}
