// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { CollateralVault } from "src/honey/CollateralVault.sol";
import { HoneyFactory } from "src/honey/HoneyFactory.sol";
import { HONEY_FACTORY_ADDRESS, COLLATERAL_VAULT_IMPL } from "../HoneyAddresses.sol";

contract DeployCollateralVaultImplScript is BaseScript, Create2Deployer {
    function run() public broadcast {
        address newCollateralVaultImpl = deployWithCreate2(0, type(CollateralVault).creationCode);
        require(newCollateralVaultImpl == COLLATERAL_VAULT_IMPL, "Implementation not deployed at desired address");
        console2.log("CollateralVault implementation deployed successfully");
        console2.log("CollateralVault implementation address:", newCollateralVaultImpl);
    }

    /// @dev This function is only for testnet or test purposes.
    function upgradeToTestnet() public broadcast {
        console2.log("New CollateralVault implementation address:", COLLATERAL_VAULT_IMPL);
        _validateCode("CollateralVault", COLLATERAL_VAULT_IMPL);

        address beacon = HoneyFactory(HONEY_FACTORY_ADDRESS).beacon();
        UpgradeableBeacon(beacon).upgradeTo(COLLATERAL_VAULT_IMPL);
        console2.log("CollateralVault upgraded successfully");
    }
}
