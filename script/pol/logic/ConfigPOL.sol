// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/console2.sol";
import { Storage } from "../../base/Storage.sol";

/// @dev This contract is used to configure the POL contracts.
abstract contract ConfigPOL is Storage {
    /// @dev Set the reward allocation block delay
    function _setRewardAllocationBlockDelay(uint64 rewardAllocationBlockDelay) internal {
        console2.log("\n\nSetting reward allocation block delay on BeraChef...");
        beraChef.setRewardAllocationBlockDelay(rewardAllocationBlockDelay);
        require(
            beraChef.rewardAllocationBlockDelay() == rewardAllocationBlockDelay,
            "ConfigPOL: failed to set reward allocation delay"
        );
        console2.log("Set the reward allocation delay to be %d blocks", rewardAllocationBlockDelay);
    }

    /// @dev Set deployed addresses to BGT
    function _setBGTAddresses(address bgtStaker, address distributor, address blockRewardController) internal {
        console2.log("\n\nSetting deployed addresses to BGT...");
        // Set the staker
        bgt.setStaker(bgtStaker);
        require(address(bgt.staker()) == bgtStaker, "ConfigPOL: failed to set staker");
        console2.log("Set the BGTStaker to be %s.", bgtStaker);

        // Set the distributor
        bgt.whitelistSender(distributor, true);
        require(bgt.isWhitelistedSender(distributor), "ConfigPOL: failed to whitelist distributor");
        console2.log("Set the Distributor to be %s.", distributor);

        // set the minter
        bgt.setMinter(blockRewardController);
        require(bgt.minter() == blockRewardController, "ConfigPOL: failed to set minter");
        console2.log("Set minter to be %s.", blockRewardController);
    }
}
