// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { CollateralVault } from "src/honey/CollateralVault.sol";
import { COLLATERAL_VAULT_IMPL } from "../HoneyAddresses.sol";

contract DeployCollateralVaultImplScript is BaseScript, Create2Deployer {
    function run() public broadcast {
        address newCollateralVaultImpl = deployWithCreate2(0, type(CollateralVault).creationCode);
        require(newCollateralVaultImpl == COLLATERAL_VAULT_IMPL, "Implementation not deployed at desired address");
        console2.log("CollateralVault implementation deployed successfully");
        console2.log("CollateralVault implementation address:", newCollateralVaultImpl);
    }
}
