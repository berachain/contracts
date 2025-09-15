// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/console2.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { ForceTransferBera } from "../logic/ForceTransferBera.sol";
import { BGTDeployer } from "src/pol/BGTDeployer.sol";
import { BGT_ADDRESS } from "../POLAddresses.sol";
import { BGT_SALT } from "../POLSalts.sol";

contract DeployBGTScript is BaseScript, ForceTransferBera {
    uint256 internal constant TESTNET_RESERVE_BERA_AMOUNT = 30e6 ether; // 30M

    function run() public broadcast {
        BGTDeployer bgtDeployer = new BGTDeployer(msg.sender, BGT_SALT);
        address bgt = address(bgtDeployer.bgt());
        _checkDeploymentAddress("BGT", bgt, BGT_ADDRESS);

        // NOTE: DOUBLE CHECK TESTNET ENV FLAG BEFORE DEPLOYMENT
        if (_isTestnet) {
            // Create a reserve of BERA for the BGT contract
            forceSafeTransferBERATo(BGT_ADDRESS, TESTNET_RESERVE_BERA_AMOUNT);
            require(BGT_ADDRESS.balance == TESTNET_RESERVE_BERA_AMOUNT, "BERA reserve not transferred to BGT contract");
        }
    }
}
