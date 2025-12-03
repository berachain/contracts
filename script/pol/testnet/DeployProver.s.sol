// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Script, console2 } from "forge-std/Script.sol";

import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { Distributor } from "src/pol/rewards/Distributor.sol";
import { MockERC20 } from "test/mock/token/MockERC20.sol";
import { NoopBeraChef } from "test/mock/pol/NoopBeraChef.sol";
import { NoopBlockRewardController } from "test/mock/pol/NoopBlockRewardController.sol";

/// @notice Contains logic to deploy a lightweight Distributor for testing the proof system.
contract DeployProver is Create2Deployer, Script {
    uint64 internal constant ZERO_VALIDATOR_PUBKEY_G_INDEX = 3_254_554_418_216_960;
    uint64 internal constant PROPOSER_INDEX_G_INDEX = 9;
    uint256 internal constant SALT = 69_420;

    function run() public virtual {
        vm.startBroadcast();

        address beraChef = address(new NoopBeraChef());
        console2.log("NoopBeraChef deployed at: %s", address(beraChef));

        MockERC20 bgt = new MockERC20();
        bgt.initialize("Mock BGT", "mBGT");
        console2.log("MockBGT deployed at: %s", address(bgt));

        address blockRewardController = address(new NoopBlockRewardController());
        console2.log("NoopBlockRewardController deployed at: %s", address(blockRewardController));

        address governance = msg.sender;
        console2.log("Governance: %s", governance);

        address distributorImpl = deployWithCreate2(SALT, type(Distributor).creationCode);
        console2.log("Distributor implementation deployed at: %s", address(distributorImpl));

        address distributorProxy = deployProxyWithCreate2(distributorImpl, SALT);
        console2.log("Distributor proxy deployed at: %s", address(distributorProxy));

        Distributor(distributorProxy)
            .initialize(
                beraChef,
                address(bgt),
                blockRewardController,
                governance,
                ZERO_VALIDATOR_PUBKEY_G_INDEX,
                PROPOSER_INDEX_G_INDEX
            );

        vm.stopBroadcast();
    }
}
