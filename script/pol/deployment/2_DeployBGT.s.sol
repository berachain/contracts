// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BaseScript } from "../../base/Base.s.sol";
import { ChainType } from "../../base/Chain.sol";
import { ForceTransferBera } from "../logic/ForceTransferBera.sol";
import { BGT } from "src/pol/BGT.sol";
import { BGTDeployer } from "src/pol/BGTDeployer.sol";
import { AddressBook } from "../../base/AddressBook.sol";

contract DeployBGTScript is BaseScript, ForceTransferBera, AddressBook {
    uint256 internal constant TESTNET_RESERVE_BERA_AMOUNT = 30e6 ether; // 30M

    constructor() AddressBook(_chainType) { }

    function run() public broadcast {
        BGTDeployer bgtDeployer = new BGTDeployer(msg.sender, _salt(type(BGT).creationCode));
        address bgt = address(bgtDeployer.bgt());
        _checkDeploymentAddress("BGT", bgt, _polAddresses.bgt);

        if (_chainType == ChainType.Testnet || _chainType == ChainType.Anvil) {
            // Create a reserve of BERA for the BGT contract
            forceSafeTransferBERATo(_polAddresses.bgt, TESTNET_RESERVE_BERA_AMOUNT);
            require(
                _polAddresses.bgt.balance == TESTNET_RESERVE_BERA_AMOUNT,
                "BERA reserve not transferred to BGT contract"
            );
        }
    }
}
