// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { BGT } from "./BGT.sol";
import { Create2Deployer } from "../base/Create2Deployer.sol";

contract BGTDeployer is Create2Deployer {
    /// @notice The BGT contract.
    // solhint-disable-next-line immutable-vars-naming
    BGT public immutable bgt;

    /// @notice Constructor for the BGTDeployer.
    /// @param owner The owner of the BGT contract.
    /// @param bgtSalt The salt for the BGT contract.
    constructor(address owner, uint256 bgtSalt) {
        bgt = BGT(deployWithCreate2(bgtSalt, type(BGT).creationCode));
        bgt.initialize(owner);

        require(keccak256(bytes(bgt.CLOCK_MODE())) == keccak256("mode=timestamp"), "BGT CLOCK_MODE is incorrect");
    }
}
