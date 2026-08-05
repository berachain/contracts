// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";
import { Create2Deployer } from "../base/Create2Deployer.sol";
import { Salt } from "../base/Salt.sol";
import { BUSD } from "./BUSD.sol";
import { BUSDFactory } from "./BUSDFactory.sol";
import { BUSDFactoryReader } from "./BUSDFactoryReader.sol";

import { CollateralVault } from "./VaultAdmin.sol";

/// @title BUSDDeployer
/// @author Berachain Team
/// @notice The BUSDDeployer contract is responsible for deploying the BUSD contracts.
contract BUSDDeployer is Create2Deployer {
    /// @notice The BUSD contract.
    // solhint-disable-next-line immutable-vars-naming
    BUSD public immutable busd;

    /// @notice The HoneyFactory contract.
    // solhint-disable-next-line immutable-vars-naming
    BUSDFactory public immutable busdFactory;

    BUSDFactoryReader public immutable busdFactoryReader;

    constructor(
        address governance,
        address polFeeCollector,
        address feeReceiver,
        Salt memory busdSalt,
        Salt memory busdFactorySalt,
        Salt memory busdFactoryReaderSalt,
        address priceOracle
    ) {
        // deploy the beacon
        address beacon = address(new UpgradeableBeacon(governance, address(new CollateralVault())));

        // deploy the BUSD implementation
        address busdImpl = deployWithCreate2(busdSalt.implementation, type(BUSD).creationCode);
        // deploy the Honey proxy
        busd = BUSD(deployProxyWithCreate2(busdImpl, busdSalt.proxy));

        // deploy the BUSDFactory implementation
        address busdFactoryImpl = deployWithCreate2(busdFactorySalt.implementation, type(BUSDFactory).creationCode);
        // deploy the BUSDFactory proxy
        busdFactory = BUSDFactory(deployProxyWithCreate2(busdFactoryImpl, busdFactorySalt.proxy));

        // deploy the BUSDFactoryReader implementation
        address busdFactoryReaderImpl =
            deployWithCreate2(busdFactoryReaderSalt.implementation, type(BUSDFactoryReader).creationCode);
        // Deploy the BUSDFactoryReader proxy
        busdFactoryReader =
            BUSDFactoryReader(deployProxyWithCreate2(busdFactoryReaderImpl, busdFactoryReaderSalt.proxy));

        // initialize the contracts
        busd.initialize(governance, address(busdFactory));
        busdFactory.initialize(governance, address(busd), polFeeCollector, feeReceiver, priceOracle, beacon);
        busdFactoryReader.initialize(governance, address(busdFactory));
    }
}
