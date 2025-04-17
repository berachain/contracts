// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";
import { Create2Deployer } from "../base/Create2Deployer.sol";
import { Honey } from "./Honey.sol";
import { HoneyFactory } from "./HoneyFactory.sol";
import { HoneyFactoryReader } from "./HoneyFactoryReader.sol";

import { CollateralVault } from "./VaultAdmin.sol";

/// @title HoneyDeployer
/// @author Berachain Team
/// @notice The HoneyDeployer contract is responsible for deploying the Honey contracts.
contract HoneyDeployer is Create2Deployer {
    /// @notice The Honey contract.
    // solhint-disable-next-line immutable-vars-naming
    Honey public immutable honey;

    /// @notice The HoneyFactory contract.
    // solhint-disable-next-line immutable-vars-naming
    HoneyFactory public immutable honeyFactory;

    HoneyFactoryReader public immutable honeyFactoryReader;

    constructor(
        address governance,
        address polFeeCollector,
        address feeReceiver,
        uint256 honeySalt,
        uint256 honeyFactorySalt,
        uint256 honeyFactoryReaderSalt,
        address priceOracle
    ) {
        // deploy the beacon
        address beacon = address(new UpgradeableBeacon(governance, address(new CollateralVault())));

        // deploy the Honey implementation
        address honeyImpl = deployWithCreate2(0, type(Honey).creationCode);
        // deploy the Honey proxy
        honey = Honey(deployProxyWithCreate2(honeyImpl, honeySalt));

        // deploy the HoneyFactory implementation
        address honeyFactoryImpl = deployWithCreate2(0, type(HoneyFactory).creationCode);
        // deploy the HoneyFactory proxy
        honeyFactory = HoneyFactory(deployProxyWithCreate2(honeyFactoryImpl, honeyFactorySalt));

        // deploy the HoneyFactoryReader implementation
        address honeyFactoryReaderImpl = deployWithCreate2(0, type(HoneyFactoryReader).creationCode);
        // Deploy the HoneyFactoryReader proxy
        honeyFactoryReader = HoneyFactoryReader(deployProxyWithCreate2(honeyFactoryReaderImpl, honeyFactoryReaderSalt));

        // initialize the contracts
        honey.initialize(governance, address(honeyFactory));
        honeyFactory.initialize(governance, address(honey), polFeeCollector, feeReceiver, priceOracle, beacon);
        honeyFactoryReader.initialize(governance, address(honeyFactory));
    }
}
